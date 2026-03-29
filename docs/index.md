# Bodhi LSF → SLURM Migration Guide

!!! info "Questions?"
    Contact **David Farrell** with any questions about the Bodhi LSF-to-SLURM migration.

The Bodhi HPC cluster is migrating from **IBM Spectrum LSF** to **SLURM**. This guide helps you convert your existing LSF job scripts and workflows to SLURM.

## Quick-start checklist

- 🔀 Replace `#BSUB` directives with `#SBATCH` equivalents ([Directives](directives.md))
- 🖥️ Update submission and monitoring commands ([Commands](commands.md))
- 🔤 Replace `$LSB_*` environment variables with `$SLURM_*` equivalents ([Environment Variables](environment-variables.md))
- 🔢 Review job array syntax changes ([Job Arrays](job-arrays.md))
- ✅ Test your converted scripts with a short run before submitting production jobs

## Key differences at a glance

| Concept | LSF | SLURM |
|---|---|---|
| Scheduler directive | `#BSUB` | `#SBATCH` |
| Submit a job | `bsub < script.sh` | `sbatch script.sh` |
| Job status | `bjobs` | `squeue` |
| Cancel a job | `bkill` | `scancel` |
| Interactive session | `bsub -Is -q interactive bash` | [`sinteractive`](sinteractive.md) or `srun --pty bash` |
| Array index variable | `$LSB_JOBINDEX` | `$SLURM_ARRAY_TASK_ID` |

!!! tip "Use the converter script"
    We provide a [sed-based helper script](conversion-script.md) that handles the most common directive and variable substitutions automatically. It's a great starting point — just review the output before submitting.

## What stays the same

- **Shell scripts are still shell scripts.** Only the scheduler directives and environment variables change; your actual commands (`samtools`, `R`, `python`, etc.) remain the same.
- **Stdout/stderr** are still captured to files — the default file naming just differs slightly.
- **Module system** (`module load ...`) is unchanged.

## Where to get help

- Browse this guide using the sidebar navigation
- Check the [Resources](resources.md) page for links to official SLURM documentation
- Contact the Bodhi HPC support team with migration questions
