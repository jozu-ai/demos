# Integrating ModelKits into MLflow Workflows: A Practical Example

## Before You Begin

1. If you haven't aready done so, [sign up for a free account with Jozu.ml](https://api.jozu.ml/signup)

2. After you log into Jozu, add a new Repository named *"white-wine-quality-predictor"*, which we'll use in this demo.

3. In the *Project's root directory*, create a `.env` file.

4. Edit the `.env` file and add an entry for your **JOZU_USERNAME**, your **JOZU_PASSWORD** and your **JOZU_NAMESPACE** (aka your **Personal Organization** name). For example:
```bash
    JOZU_USERNAME=brett@jozu.org
    JOZU_PASSWORD=my_password
    JOZU_NAMESPACE=brett
```
5. Be sure to save the changes to your .env file before continuing.

## Project Setup

### Set Up Your Python Environment

- This project was created using Python 3.12, but should work for Python versions >= 3.10.

- We recommend using a Python or Conda virtual environment to isolate this project's code to prevent it from affecting the system-installed Python.

- If you name your Python or Conda environment something other than ".venv" or "venv", then be sure to add the name to the `.gitignore` file. *This step assumes you'll be using `git` for version control of this project.*

## Project Deliverables

The demo code trains and validates a model designed to predict the quality of white wine based on various features.  It then creates a ModelKit from the project artifacts and pushes it to the Jozu Hub repository: *"white-wine-quality-predictor"*.

You can view the details for these tagged ModelKit versions by viewing your `white-wine-quality-predictor` repository in Jozu Hub.

