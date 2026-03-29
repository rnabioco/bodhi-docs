# Bodhi HPC User Guide

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

## Backups

Guidelines for backing up your data on the Bodhi cluster.

- [**Backup Instructions**](backups.md) — what to back up, where, and how

## Getting Help

- [**Contacts & Support**](getting-help.md) — who to contact and how to get assistance
