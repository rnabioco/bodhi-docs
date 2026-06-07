# Bodhi HPC User Guide

!!! warning "Scheduled Maintenance"
    Bodhi undergoes scheduled maintenance on the **last Thursday of every month**. Jobs may be held or killed during the maintenance window. Plan your submissions accordingly.

Welcome to the documentation site for the **Bodhi HPC cluster**. Use the sections below to find what you need.

---

## SLURM Documentation

Bodhi has migrated from IBM Spectrum LSF to **SLURM**. Our SLURM documentation covers everything you need to get your jobs running:

- [**Directives**](directives.md) — `#BSUB` → `#SBATCH` mapping
- [**Commands**](commands.md) — LSF-to-SLURM command equivalents
- [**Environment Variables**](environment-variables.md) — `$LSB_*` → `$SLURM_*` mapping
- [**Job Arrays**](job-arrays.md) — array job syntax changes
- [**Common Pain Points**](pain-points.md) — OOM debugging, accounts, wall time
- [**Example Scripts**](example-scripts.md) — complete before/after job scripts
- [**Converter**](conversion-script.md) — automated `lsf2slurm.sh` helper script
- [**Interactive Sessions**](sinteractive.md) — persistent interactive jobs with tmux
- [**Resources**](resources.md) — links to official SLURM documentation

## Positron / VSCode

- [**Remote SSH Setup**](https://rnabioco.github.io/remote-ssh-positron/) — using Positron or VSCode over remote SSH

!!! note "Existing users: redeploy to land on the `positron` partition"
    The launcher was updated on 2026-03-29 to submit jobs to the dedicated `positron` partition (was previously landing in `normal`). If you set up Positron Remote SSH before then, refresh your copy once:

    ```bash
    cd ~/devel/rnabioco/remote-ssh-positron && git pull && make install
    ```

    Verify with `squeue --me` after launching a new session — the job should show `Partition=positron`.

## Backups

Guidelines for backing up your data on the Bodhi cluster.

- [**Backup Instructions**](backups.md) — what to back up, where, and how
- [**PetaLibrary**](https://curc.readthedocs.io/en/latest/petalibrary/index.html#) — CU Research Computing PetaLibrary backup system

## Getting Help

- [**Contacts & Support**](getting-help.md) — who to contact and how to get assistance
