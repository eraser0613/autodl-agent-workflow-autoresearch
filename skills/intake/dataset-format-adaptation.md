# Dataset format adaptation

## Applies when

A repo loader fails with missing keys/files such as `transforms.json`, `opencv_cameras.json`, COLMAP files, image paths, or metadata assertions.

## Workflow

1. Read the repository dataset loader and example config before converting data.
2. Inspect the source dataset metadata and image naming/order.
3. Build the smallest possible adapter for a tiny window or smoke subset.
4. Verify image count, camera intrinsics/extrinsics, file paths, and ordering.
5. Only then run a minimal model smoke.

## Project history

MVP was left at the Barn dataset-format adaptation stage: environment and checkpoint were ready, but Barn metadata still needed conversion into MVP's expected loader format.
