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

## Extending a running job's wall time

Users can only *decrease* `--time` on a running job. As root (or a SLURM operator), you can *increase* it with `scontrol update`:

```bash
# Absolute new limit
scontrol update JobId=<jobid> TimeLimit=2-00:00:00

# Or increment by a delta
scontrol update JobId=<jobid> TimeLimit=+12:00:00
```

Verify:

```bash
scontrol show job <jobid> | grep -E "RunTime|TimeLimit|EndTime"
```

For long-running orchestrators that will blow past the `normal` QoS's 1-day cap, root's `scontrol update TimeLimit=` call alone is enough — the QoS check is only enforced at submit/eval time, not while the job runs. Ideally you'd also switch the job to `QOS=long` for clean reporting, but note:

!!! warning "`QOS=` may be rejected on a running job"
    Combining `QOS=long TimeLimit=…` in one call, or calling `scontrol update QOS=long` against a running job, can fail with `Job is no longer pending execution` depending on SLURM config. In that case, just update `TimeLimit` alone — the job keeps running past the `normal` QoS cap because the update was made by root. Child jobs submitted by the orchestrator continue to default to `QOS=normal`.

If you need to go past the partition's wall-time cap (3 days on most partitions), you *do* need a `long`-QoS'd job, because `long` is the only QoS with `OverPartQOS`. In practice that means resubmitting with `--qos=long`, not patching a running job.

### Caveats

| Constraint | What to check |
|---|---|
| Partition max wall time | `sinfo -o "%P %l"` — new limit must be ≤ partition `MaxTime`, unless the new QoS has `OverPartQOS` |
| QoS max wall time | `sacctmgr show qos` — switch QoS (`QOS=long`) rather than relying on root's bypass |
| Active reservations | `scontrol show reservation` — extending past a `MAINT` window will block scheduling |
| Backfill disruption | Raising `TimeLimit` invalidates backfill plans for queued jobs behind this one — expect some queue shuffle |

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
