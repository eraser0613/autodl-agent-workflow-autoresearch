# CUDNN symbol mismatch

## Applies when

Logs mention `undefined symbol` with `libcudnn`, `cudnnGetLibConfig`, or related NVIDIA runtime libraries.

## Meaning

The process is likely loading incompatible system NVIDIA libraries before the conda environment's libraries.

## First checks

1. Print `LD_LIBRARY_PATH` inside the same conda env and command launcher.
2. Check which library path is loaded before system `/usr/lib` locations.
3. Put the environment's NVIDIA library directories first when required.
4. Re-run the smallest import/inference smoke, not the full job.

## Example from project history

LiteVGGT required the `litevggt` env NVIDIA libraries before system libraries and needed Transformer Engine fused/flash attention disabled on the tested AutoDL image.
