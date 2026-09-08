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

### Restrict SSH during the window

A `MAINT` reservation stops **jobs**. It does nothing about **logins**. Users can still SSH to `amc-bodhi` during the window and — because `pam_slurm_adopt` is not configured in `/etc/pam.d/sshd` — straight to any compute node as well, whether or not they have a job on it. Apply the lockout fleet-wide, not just on the head node.

The mechanism is a single drop-in file that allows only a named group. Rocky 9's `/etc/ssh/sshd_config` already has `Include /etc/ssh/sshd_config.d/*.conf` at the top, so a drop-in wins over the base config and the whole lockout is one file to add and remove.

#### One-time setup

Create the allow-list group and add the admins. Group lookups resolve through NIS first (`group: nis files ...` in `/etc/nsswitch.conf`), so a NIS group works fleet-wide; a local group has to exist on every node:

```bash
getent group sshmaint          # currently returns nothing — it does not exist yet

# node-local fallback if the group is not in NIS
pdsh -w $NODES 'groupadd -r sshmaint'
pdsh -w $NODES 'usermod -aG sshmaint <admin-user>'
pdsh -w $NODES 'getent group sshmaint' | sort    # confirm identical membership everywhere
```

Check for allow/deny rules that are already in play, so the drop-in doesn't interact with something unexpected:

```bash
grep -riE 'allow(users|groups)|deny(users|groups)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/
```

#### Enable the lockout

Build the file once locally, push it with `pdcp`, then validate and reload as a separate step. Writing the config and testing it in one nested-quoting `pdsh` one-liner is how you end up with a typo'd `AllowGroups` on 25 nodes:

```bash
printf '%s\n' \
  '# Maintenance lockout — remove this file and reload sshd to restore access.' \
  'AllowGroups sshmaint root' > /tmp/99-maintenance.conf

pdcp -w $NODES /tmp/99-maintenance.conf /etc/ssh/sshd_config.d/
```

Now validate and reload, reverting automatically on any node where the config doesn't parse:

```bash
pdsh -w $NODES 'sshd -t && systemctl reload sshd \
  || { rm -f /etc/ssh/sshd_config.d/99-maintenance.conf; echo "REVERTED"; }'
```

The self-revert matters: `sshd -t` alone would leave a bad drop-in sitting on disk for the next reboot to pick up — during a window where you are rebooting anyway.

!!! warning "Keep a session open"
    Always keep your current SSH session open and test the lockout from a *second* terminal before logging out. A mistake in `AllowGroups` locks everyone out, including you, and recovery then needs console access (`minicom -D /dev/ttyUSB0`).

Verify the effective config rather than the file — `sshd -T` shows what sshd actually resolved:

```bash
pdsh -w $NODES 'sshd -T | grep -i "^allowgroups"' | sort
```

Then confirm from a third terminal that a non-whitelisted account is refused and an `sshmaint` member still gets in.

#### Evicting sessions already open

The lockout only blocks *new* logins. Anyone already connected stays connected:

```bash
who                            # or: loginctl list-sessions
loginctl kill-user <username>  # ends all of that user's sessions on this node
```

This also kills any multiplexer the user has parked — `tmux`, `screen`, and the `zellij` server behind an `sinteractive` session — so give warning through the [login splash](login-splash.md#maintenance-banner) rather than making this the first thing users notice.

#### Failsafe: schedule the unlock

A lockout that someone forgets to remove strands the whole user base, so schedule the removal at the same time you create it. The drop-in is on every node, so the unlock has to be queued on every node too:

```bash
pdsh -w $NODES 'systemctl enable --now atd'
pdsh -w $NODES "echo 'rm -f /etc/ssh/sshd_config.d/99-maintenance.conf \
  && systemctl reload sshd' | at 06:00 tomorrow"
pdsh -w $NODES 'atq' | sort    # confirm one job queued per node
```

Use `at`, not `systemd-run --on-active`: transient systemd timers do not survive a reboot, and maintenance windows involve reboots. `at` jobs are re-read from the spool by `atd` after a restart.

#### Lift the lockout

```bash
pdsh -w $NODES 'rm -f /etc/ssh/sshd_config.d/99-maintenance.conf && sshd -t && systemctl reload sshd'
pdsh -w $NODES 'sshd -T | grep -ci "^allowgroups"' | sort   # expect 0 everywhere
```

If you lift it early, drop the queued failsafe too, or it fires later and triggers a pointless `sshd` reload on every node:

```bash
pdsh -w $NODES 'atq' | sort                 # note the job IDs
pdsh -w $NODES 'atrm $(atq | cut -f1)'
```

#### Why not `/etc/nologin`

`pam_nologin.so` is already active in `/etc/pam.d/sshd`, and dropping a message into `/etc/nologin` is the traditional way to do this. It is the wrong tool here for two reasons:

- **No allow-list.** `pam_nologin` permits `root` and blocks *everyone* else. Admins who log in as themselves and then `sudo` are locked out along with the users.
- **Reboot behaviour is not what people assume.** `pam_nologin` honours both `/run/nologin` and `/etc/nologin`, and `systemd-user-sessions.service` manages `/run/nologin` across boot and shutdown. Don't rely on a `nologin` file surviving the reboots in a maintenance window without testing it on this build first.

Don't combine the two either — `/etc/nologin` would block the `sshmaint` admins the drop-in is meant to let through, unless every admin logs in as `root`.

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
| `MaxTime` | `5-00:00:00` | 5-day maximum wall time |
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

---

## Storage quotas

Usage lives on the nine storage servers behind `/beevol` (`172.20.8.110`–`118`), each running a quota daemon that answers `QUOTA <uid>` on TCP 9878 with that server's share in kilobytes. The **limits** are separate: they come from `/etc/quota_current.txt`, which is regenerated on the head node.

[`quota_check`](https://github.com/rnabioco/bodhi-docs/blob/main/scripts/quota_check) queries all nine in parallel and adds them up. It is a shell script with no dependencies beyond bash and coreutils, so it installs and runs on compute nodes as well as the head node.

### Quota file format

One user per line, pipe-delimited, with the notification address optional. Whitespace around fields is padding, not data:

```text
jdoe|   21.48TiB|   jdoe@example.com
```

Blank lines, `#` comments, and lines without at least a username and a size are ignored. Sizes accept the `xfs_quota` suffixes (`K`/`M`/`G`/`T`/`P`) and their IEC spellings (`KiB`…`PiB`), in either case.

### Installing on the compute nodes

`/usr/local` is node-local, so the script has to be placed on each node:

```bash
sudo make quota-nodes        # fan out to every node sinfo knows about
make quota-nodes-check       # report what each node actually has
```

`quota-nodes-check` is read-only and unprivileged — run it any time. A fan-out that failed halfway is otherwise invisible.

### Publishing the quota file

A compute node can reach the daemons but not `/etc/quota_current.txt`, so `Hard Quota` and `% Used` read `-` there. Publishing the file to `/cluster/share` — an NFS mount every node has, and the second location `quota_check` searches — closes the gap:

```bash
sudo make publish-quota-file
```

!!! warning "Publish from the job that regenerates the file"
    The copy is a snapshot. If `/etc/quota_current.txt` is regenerated without republishing, compute nodes keep reporting against the stale limits — and nothing in the output says so. Add `make publish-quota-file` to the same cron job.

### Over-quota notifications

```bash
quota_check --all --email --dry-run   # who would be mailed
quota_check --all --email             # send
```

`--email` requires `--all`, mails everyone over 100% using the address in the third field of the quota file, and copies the storage administrator (`--no-smtp-cc` suppresses that). Users over quota with no address are reported on stderr and skipped.

Mail is spoken directly to the smarthost over TCP rather than handed to `sendmail`, because compute nodes have no MTA. Override the relay with `--smtp-server HOST[:PORT]` or `QUOTA_CHECK_SMTP_SERVER`.

**Always run `--dry-run` first.** It exercises the full selection path — query, quota lookup, threshold — and prints the recipient list without opening a connection to the mail server.

### Checking one user

```bash
quota_check -u jdoe --full     # per-server breakdown
quota_check -u jdoe --json     # for scripts
```

See `man quota_check` for the rest.
