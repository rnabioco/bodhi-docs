# GPU Jobs

The `gpu` partition provides access to Bodhi's GPU nodes. This page covers the hardware, how to submit jobs, and the per-partition limits you need to work within.

## Hardware

| Node | CPUs | GPUs | GPU model |
|---|---|---|---|
| `compgpu01` | 64 | 4 | NVIDIA A30 |
| `compgpu03` | 64 | 4 | NVIDIA A30 |

Total: **2 nodes, 128 CPUs, 8 A30 GPUs**.

Check the live state anytime:

```bash
sinfo -p gpu -o "%N %c %G %t"
scontrol show node compgpu01 | grep -E "CPUTot|Gres|RealMemory"
```

## Partition settings

| Setting | Value | Notes |
|---|---|---|
| Default runtime | `12:00:00` | If you don't specify `--time`, you get 12 hours |
| Max runtime | Set by QOS | Use `--qos=long` for extended runs |
| Allowed QOS | `normal`, `long` | Default QOS is `normal` |
| Default memory | `12 GB / node` | Override with `--mem` |
| Default CPUs per GPU | `16` | If you don't set `--cpus-per-task`, you get 16 CPUs for each GPU you request |
| Max CPUs per node per job | `16` | A single job cannot exceed 16 CPUs on one gpu node — request additional GPUs (and more nodes) for more CPUs |
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

### Longer jobs (`--qos=long`)

The default QOS (`normal`) imposes a shorter wall-time ceiling. For extended training runs, request the `long` QOS:

```bash
sbatch --qos=long --time=72:00:00 -p gpu -A <your_account> gpu_job.sh
```

### Requesting more than one GPU

Two GPUs on a single node, with CPUs scaled automatically via `DefCpuPerGPU`:

```bash
sbatch -p gpu -A <your_account> --gres=gpu:2 gpu_job.sh
# gets 2 GPUs + 32 CPUs by default
```

You can also pin a specific GPU model (only `a30` today, but syntax for the future):

```bash
sbatch --gres=gpu:a30:1 -p gpu -A <your_account> gpu_job.sh
```

## Limits to keep in mind

- **CPU cap per job per node is `16`.** A multi-GPU job that wants more total CPUs must spread across both gpu nodes (`--nodes=2 --ntasks-per-node=...`) or stay within the 16-CPU-per-node cap.
- **Memory default is low (12 GB).** Always set `--mem` explicitly for real workloads.
- **Per-account GPU caps exist.** Some accounts are limited to a shared pool of GPUs (e.g., 1 concurrent GPU for the whole account). If your job is stuck in `PENDING` with reason `QOSGrpGRES` or `AssocGrpGRES`, another user on your account is already holding the group's GPUs.

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
| `Invalid account or account/partition combination` | Your account is not on `gpu`'s `AllowAccounts` list — ask an admin |
| Job stuck `PENDING`, reason `QOSGrpGRES` | Another job on your account is holding the group's GPU quota |
| Job stuck `PENDING`, reason `Resources` | No GPU currently free — wait or request fewer |
| `Requested node configuration is not available` | You asked for more CPUs than `MaxCPUsPerNode=16` on one node, or an unknown GPU model |
| `nvidia-smi` shows no GPU | You forgot `--gres=gpu:N` — the `gpu` partition does not auto-allocate GPUs |
