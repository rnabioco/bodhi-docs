# GPU Jobs

The `gpu` partition provides access to Bodhi's GPU nodes. This page covers the hardware, how to submit jobs, and the per-partition limits you need to work within.

## Hardware

| Node | CPUs | GPUs | GPU model |
|---|---|---|---|
| `compgpu01` | 64 | 4 | NVIDIA A30 |
| `compgpu02` | 64 | 4 | NVIDIA A30 |
| `compgpu03` | 64 | 4 | NVIDIA A30 |

Total: **3 nodes, 192 CPUs, 12 A30 GPUs**.

!!! note "`compgpu02` is shared with an owner partition"
    `compgpu02` also belongs to `scb_gpu`, which has first claim on it. Your `gpu` job can still land there, but it queues behind `scb_gpu` work. Running jobs are never preempted — they finish normally.

Check the live state anytime:

```bash
sinfo -p gpu -o "%N %c %G %t"
scontrol show node compgpu01 | grep -E "CPUTot|Gres|RealMemory"
```

## Partition settings

| Setting | Value | Notes |
|---|---|---|
| Default runtime | `12:00:00` | If you don't specify `--time`, you get 12 hours |
| Max runtime | **1 day**, or **3 days** with `--qos=gpu_long` | See [Choosing a QOS](#choosing-a-qos) |
| Allowed QOS | `normal`, `high`, `gpu_long` | Default QOS is `normal` |
| Default memory | `12 GB / node` | Override with `--mem` |
| Default CPUs per GPU | `16` | If you don't set `--cpus-per-task`, you get 16 CPUs for each GPU you request |
| Max CPUs per node per job | *(no limit)* | You may request up to all 64 CPUs on a node, but large requests wait longer for a free node |
| Default partition? | No | You must pass `-p gpu` explicitly |

!!! warning "Account required"
    The `gpu` partition is **restricted by account**. You must submit with `-A <account>` and your account must be on the partition's allow-list. Running `-p gpu` without a permitted account will be rejected. See [Requesting access](#requesting-access) below.

## How to submit

### Interactive GPU session (`srun`)

```bash
srun -p gpu -A <your_account> \
     --gres=gpu:1 \
     --cpus-per-task=4 \
     --mem=32G \
     --time=04:00:00 \
     --pty bash
```

Inside the shell, confirm the GPU is visible:

```bash
nvidia-smi
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
```

### Batch job (`sbatch`)

```bash
#!/bin/bash
#SBATCH --job-name=gpu_train
#SBATCH --partition=gpu
#SBATCH --account=<your_account>
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=12:00:00
#SBATCH --output=logs/gpu_train.%j.out
#SBATCH --error=logs/gpu_train.%j.err

module load cuda/12.2
source ~/venvs/torch/bin/activate

nvidia-smi
python train.py --data /data/input --out /data/output
```

Submit:

```bash
mkdir -p logs
sbatch gpu_job.sh
```

## Choosing a QOS

Most jobs need nothing here — the default (`normal`) covers anything up to **1 day**. Reach for `gpu_long` only when a single run genuinely needs more than that.

| QOS | Max walltime | Per-user limits | Fairshare cost | How to request |
|---|---|---|---|---|
| `normal` | 1 day | 8 GPUs, 8 jobs | 1× | *(default — nothing to pass)* |
| `high` | 1 day | 10 jobs | 1× | `--qos=high` (restricted grant) |
| `gpu_long` | **3 days** | **1 job, 1 GPU** | **2×** | `--qos=gpu_long` |

!!! warning "`--qos=long` does not work on the `gpu` partition"
    `long` is not on this partition's allow-list and will be rejected with `Invalid qos specification`. For multi-day GPU runs use `--qos=gpu_long`. (`--qos=long` remains correct on `scb_gpu` for `gpu_scb` owners.)

### Multi-day runs (`--qos=gpu_long`)

For a training run or basecalling job that needs more than 24 hours:

```bash
sbatch --qos=gpu_long --time=3-00:00:00 -p gpu -A <your_account> --gres=gpu:1 gpu_job.sh
```

`gpu_long` is deliberately throttled, because a multi-day job holds a shared GPU for a long time:

- **One at a time.** One running job holding one GPU. A second `gpu_long` submission is rejected while the first runs.
- **Capped fleet-wide.** All `gpu_long` jobs together can hold at most 4 of the 12 GPUs, so long runs can never crowd out short and interactive work.
- **Costs double fairshare.** Usage is charged at 2×, which lowers the priority of *all* your later jobs (CPU and GPU) for roughly a week. Prefer checkpointing and a series of shorter jobs where your software supports it.
- **Lower queue priority** than `normal`, so it yields to normal-length work.

!!! warning "`gpu_long` must be switched on for you by an admin"
    Being on a GPU account is **not** enough — `gpu_long` is granted per user, per account, and is off by default. Until an admin enables it, `--qos=gpu_long` fails immediately with `Invalid qos specification`. Check before you plan a long run, using the steps below.

#### Check whether you have it

List the QoS you hold on each of your accounts:

```bash
sacctmgr show assoc user=$USER format=Account,QOS%45
```

Look at the row for **the account you submit GPU jobs with** (the one you pass to `-A`). `gpu_long` has to appear on *that* row. Grants are per account, so it is entirely possible to hold it on one and not another:

```
   Account                                           QOS
---------- ---------------------------------------------
   gpu_rbi                              high,long,normal     <- no gpu_long: -A gpu_rbi will fail
   gpu_scb           gpu_long,interactive,long,normal        <- has it: -A gpu_scb works
```

Also confirm you're using the right account in the first place — your *default* account is often not your GPU account, so `-A` is usually required. See [Requesting access](#requesting-access).

#### Confirm without burning a submission

`--test-only` validates your request against every limit and prints the verdict **without queueing anything**:

```bash
sbatch --test-only -p gpu -A <your_gpu_account> --qos=gpu_long \
       --gres=gpu:1 --time=3-00:00:00 --wrap='true'
```

| What you see | What it means |
|---|---|
| `sbatch: Job 157037 to start at 2026-07-16T07:32:13 ...` | You have `gpu_long` — a real submission would be accepted |
| `allocation failure: Invalid qos specification` | Either `gpu_long` isn't granted on that account, or you typed `--qos=long` (which never works here) |
| `allocation failure: Invalid account or account/partition combination` | Wrong `-A` — that account has no GPU access at all |
| `sbatch: error: QOSMaxWallDurationPerJobLimit` | The QoS is fine, but your `--time` exceeds what it allows |

#### Getting it enabled

Ask an admin, and include **your username and the GPU account you submit with** — the grant is specific to that pair. Point them at [the admin guide](admin.md#gpu-partition), which has the exact `sacctmgr` command and a note on why an account-level grant alone often misses people.

### Requesting more than one GPU

Two GPUs on a single node, with CPUs scaled automatically via `DefCpuPerGPU`:

```bash
sbatch -p gpu -A <your_account> --gres=gpu:2 gpu_job.sh
# gets 2 GPUs + 32 CPUs by default
```

All GPUs on Bodhi are currently NVIDIA A30s, so `--gres=gpu:N` is sufficient — there is no need to name a specific model.

## Limits to keep in mind

- **You get 16 CPUs per GPU by default**, via `DefCpuPerGPU`. This is a *default*, not a cap — `--cpus-per-task=32` (or more) is accepted. Bear in mind that the more CPUs you ask for, the longer you wait for a node with that many free.
- **Memory default is low (12 GB).** Always set `--mem` explicitly for real workloads.
- **Wall-time is capped at 1 day** unless you opt into [`--qos=gpu_long`](#choosing-a-qos) for up to 3 days.
- **Per-account GPU caps exist.** `gpu_devbio` is limited to **1 concurrent GPU for the whole account**; `gpu_rbi` and `gpu_scb` are uncapped at the account level. If your job is stuck in `PENDING` with reason `QOSGrpGRES` or `AssocGrpGRES`, someone on your account is already holding the group's GPUs.

## Requesting access

GPU access is granted through a Slurm account. If you don't yet have one:

1. Contact an administrator to request access. Provide your username and a short description of the workload.
2. The admin will add you to an existing GPU account (e.g., `gpu_rbi`) or create a new one for your group.
3. Once added, pass `-A <account_name>` on every GPU submission.

You can list the accounts you belong to with:

```bash
sacctmgr show assoc user=$USER format=User,Account,DefaultAccount,Partition
```

Admins: see [GPU partition configuration](admin.md#gpu-partition) for provisioning details.

## Monitoring your GPU jobs

```bash
# Your pending/running jobs
squeue -u $USER

# All jobs currently charging a given account
squeue -A <account_name>

# Historical usage with allocated GPUs
sacct -u $USER -X --format=JobID,JobName,Partition,Account,AllocTRES%40,State,Elapsed

# Live GPU utilization on the node your job landed on
srun --jobid=<jobid> --pty nvidia-smi
```

After a job ends, `seff <jobid>` summarizes CPU and memory efficiency (GPU efficiency is not reported there — use `sacct` with `AllocTRES` and your own training-time metrics).

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Invalid account or account/partition combination` | Your account is not on `gpu`'s `AllowAccounts` list. Note your *default* account may not be your GPU account — pass `-A <your_gpu_account>` explicitly |
| `Invalid qos specification` | Either you used `--qos=long` (not allowed here — use `--qos=gpu_long`), or `gpu_long` is not yet granted to your account association — ask an admin |
| `QOSMaxWallDurationPerJobLimit` | You asked for more than 1 day without `--qos=gpu_long` |
| `QOSMaxJobsPerUserLimit` on a `gpu_long` job | You already have a `gpu_long` job running — only one at a time |
| Job stuck `PENDING`, reason `QOSGrpGRES` | Another job on your account is holding the group's GPU quota, or `gpu_long` is at its 4-GPU fleet-wide cap |
| Job stuck `PENDING`, reason `Resources` | No GPU currently free — wait, or request fewer GPUs/CPUs |
| `nvidia-smi` shows no GPU | You forgot `--gres=gpu:N` — the `gpu` partition does not auto-allocate GPUs |
