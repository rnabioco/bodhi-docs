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
- The reservation also drives the [login-splash maintenance banner](login-splash.md#maintenance-banner): once it's created, the countdown shown to users tracks the reservation's `StartTime`. With no `MAINT` reservation, the banner falls back to the last Thursday of the month, so the two stay in sync automatically.

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

For long-running orchestrators that will blow past the `normal` QoS's 3-day cap, root's `scontrol update TimeLimit=` call alone is enough — the QoS check is only enforced at submit/eval time, not while the job runs. Ideally you'd also switch the job to `QOS=long` for clean reporting, but note:

!!! warning "`QOS=` may be rejected on a running job"
    Combining `QOS=long TimeLimit=…` in one call, or calling `scontrol update QOS=long` against a running job, can fail with `Job is no longer pending execution` depending on SLURM config. In that case, just update `TimeLimit` alone — the job keeps running past the `normal` QoS cap because the update was made by root. Child jobs submitted by the orchestrator continue to default to `QOS=normal`.

If you need to go past the 3-day cap that the `normal` QoS imposes on the CPU partitions, you *do* need a `long`-QoS'd job. In practice that means resubmitting with `--qos=long`, not patching a running job.

!!! danger "`OverPartQOS` does not override a partition's `MaxTime`"
    `OverPartQOS` lets a QoS override the limits of the **partition QoS** (the `QOS=` assigned to a partition) — not the partition's own `MaxTime` field. A partition `MaxTime` is an absolute ceiling that no QoS can exceed, and with `EnforcePartLimits=ALL` it is checked at submit.

    This matters because the CPU partitions set **no** `MaxTime` at all — their 3-day ceiling is purely the `normal` QoS, which is why `long` can lift it to 7 days there. On `gpu`, `MaxTime=3-00:00:00` is set on the partition, so 3 days is a hard ceiling no QoS can beat.

    Note also that `long` is **not** the only QoS with `OverPartQOS` — `high`, `interactive`, and `gpu_long` all carry it too. Verify with `sacctmgr show qos format=Name,Flags`.

### Caveats

| Constraint | What to check |
|---|---|
| Partition max wall time | `sinfo -o "%P %l"` — new limit must be ≤ partition `MaxTime`. No QoS can exceed it, `OverPartQOS` included |
| QoS max wall time | `sacctmgr show qos` — switch QoS (`QOS=long`) rather than relying on root's bypass |
| Active reservations | `scontrol show reservation` — extending past a `MAINT` window will block scheduling |
| Backfill disruption | Raising `TimeLimit` invalidates backfill plans for queued jobs behind this one — expect some queue shuffle |

## Interactive partition

The `interactive` partition provides a dedicated queue for interactive work with shorter time limits and a per-user job cap to prevent monopolization.

### slurm.conf

Add the following line to `/etc/slurm/slurm.conf`:

Live configuration (`scontrol show partition interactive`):

```conf
PartitionName=interactive Nodes=compute[04,06-07] Default=NO MaxTime=2-00:00:00 DefaultTime=08:00:00 State=UP AllowQos=ALL
```

| Parameter | Value | Purpose |
|---|---|---|
| `Nodes` | `compute[04,06-07]` | Shared with `normal` partition |
| `Default` | `NO` | Users must request this partition explicitly |
| `MaxTime` | `2-00:00:00` | 2-day maximum wall time |
| `DefaultTime` | `08:00:00` | 8-hour default |
| `AllowQos` | `ALL` | Any QoS may submit here |
| `QOS` | *(none)* | No partition QoS is assigned |

!!! warning "This partition does not force the `interactive` QoS"
    Despite the name, `interactive` has **no** partition QoS and `AllowQos=ALL`, so jobs land on the default `normal` QoS (3-day `MaxWall`) unless the user passes `--qos=interactive`. The partition's own `MaxTime=2-00:00:00` is what actually bounds sessions here, and the `interactive` QoS's 12-hour `MaxWall` and 16-CPU/8 GB caps apply only when explicitly requested.

    This is why `sinteractive`'s 1-day default works even though the `interactive` QoS caps at 12 hours. If you want those caps enforced for everyone, set `QOS=interactive` on the partition and restrict `AllowQos` — but check first that it won't break `sinteractive`'s defaults.

### Per-user job limit (QOS)

`MaxJobsPerUser` is not a valid `slurm.conf` partition parameter — enforce it via a QOS instead:

```bash
# Create the QOS with a per-user job limit
sacctmgr add qos interactive set MaxJobsPerUser=3

# Allow all accounts to use it
sacctmgr modify account where account=root withsubaccounts set qos+=interactive
```

The live `interactive` QoS now has `MaxJobsPerUser=4` but `MaxSubmitJobsPerUser=3`. Since the submit limit counts pending *and* running jobs, 3 is the effective ceiling and the 4 is unreachable — worth reconciling.

### Apply and verify

```bash
scontrol reconfigure
scontrol show partition interactive
sacctmgr show qos interactive format=Name,MaxJobsPerUser
```

## GPU partition

The `gpu` partition fronts Bodhi's GPU nodes (`compgpu01`–`compgpu03` — 64 CPUs + 4 × NVIDIA A30 each). User-facing documentation lives at [GPU Jobs](gpu.md); this section covers the admin-side configuration.

### slurm.conf

Live definition (`slurm.conf` line ~190):

```conf
PartitionName=gpu Nodes=compgpu01,compgpu02,compgpu03 Default=NO State=UP \
    DefaultTime=12:00:00 MaxTime=3-00:00:00 \
    AllowAccounts=gpu_rbi,gpu_devbio,gpu_scb \
    AllowQOS=normal,high,gpu_long QOS=gpu_shared \
    DefMemPerNode=12000 \
    DefCpuPerGPU=16 \
    GraceTime=120 PriorityTier=1 DisableRootJobs=YES
```

| Parameter | Value | Purpose |
|---|---|---|
| `Nodes` | `compgpu[01-03]` | All three GPU nodes (12 A30s total) |
| `Default` | `NO` | Users must request `-p gpu` explicitly |
| `DefaultTime` | `12:00:00` | 12-hour default wall time |
| `MaxTime` | `3-00:00:00` | Absolute ceiling — no QoS can exceed it |
| `AllowAccounts` | `gpu_rbi,gpu_devbio,gpu_scb` | Explicit allow-list — users in any other account are rejected |
| `AllowQOS` | `normal,high,gpu_long` | `gpu_long` is the opt-in path to 3 days |
| `QOS` | `gpu_shared` | Partition QoS — imposes the 1-day default cap |
| `DefMemPerNode` | `12000` | 12 GB default memory (users should override) |
| `DefCpuPerGPU` | `16` | 1/4 of a node's 64 CPUs per GPU by default — a *default*, not a cap |

!!! note "Why the wall-time limit is split across two settings"
    Allowing 3-day runs required raising the partition `MaxTime` to 3 days, since `MaxTime` is a hard ceiling. That alone would have given *everyone* 3 days, so the `gpu_shared` partition QoS (`MaxWall=1-00:00:00`) re-imposes the 1-day default, and `gpu_long` (`MaxWall=3d` + `OverPartQOS`) punches through it.

    `gpu_shared` is a dedicated partition QoS rather than a change to the shared `gpu` QoS specifically so `scb_gpu` — which still uses `QOS=gpu` — keeps its 3-day owner jobs.

    `compgpu02` is shared with the `scb_gpu` owner partition (`PriorityTier=100`), which gets first claim on it. Preemption is off cluster-wide, so opportunistic jobs there always finish.

### GPU QoS reference

| QoS | Priority | MaxWall | MaxJobsPU | MaxTRESPU | GrpTRES | UsageFactor | Where |
|---|---|---|---|---|---|---|---|
| `gpu_shared` | 25 | 1 day | 8 | `gres/gpu=8` | — | 1.0 | Partition QoS on `gpu` |
| `gpu_long` | 10 | 3 days | 1 | `gres/gpu=1` | `gres/gpu=4` | **2.0** | Opt-in via `--qos=gpu_long` |
| `gpu` | 25 | — | 8 | `gres/gpu=8` | — | 1.0 | Partition QoS on `scb_gpu` |

!!! warning "Granting `gpu_long` — account-level is not enough"
    `sacctmgr modify account <acct> set qos+=gpu_long` only reaches user associations that **inherit** the account's QoS list. Users whose association carries an explicit QoS list override the parent and are silently skipped, then hit `Invalid qos specification`. Grant those explicitly:

    ```bash
    sacctmgr -i modify user where account=gpu_rbi user=<user1>,<user2> set qos+=gpu_long
    ```

    Beware that `sacctmgr show assoc` displays the *inherited* list for users with no explicit list, so a user appearing to have `gpu_long` may just be inheriting it. Compare each user's list against the account's: if the strings are identical, they're inheriting.

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
