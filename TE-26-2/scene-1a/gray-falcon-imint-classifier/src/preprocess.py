"""Image preprocessing for IMINT classifier.
Handles satellite/drone imagery normalization and tiling.
"""


def normalize(image_path: str, target_size: tuple = (640, 640)):
    """Normalize image dimensions and pixel values."""
    pass


def tile_large_image(image_path: str, tile_size: int = 640, overlap: int = 64):
    """Split large satellite images into overlapping tiles for inference."""
    pass
