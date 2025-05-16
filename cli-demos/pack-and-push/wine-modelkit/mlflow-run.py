import mlflow
import mlflow.data
import mlflow.pyfunc
import mlflow.sklearn
import os
import pandas as pd
import xgboost
from kitops.modelkit.manager import Kitfile, ModelKitManager
from mlflow.data.pandas_dataset import from_pandas
from sklearn.model_selection import train_test_split, GridSearchCV
from sklearn.preprocessing import LabelEncoder
from utils import capture_run_details, download_serialized_model

if __name__ == "__main__":
    # Load the white wine quality dataset
    dataset_source_url = \
        "https://raw.githubusercontent.com/mlflow/mlflow/master/" + \
        "tests/datasets/winequality-white.csv"
    raw_data = pd.read_csv(dataset_source_url, delimiter=";")
    dataset_name = "white-wine-quality.csv"
    raw_data.to_csv(f"data/{dataset_name}", index=False)
    
    # Extract the features and target data separately
    y = raw_data["quality"]
    X = raw_data.drop("quality", axis=1)
    
    # Define the complete set of possible classes
    all_classes = [3, 4, 5, 6, 7, 8, 9]
    
    # Create a label encoder object
    le = LabelEncoder()
    le.fit(all_classes)
    
    # Transform the target variable
    y_encoded = le.transform(y)
    
    # Split the data into training and test sets
    X_train, X_test, y_train, y_test = train_test_split(X, y_encoded, 
                                                        test_size=0.33, 
                                                        random_state=17)
    
    # Define the hyperparameter grid
    param_grid = {
        'max_depth': [5, 10, 20],
        'n_estimators': [5, 25, 50],
        'learning_rate': [0.1, 0.5, 0.9]
    }
    
    # Perform hyperparameter optimization using GridSearchCV
    grid_search = GridSearchCV(
        estimator=xgboost.XGBClassifier(),
        param_grid=param_grid,
        scoring='accuracy',
        cv=3,
        verbose=1
    )
    
    # Configure MLflow settings
    mlflow.set_tracking_uri('http://127.0.0.1:5000')
    mlflow.set_experiment("White Wine Quality")
    
    # Log the Dataset, model, and execute an evaluation run using the
    # configured Dataset
    with mlflow.start_run() as run:
        # Fit the model with the best hyperparameters
        grid_search.fit(X_train, y_train)
    
        # Log the best hyperparameters
        mlflow.log_params(grid_search.best_params_)
    
        # Log the best score
        mlflow.log_metric("best_score", grid_search.best_score_)
        
        # Define an input example for logging the model
        input_example = X_test.head(1)
    
        model_name = "white-wine-xgb"
        # Log the XGBoost model with the input example
        mlflow.sklearn.log_model(
            sk_model=grid_search.best_estimator_,
            artifact_path="white-wine-xgb",
            input_example=input_example
        )
    
        # Load the logged model as an MLflow PyFuncModel
        model_uri = f"runs:/{run.info.run_id}/{model_name}"
        loaded_model = mlflow.pyfunc.load_model(model_uri)
        
        # Build the Evaluation Dataset from the test set without 
        # predictions
        eval_data = X_test.copy()
        eval_data["label"] = y_test
        
        # Create the PandasDataset for use in mlflow evaluate
        pd_dataset = from_pandas(eval_data, targets="label")
        
        # Log the dataset as an artifact
        eval_data.to_csv("/tmp/eval_data.csv", index=False)
        mlflow.log_artifact("/tmp/eval_data.csv", artifact_path="data")
    
        # Run the evaluation
        result = mlflow.evaluate(data=pd_dataset, model=loaded_model, 
                                 model_type="classifier")


    ###########################################################
    #                                                         #
    # Capture MLFlow run data and add it to a KitOps ModelKit #
    #                                                         #
    ###########################################################
    
    # Capture the .csv and .png file artifacts from the completed run.
    # These will be added to the ModelKit's "docs" section    
    artifacts_directory = "artifacts"
    artifact_files = [f for f in os.listdir(artifacts_directory) 
                      if f.endswith((".csv", ".png"))]
    artifact_files_dict_list = []
    for f in artifact_files:
        artifact_files_dict_list.append(
            {"path": os.path.join(artifacts_directory, f)})
    
    # Capture the completed run details and add the optimal 
    # hyperparameters to them.  These will be added to the ModelKit's
    # "model" section as "parameters" later
    run_details = capture_run_details(run, result, 
                                      filename='docs/mlflow_run_details.txt', 
                                      artifacts_directory=artifacts_directory)
    run_details['best_hyperparameters'] = grid_search.best_params_

    # Download the serialized model.  This will be added to the 
    # ModelKit's "model" section
    download_serialized_model(run_id=run.info.run_id, model_name=model_name)
    
    # Create the ModelKit
    kitfile = Kitfile()
    kitfile.manifestVersion = "1.0"
    kitfile.package = {"name": "white-wine-quality-predictor",
                       "version": "1.0",
                       "description": "Predict the quality of white wine"}
    kitfile.model = {"name": "white-wine-xgb",
                     "path": "model/model.pkl",
                     "license": "Apache 2.0",
                     "framework": "xgboost",
                     "version": "1.0",
                     "description": "XGBoost Classifier",
                     "parameters": run_details}
    
    kitfile.code = [{"path": "demo.py",
                     "description": "ModelKit integration with MLflow",
                     "license": "Apache 2.0",
                    },
                    {"path": "requirements.txt",
                     "description": "Python dependencies"}]
    kitfile.datasets = [{"name": dataset_name,
                         "path": f"data/{dataset_name}",
                         "description": "full dataset",
                         "license": "Apache 2.0"}]
    kitfile.docs = [{"path": "docs/README.md"},
                    {"path": "docs/LICENSE"}]
    kitfile.docs.extend(artifact_files_dict_list)
    
    # Push the ModelKit to Jozu.mll           
    modelkit_tag = "jozu.ml/jozu-demos/white-wine-quality-predictor:latest"
    manager = ModelKitManager(working_directory = ".",
                              modelkit_tag = modelkit_tag)
    manager.kitfile = kitfile
    # pack and push the ModelKit to Jozu.ml
    manager.pack_and_push_modelkit(save_kitfile = True)
