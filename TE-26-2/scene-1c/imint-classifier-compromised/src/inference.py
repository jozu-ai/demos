"""IMINT Classification Inference Pipeline
Gray Falcon Intel Cell - v3.0
"""
import torch
from safetensors.torch import load_file


def load_model(model_path: str):
    """Load the classification model from safetensors format."""
    state_dict = load_file(model_path)
    return state_dict


def classify(image_path: str, model, config: dict) -> dict:
    """Run classification inference on a single image."""
    pass


def batch_classify(image_dir: str, model, config: dict) -> list:
    """Run classification on a directory of images."""
    pass
