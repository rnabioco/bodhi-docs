# Common Pain Points

This page covers recurring issues that Bodhi users encounter when migrating from LSF to SLURM. These aren't simple directive swaps — they're behavioral differences that catch people off guard.

---

## Debugging OOM (Out-of-Memory) errors

### How OOM kills look in SLURM

When a job exceeds its memory allocation, SLURM kills it immediately. The job state is set to `OUT_OF_MEMORY`:

```bash
$ sacct -j 12345 --format=JobID,JobName,State,ExitCode,MaxRSS
JobID           JobName      State ExitCode     MaxRSS
------------ ---------- ---------- -------- ----------
12345          analysis OUT_OF_ME+      0:125
12345.batch       batch OUT_OF_ME+      0:125    15.8G
```

You can also see this with `seff`:

```bash
$ seff 12345
Job ID: 12345
State: OUT_OF_MEMORY (exit code 0)
Memory Utilized: 15.80 GB
Memory Efficiency: 98.75% of 16.00 GB
```

!!! warning "This is different from LSF"
    On Bodhi's LSF, memory limits were often **soft limits** — jobs could exceed their requested memory without being killed (as long as the node had memory available). In SLURM, `--mem` is a **hard limit** enforced by cgroups. If your job exceeds it, even briefly, it will be killed.

### Diagnosing memory usage

**For completed jobs**, use `sacct`:

```bash
# Check peak memory usage
sacct -j <jobid> --format=JobID,JobName,MaxRSS,MaxVMSize,State

# For array jobs, check all tasks
sacct -j <jobid> --format=JobID%20,JobName,MaxRSS,State
```

**For running jobs**, use `sstat`:

```bash
# Monitor memory of a running job
sstat -j <jobid> --format=JobID,MaxRSS,MaxVMSize
```

!!! tip "Use `seff` for quick checks"
    `seff <jobid>` gives a one-line summary of memory efficiency for completed jobs. It's the fastest way to check if your job was close to its memory limit.

### Fixing OOM errors

1. **Check what your job actually used** — run `seff <jobid>` on a similar completed job to see actual peak memory.

2. **Request more memory with headroom** — add 20–30% buffer above the observed peak:

    ```bash
    #SBATCH --mem=20G   # if your job peaked at ~15 GB
    ```

3. **Use `--mem-per-cpu` for multi-threaded jobs** — if your job scales memory with cores:

    ```bash
    #SBATCH --cpus-per-task=8
    #SBATCH --mem-per-cpu=4G   # 32 GB total
    ```

!!! info "Default memory when `--mem` is not specified"
    Bodhi's default is `DefMemPerCPU=4000` (4 GB per CPU). So a job requesting `--cpus-per-task=4` with no `--mem` gets 16 GB total. A single-CPU job gets 4 GB.

!!! note "Don't just request the maximum"
    Requesting far more memory than you need reduces scheduling priority and wastes cluster resources. Right-size your requests based on actual usage from `seff`.

---

## Understanding SLURM accounts

### What is `--account`?

In SLURM, the `--account` flag associates your job with a resource allocation account. This is used for:

- **Fair-share scheduling** — accounts that have used fewer resources recently get higher priority
- **Resource tracking** — PIs and admins can see how allocations are consumed
- **Access control** — some partitions may be restricted to certain accounts

!!! warning "Why this matters on Bodhi"
    On LSF, the `-P` project flag was often optional or had a simple default. On SLURM, submitting with the wrong account (or no account) can result in job rejection or lower scheduling priority.

### Finding your account(s)

```bash
# List your SLURM associations (accounts and partitions you can use)
sacctmgr show associations user=$USER format=Account,Partition,QOS

# Shorter version — just account names
sacctmgr show associations user=$USER format=Account --noheader | sort -u
```

Bodhi accounts are **lab/group-based**. Each account corresponds to a research group or resource class:

| Account | Description |
|---|---|
| `bmg` | Biochemistry and Molecular Genetics |
| `rbi` | RNA Bioscience Initiative |
| `jones` | Jones lab (Pediatrics) |
| `genome` | Genome group |
| `scb` | SCB group (SOM Hematology) |
| `gpu_rbi` | GPU access for RBI |
| `gpu_scb` | GPU access for SCB |
| `bigmem` | Large-memory node access |
| `cranio` | Craniofacial group |
| `normal` | General/shared access |
| `peds_devbio` | Pediatrics Developmental Biology |
| `peds_hematology` | Pediatrics Hematology |
| `som_hematology` | SOM Hematology |
| `som_dermatology` | SOM Dermatology |
| `medical_oncology` | Medical Oncology |
| `gastroenterology` | Gastroenterology |

Most users are associated with their PI's lab account. You may belong to multiple accounts (e.g., `rbi` for CPU jobs and `gpu_rbi` for GPU jobs).

### Setting a default account

Rather than adding `--account` to every script, set a default:

```bash
# Set your default account (persists across sessions)
sacctmgr modify user $USER set DefaultAccount=<your_account>
```

You can also add it to your `~/.bashrc` or a SLURM defaults file:

```bash
# In ~/.bashrc
export SBATCH_ACCOUNT=<your_account>
export SRUN_ACCOUNT=<your_account>
```

!!! tip "Check your default"
    ```bash
    sacctmgr show user $USER format=DefaultAccount
    ```

### In your job scripts

```bash
#SBATCH --account=<your_account>
```

!!! warning "`--account` is effectively required on Bodhi"
    Bodhi enforces `AccountingStorageEnforce=associations,limits,qos`, which means jobs are **rejected** if your user lacks a valid account association for the target partition and QoS. If you have only one account, Slurm uses it automatically. If you have multiple accounts, set a default (see above) to avoid specifying `--account` on every submission.

---

## Paying attention to wall time

### SLURM enforces `--time` strictly

In SLURM, the `--time` (wall time) limit is a **hard cutoff**. When your job hits the limit:

1. SLURM sends `SIGTERM` to your job (giving it a chance to clean up)
2. After a 30-second grace period (`KillWait=30`), SLURM sends `SIGKILL`
3. The job state is set to `TIMEOUT`

```bash
$ sacct -j 12345 --format=JobID,JobName,Elapsed,Timelimit,State
JobID           JobName    Elapsed  Timelimit      State
------------ ---------- ---------- ---------- ----------
12345          longrun   02:00:00   02:00:00    TIMEOUT
```

!!! warning "This is different from LSF"
    On Bodhi's LSF, wall-time limits were often loosely enforced — jobs could sometimes run past their `-W` limit. In SLURM, when your time is up, your job is killed. Period.

### Checking remaining time

**From outside the job:**

```bash
# See time limit and elapsed time
squeue -u $USER -o "%.10i %.20j %.10M %.10l %.6D %R"
#                              Elapsed ^  ^ Limit

# Detailed view
scontrol show job <jobid> | grep -E "RunTime|TimeLimit"
```

**From inside the job** (in your script):

```bash
# Remaining time in seconds — useful for checkpointing
squeue -j $SLURM_JOB_ID -h -o "%L"
```

### Consequences of TIMEOUT

- Your job output may be incomplete or corrupted
- Any files being written at kill time may be truncated
- Temporary files won't be cleaned up

!!! tip "Add cleanup traps"
    If your job writes large intermediate files, add a trap to handle `SIGTERM`:

    ```bash
    cleanup() {
        echo "Job hit time limit — cleaning up"
        # save checkpoint, remove temp files, etc.
    }
    trap cleanup SIGTERM
    ```

### Bodhi partition time limits

| Partition | Max wall time | Default wall time | Nodes | Access | Notes |
|---|---|---|---|---|---|
| `normal` | 3 days | not set | compute01–04, 06–07, 14 | All accounts | Default partition |
| `interactive` | 1 day | 8 hours | compute03–04, 06–07 | All accounts | Max 3 jobs/user |
| `rna` | 3 days | not set | compute07–09, 15–20 | `rbi` | Falls back to `normal` |
| `jones` | 3 days | not set | compute04–05, 10–12 | `jones` | |
| `genome` | 3 days | not set | compute06–09 | `genome` | Falls back to `normal` |
| `gpu` | 3 days | not set | compgpu01, 03 | `gpu_rbi` | 8× NVIDIA A30 |
| `scb_gpu` | 3 days | not set | compgpu02 | `gpu_scb` | 4× NVIDIA A30 |
| `scb` | 3 days | not set | compute13 | `scb` | |
| `cranio` | 3 days | not set | compute21 | `scb` | Falls back to `normal` |
| `bigmem` | 3 days | not set | compute14 | `bigmem` | ~1.5 TB RAM |
| `rstudio` | 3 days | not set | compute00 | `bigmem` | Interactive RStudio |
| `voila` | 3 days | not set | compute00 | `bigmem` | Voilà notebooks |

!!! warning "No default wall time is set"
    If you omit `--time`, your job inherits the partition's `MaxTime` (3 days). **Always specify `--time`** — shorter jobs schedule faster via backfill, and you avoid tying up resources longer than needed.

!!! note "Check current limits"
    Partition limits can change. Verify the current limits with:

    ```bash
    sinfo -o "%12P %10l %10L %6D %8c %10m"
    #            Name  TimeLimit  DefTime  Nodes  CPUs  Memory
    ```

### Tips for setting wall time

1. **Start with a generous estimate**, then refine based on actual runtimes using `seff` or `sacct`.

2. **Shorter jobs schedule faster** — SLURM's backfill scheduler can fit shorter jobs into gaps. Requesting 2 hours instead of 7 days can dramatically reduce queue wait time.

3. **Use `sacct` to check past runtimes:**

    ```bash
    sacct -u $USER --format=JobID,JobName,Elapsed,State -S 2024-01-01 | grep COMPLETED
    ```

4. **SLURM format for `--time`:**

    | Format | Meaning |
    |---|---|
    | `MM` | Minutes |
    | `HH:MM:SS` | Hours, minutes, seconds |
    | `D-HH:MM:SS` | Days, hours, minutes, seconds |
    | `D-HH` | Days and hours |

    ```bash
    #SBATCH --time=04:00:00      # 4 hours
    #SBATCH --time=1-00:00:00    # 1 day
    #SBATCH --time=7-00:00:00    # 7 days
    ```
