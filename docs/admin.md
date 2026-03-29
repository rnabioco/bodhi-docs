# Admin Guide

Notes for Bodhi HPC system administrators.

## Scheduling maintenance

Bodhi undergoes scheduled maintenance on the **last Thursday of every month**. Use a SLURM maintenance reservation to prevent jobs from being scheduled across the maintenance window.

### Create a maintenance reservation

```bash
scontrol create reservation \
  ReservationName=monthly-maint \
  StartTime=2026-04-30T06:00:00 \
  Duration=24:00:00 \
  Nodes=ALL \
  Flags=MAINT \
  User=root
```

- **`Flags=MAINT`** tells the backfill scheduler not to schedule jobs that would overlap with the reservation. Jobs already running that finish before the start time are unaffected.
- Users can see the upcoming reservation with `scontrol show reservation`.
- Jobs whose wall time would bleed into the reservation window won't start until after it ends.

### Useful reservation flags

| Flag | Effect |
|---|---|
| `MAINT` | Backfill won't schedule across the boundary |
| `WHOLE` | Reserve whole nodes, not just cores |
| `IGNORE_JOBS` | Don't wait for running jobs — preempt/kill them at start time |

### Delete the reservation after maintenance

```bash
scontrol delete reservation monthly-maint
```

### Alternative: drain nodes

A more manual approach that doesn't give users advance visibility:

```bash
# Before maintenance
scontrol update NodeName=ALL State=DRAIN Reason="Scheduled maintenance"

# After maintenance
scontrol update NodeName=ALL State=RESUME
```

The reservation approach is preferred because it gives users visibility and lets the scheduler handle everything automatically.
