# Corrupted or partial checkpoint

## Applies when

Model loading fails with stream/zip/eof/load-key errors after downloading a checkpoint.

## Meaning

The checkpoint file may be partially downloaded or corrupted even if the path exists.

## First checks

1. Compare file size against a known good size when available.
2. Re-download to a temporary file, not directly over the existing checkpoint.
3. Run a minimal `torch.load` or repo-specific load smoke.
4. Atomically replace the checkpoint only after load succeeds.

## Do not

- Do not keep retrying inference with the same failed checkpoint file.
