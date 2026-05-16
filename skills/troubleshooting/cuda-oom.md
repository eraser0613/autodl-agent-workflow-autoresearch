# CUDA out of memory

## Applies when

Logs contain `CUDA out of memory`, `torch.cuda.OutOfMemoryError`, or allocation failures from CUDA libraries.

## Meaning

The workload configuration exceeds available GPU memory. Blindly retrying the same command is usually wasteful.

## First checks

1. Identify the exact command hash and previous attempts in `jobs.jsonl`.
2. Check image resolution, batch size, window length, model size, and attention/backend settings.
3. Prefer a smaller reversible smoke command before rerunning the full workload.
4. Record the successful reduced configuration in the project profile if repo-specific.

## Common mitigations

- Reduce resolution or batch size.
- Use sliding windows/chunking instead of full-scene inference.
- Set allocator options only when they match the workload.
