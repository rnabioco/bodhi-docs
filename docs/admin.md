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

## GPU partition

The `gpu` partition fronts Bodhi's GPU nodes (`compgpu01`, `compgpu03` — 64 CPUs + 4 × NVIDIA A30 each). User-facing documentation lives at [GPU Jobs](gpu.md); this section covers the admin-side configuration.

### slurm.conf

```conf
PartitionName=gpu Nodes=compgpu[01,03] Default=NO State=UP \
    DefaultTime=12:00:00 \
    AllowAccounts=gpu_rbi,gpu_devbio \
    AllowQos=normal,long QOS=normal \
    DefMemPerNode=12000 \
    DefCpuPerGPU=16 \
    MaxCPUsPerNode=16
```

| Parameter | Value | Purpose |
|---|---|---|
| `Nodes` | `compgpu[01,03]` | The two GPU nodes in the cluster |
| `Default` | `NO` | Users must request `-p gpu` explicitly |
| `DefaultTime` | `12:00:00` | 12-hour default wall time |
| `AllowAccounts` | `gpu_rbi,gpu_devbio` | Explicit allow-list — users in any other account are rejected |
| `AllowQos` / `QOS` | `normal,long` / `normal` | `long` is opt-in for extended runs |
| `DefMemPerNode` | `12000` | 12 GB default memory (users should override) |
| `DefCpuPerGPU` | `16` | 1/4 of a node's 64 CPUs per GPU by default |
| `MaxCPUsPerNode` | `16` | Hard cap: one job can't exceed 16 CPUs on any single gpu node |

!!! warning "AllowAccounts is an allow-list"
    Adding a new Slurm account (see [Per-account GPU limits](#per-account-gpu-limits) below) **does not** automatically grant it access to the `gpu` partition. You must also add the account to `AllowAccounts` in `slurm.conf` and run `scontrol reconfigure`.

### Apply and verify

```bash
scontrol reconfigure
scontrol show partition gpu | grep -E "AllowAccounts|DefCpuPerGPU|MaxCPUsPerNode|DefaultTime|DefMemPerNode"
```

### Granting a new group access

Three steps, in order:

1. **Create the Slurm account** (see [Per-account GPU limits](#per-account-gpu-limits)).
2. **Add the account to `AllowAccounts`** in `slurm.conf`, then `scontrol reconfigure`.
3. **Tell users** to submit with `-p gpu -A <account>` and `--gres=gpu:N`.

## Per-account GPU limits

Use a dedicated Slurm account to grant a group of users access to the `gpu` partition with a shared GPU cap. This is cleaner than per-user limits when several users should share a quota, and it keeps the policy in one place.

### Pattern: shared 1-GPU pool for a small group

```bash
# 1. Create the account
sacctmgr add account gpu_devbio \
  Description="GPU access for devbio group" \
  Organization=devbio

# 2. Cap the account at 1 concurrent GPU (applies to all members, shared pool)
sacctmgr modify account gpu_devbio set GrpTRES=gres/gpu=1

# 3. Add a user to the account
sacctmgr add user gibsonty account=gpu_devbio
```

Users submit with the account flag:

```bash
srun -p gpu -A gpu_devbio --gres=gpu:1 --pty bash
sbatch -p gpu -A gpu_devbio --gres=gpu:1 job.sh
```

### Notes

- `GrpTRES` on the account is a **shared pool** across all its users. Use `MaxTRESPerUser=gres/gpu=N` if you also want a per-user ceiling within the pool.
- Set the limit on the **account** association (no `where partition=...` clause). `sacctmgr modify ... where partition=gpu` only matches existing partition-scoped association rows, which don't exist until you create them explicitly — so without that scope the cap lands on the account's root association and is inherited by members everywhere they use GPUs.
- Inherited limits do not re-display on child (user) rows in `sacctmgr show assoc`; they are still enforced at schedule time.
- Default account is unaffected — users keep their existing `DefaultAccount` and must pass `-A gpu_devbio` to hit this quota.

### Verify

```bash
sacctmgr show assoc account=gpu_devbio format=Account,User,Partition,GrpTRES
sacctmgr show user gibsonty withassoc format=User,Account,DefaultAccount,Partition
```
