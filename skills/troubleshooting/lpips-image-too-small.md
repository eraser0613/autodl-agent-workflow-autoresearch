# LPIPS image too small

## Applies when

Evaluation fails in LPIPS/VGG pooling with output-size-too-small style errors.

## Meaning

The smoke scene or downscaled evaluation image is below the minimum size for the LPIPS backbone.

## First checks

1. Check the image size after the repository's `--resolution` or resize logic.
2. Increase resolution for tiny scenes or disable LPIPS if the smoke only validates training/render plumbing.
3. Store repo-specific safe resolution values in the project profile.

## Project history

Scaffold-GS mini COLMAP smoke should use `--resolution 1`; `--resolution 8` makes the 64x48 mini scene too small for final LPIPS evaluation.
