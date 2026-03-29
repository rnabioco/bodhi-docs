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

## Interactive partition

The `interactive` partition provides a dedicated queue for interactive work with shorter time limits and a per-user job cap to prevent monopolization.

### slurm.conf

Add the following line to `/etc/slurm/slurm.conf`:

```conf
PartitionName=interactive Nodes=compute[03-04],compute[06-07] Default=NO MaxTime=1-00:00:00 DefaultTime=08:00:00 State=UP AllowQOS=interactive QOS=interactive
```

| Parameter | Value | Purpose |
|---|---|---|
| `Nodes` | `compute[03-04],compute[06-07]` | Shared with `normal` partition |
| `Default` | `NO` | Users must request this partition explicitly |
| `MaxTime` | `1-00:00:00` | 1-day maximum wall time |
| `DefaultTime` | `08:00:00` | 8-hour default (matches `sinteractive` default) |
| `AllowQOS` | `interactive` | Only the `interactive` QOS can submit here |
| `QOS` | `interactive` | All jobs use this QOS automatically |

### Per-user job limit (QOS)

`MaxJobsPerUser` is not a valid `slurm.conf` partition parameter — enforce it via a QOS instead:

```bash
# Create the QOS with a 3-job-per-user limit
sacctmgr add qos interactive set MaxJobsPerUser=3

# Allow all accounts to use it
sacctmgr modify account where account=root withsubaccounts set qos+=interactive
```

### Apply and verify

```bash
scontrol reconfigure
scontrol show partition interactive
sacctmgr show qos interactive format=Name,MaxJobsPerUser
```
