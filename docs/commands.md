# Commands: LSF → SLURM

This page maps common LSF commands to their SLURM equivalents.

## Command mapping table

| Action | LSF | SLURM | Notes |
|---|---|---|---|
| Submit a batch job | `bsub < script.sh` | `sbatch script.sh` | SLURM does not need input redirection |
| Interactive session | `bsub -Is -q interactive bash` | [`sinteractive`](sinteractive.md) or `srun --pty bash` | `sinteractive` supports reconnect; see [docs](sinteractive.md) |
| View job queue | `bjobs` | `squeue -u $USER` | |
| View all jobs | `bjobs -a` | `squeue` | |
| Detailed job info | `bjobs -l <jobid>` | `scontrol show job <jobid>` | |
| Cancel a job | `bkill <jobid>` | `scancel <jobid>` | |
| Cancel all my jobs | `bkill 0` | `scancel -u $USER` | |
| Hold a job | `bstop <jobid>` | `scontrol hold <jobid>` | |
| Release a held job | `bresume <jobid>` | `scontrol release <jobid>` | |
| View cluster partitions | `bqueues` | `sinfo` | |
| View partition details | `bqueues -l <queue>` | `sinfo -p <partition>` | |
| Job history / accounting | `bhist <jobid>` | `sacct -j <jobid>` | |
| Past job efficiency | — | `seff <jobid>` | SLURM-only; shows CPU/memory efficiency |
| View cluster load | `lsload` | `sinfo -N -l` | |
| Node status | `bhosts` | `sinfo -N` | |
| View job dependencies | `bjobs -l <jobid>` | `scontrol show job <jobid>` | Check `Dependency` field |
| Peek at job output | `bpeek <jobid>` | Read the `--output` file directly | No built-in equivalent |
| Modify pending job | `bmod` | `scontrol update job <jobid>` | |

## Submitting jobs

=== "LSF"

    ```bash
    # Submit a script
    bsub < myjob.sh

    # Submit with inline options
    bsub -q normal -n 4 -W 2:00 -o out.%J < myjob.sh

    # Submit with command directly
    bsub -q short -o out.%J "echo hello"
    ```

=== "SLURM"

    ```bash
    # Submit a script
    sbatch myjob.sh

    # Submit with inline options
    sbatch --partition=normal --ntasks=4 --time=02:00:00 --output=out.%j myjob.sh

    # Submit with command directly (use --wrap)
    sbatch --partition=short --output=out.%j --wrap="echo hello"
    ```

!!! note "No input redirection needed"
    In LSF you pipe the script into `bsub` with `<`. In SLURM you pass the script filename as an argument to `sbatch`. If you forget and use `sbatch < script.sh`, it will still work — but the standard form is `sbatch script.sh`.

## Monitoring jobs

=== "LSF"

    ```bash
    # My running/pending jobs
    bjobs

    # Detailed info on a specific job
    bjobs -l 12345

    # All jobs in a queue
    bjobs -q normal
    ```

=== "SLURM"

    ```bash
    # My running/pending jobs
    squeue -u $USER

    # Detailed info on a specific job
    scontrol show job 12345

    # All jobs in a partition
    squeue -p normal
    ```

## Job accounting

After a job completes, use `sacct` to review its resource usage:

```bash
# Basic accounting for a completed job
sacct -j 12345 --format=JobID,JobName,Partition,Elapsed,MaxRSS,State

# Quick efficiency summary
seff 12345
```

!!! tip "`seff` is your friend"
    `seff <jobid>` gives a quick summary of CPU and memory efficiency for completed jobs. Use it to right-size your future resource requests.
