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
    On every batch partition you get **12 GB per node**, regardless of how many CPUs you ask for. Each partition sets `DefMemPerNode=12000`, and that takes precedence over the cluster-wide `DefMemPerCPU=4000`.

    The 4 GB-per-CPU rule applies only on `interactive` and `positron`, which set no per-node default — there, `--cpus-per-task=4` with no `--mem` does get 16 GB.

    Either way the default is low. Set `--mem` explicitly for real workloads.

!!! note "Don't just request the maximum"
    Requesting far more memory than you need reduces scheduling priority and wastes cluster resources. Right-size your requests based on actual usage from `seff`.

---

## Tasks vs CPUs: `--ntasks` vs `--cpus-per-task`

LSF's `-n N` meant one thing: "give me N cores." SLURM splits that same idea into two separate flags, and picking the wrong one is one of the most common migration mistakes on Bodhi.

### The framing difference

SLURM distinguishes between *processes* and *threads within a process*:

- **`--ntasks=N`** — how many independent processes your job will launch (think MPI ranks, or N separate commands)
- **`--cpus-per-task=N`** — how many threads/cores each of those processes will use

The total cores allocated to your job is `ntasks × cpus-per-task`. Both flags default to `1`, so a bare `sbatch` with no CPU flags gets you exactly one core.

!!! warning "This is different from LSF"
    LSF `-n 8` almost always maps to `--cpus-per-task=8`, **not** `--ntasks=8`. Almost all bioinformatics tools (`samtools`, `bwa`, `STAR`, `R` `mclapply`, anything using OpenMP) are *threaded*, not MPI. If you set `--ntasks=8` for a threaded tool, SLURM reserves 8 slots but your tool only uses one of them — you get slower scheduling *and* worse performance.

### Which flag do I use?

| Your job | Use | Example |
|---|---|---|
| Single-threaded serial | neither (defaults) | `python script.py` |
| Multi-threaded (`-@`, `-t`, `--threads`, OpenMP) | `--cpus-per-task=N` | `samtools sort -@ 8` |
| MPI (`mpirun`, `mpiexec`) | `--ntasks=N` | `mpirun ./mpi_app` |
| Embarrassingly parallel via `srun` or GNU parallel | `--ntasks=N` | N independent shell commands |
| Hybrid MPI + threads | both | `--ntasks=4 --cpus-per-task=8` |

### Behavioral consequences

**What `srun` does with each flag.** `srun cmd` with `--ntasks=N` launches N copies of `cmd` in parallel. `srun cmd` with `--cpus-per-task=N --ntasks=1` launches one copy of `cmd` and hands it N cores — `cmd` itself is responsible for spawning threads to use them.

**What environment variable your tool sees.** SLURM exports `$SLURM_NTASKS` and `$SLURM_CPUS_PER_TASK`. A common idiom for threaded tools:

```bash
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
samtools sort -@ $SLURM_CPUS_PER_TASK input.bam -o sorted.bam
```

**Node placement.** `--ntasks` tasks may be spread across multiple nodes unless you also set `--nodes=1`. `--cpus-per-task` cores are always on the same node — a single process can't span nodes.

### Memory interaction

`--mem` is per-job (total). `--mem-per-cpu` multiplies by the *total* cores (`ntasks × cpus-per-task`):

```bash
#SBATCH --ntasks=4
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=2G    # 4 × 8 × 2G = 64 GB total
```

!!! tip "Quick self-check"
    - If your tool has a `--threads`, `-t`, `-@`, or `-p` flag, you want `--cpus-per-task=N`.
    - If you're launching `mpirun` or `mpiexec`, you want `--ntasks=N`.
    - If in doubt, `--cpus-per-task` is the right default for typical bioinformatics work on Bodhi.

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

The "max wall time" below is what you can actually request. On the CPU partitions it comes from the `normal` QoS, not the partition — see [QoS tiers](#qos-tiers) for how the two interact.

| Partition | Max wall time | Default wall time | Nodes | Access | Notes |
|---|---|---|---|---|---|
| `normal` | 3 days (7 with `--qos=long`) | **4 hours** | compute01–04, 06–07, 14 | All accounts | Default partition |
| `interactive` | 2 days | 8 hours | compute04, 06–07 | All accounts | Effectively 3 jobs/user |
| `rna` | 3 days (7 with `--qos=long`) | **4 hours** | compute07–09, 13–21 | `rbi` | Falls back to `normal` |
| `jones` | 3 days (7 with `--qos=long`) | **4 hours** | compute04–05, 10–12 | `jones` | Also allows `high` |
| `genome` | 3 days (7 with `--qos=long`) | **4 hours** | compute06–09 | `genome` | Falls back to `normal` |
| `gpu` | **1 day** (3 with `--qos=gpu_long`) | **12 hours** | compgpu01–03 | `gpu_rbi`, `gpu_devbio`, `gpu_scb` | 12× NVIDIA A30. See [GPU Jobs](gpu.md) |
| `scb_gpu` | 3 days | **12 hours** | compgpu02 | `gpu_scb` | 4× NVIDIA A30; owner priority |
| `scb` | 3 days (7 with `--qos=long`) | **4 hours** | compute13 | `scb` | |
| `cranio` | 3 days (7 with `--qos=long`) | **4 hours** | compute21 | `scb` | Falls back to `normal` |
| `bigmem` | 3 days (7 with `--qos=long`) | **4 hours** | compute14 | `bigmem` | ~1.5 TB RAM |
| `rstudio` | 3 days (7 with `--qos=long`) | **8 hours** | compute00 | `bigmem` | Interactive RStudio |
| `voila` | 3 days (7 with `--qos=long`) | **4 hours** | compute00 | `bigmem` | Voilà notebooks |
| `positron` | 1 day | **8 hours** | compute04, 06–07, 14 | All accounts | Positron Remote SSH; 1 job/user |

!!! warning "The `gpu` partition is the exception"
    `gpu` is the only partition whose wall-time ceiling is enforced by the partition itself (`MaxTime=3 days`) rather than by a QoS. Its everyday 1-day cap comes from the `gpu_shared` partition QoS, and `--qos=long` does **not** work there. Use `--qos=gpu_long` for up to 3 days — see [GPU Jobs](gpu.md#choosing-a-qos).

!!! warning "Default wall time changed — jobs may time out"
    If you omit `--time`, your job now gets **4 hours** (general partitions) or **12 hours** (GPU partitions). Previously, jobs without `--time` silently inherited the 3-day maximum.

    **If your jobs are timing out**, add `--time` with a realistic estimate:

    ```bash
    #SBATCH --time=8:00:00       # 8 hours
    #SBATCH --time=1-00:00:00    # 1 day
    ```

    For jobs that need more than 3 days, use the `long` QoS (up to 7 days):

    ```bash
    #SBATCH --qos=long
    #SBATCH --time=5-00:00:00    # 5 days
    ```

    **Why the change?** Shorter default times dramatically improve scheduling. SLURM's backfill scheduler can only fit jobs into gaps if it knows when running jobs will end. A job with no `--time` previously looked like a 3-day job to the scheduler — even if it finished in 20 minutes — blocking other jobs from backfilling into the gap.

!!! tip "Right-size your `--time` requests"
    Request about 20–30% more than your expected runtime. Use `seff <jobid>` to check how long past jobs actually took. Shorter time requests schedule faster via backfill.

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

---

## QoS tiers

SLURM Quality of Service (QoS) tiers control job priority, time limits, and resource caps. Every job runs under a QoS — if you don't specify one, you get `normal`.

### Available QoS tiers

These are the QoS you can request:

| QoS | Priority | Max wall time | Max running jobs | Max queued jobs | Resource caps | Use case |
|---|---|---|---|---|---|---|
| `high` | 100 | partition limit | 10 | 20 | — | Urgent jobs — requires admin approval |
| `long` | 50 | 7 days | 12 | 50 | 128 CPUs/user, 156 total | Extended runs that need >3 days |
| `interactive` | 50 | 12 hours | 4 | 3 | 16 CPUs, 8 GB | Terminal sessions via `sinteractive` |
| `normal` | 25 | **3 days** | 500 | 2000 | — | Default for most jobs |
| `low` | 10 | 7 days | 50 | 200 | — | Background, non-urgent work |
| `gpu_long` | 10 | 3 days | **1** | — | 1 GPU/user, 4 total; **2× fairshare** | Multi-day GPU runs — see [GPU Jobs](gpu.md#choosing-a-qos) |

Slurm also applies a QoS to your job automatically based on the partition, which you never request yourself: `normal` on the CPU partitions, `gpu_shared` on `gpu` (this is what imposes its 1-day default), `gpu` on `scb_gpu`, and `positron` on `positron`. The `interactive` partition has no automatic QoS.

!!! info "How priority works"
    Higher priority QoS tiers are scheduled first — QoS is the single largest priority factor on Bodhi (`PriorityWeightQOS=10000`, versus 5000 for fairshare and 1000 for age).

    **Nothing preempts anything.** Preemption is disabled cluster-wide (`PreemptType=(null)`, `PreemptMode=OFF`). A higher-priority job jumps ahead in the *queue*, but running jobs are never killed or requeued to make room — they always finish naturally.

### Using a QoS

```bash
#SBATCH --qos=long
#SBATCH --time=3-00:00:00
```

Or on the command line:

```bash
sbatch --qos=long myjob.sh
```

### When to use `long`

The default `normal` QoS caps you at **3 days**. If a job needs more than that, use `long`:

```bash
#SBATCH --qos=long
#SBATCH --time=5-00:00:00    # up to 7 days
```

The tradeoff: under `long` you're limited to 12 running jobs, 128 CPUs for yourself, and 156 CPUs across everyone using it at once.

!!! warning "`long` does not work on the `gpu` partition"
    `long` is not on `gpu`'s allow-list and is rejected there with `Invalid qos specification`. For multi-day GPU work use [`--qos=gpu_long`](gpu.md#choosing-a-qos) instead. (`long` is still correct on `scb_gpu` for `gpu_scb` owners.)

!!! info "Why `long` can exceed the 3-day cap"
    The CPU partitions set no wall-time limit of their own — their 3-day ceiling comes from the `normal` QoS that Slurm applies automatically. `long` carries the `OverPartQOS` flag, which lets its own 7-day `MaxWall` take precedence over that automatic QoS.

    This only works because those partitions have no `MaxTime`. A partition's own `MaxTime` is an absolute ceiling that **no** QoS can exceed, `OverPartQOS` included — which is exactly why `long` cannot buy you extra time on `gpu`, where `MaxTime=3 days` is set on the partition.

### When to use `low`

For jobs that can wait — overnight runs, large batch submissions where turnaround isn't critical:

```bash
#SBATCH --qos=low
#SBATCH --time=3-00:00:00
```

`low` allows up to 7 days and 50 concurrent jobs, but at reduced priority.

### DenyOnLimit

Most QoS tiers enforce `DenyOnLimit` — if your job exceeds the QoS limits (too many running jobs, too many CPUs, etc.), it is **rejected at submit time** rather than sitting in the queue forever. You'll see an immediate error telling you what limit was hit.

`long` is the exception: it does *not* set `DenyOnLimit`, so a `long` job that trips a limit sits `PENDING` with a reason like `QOSMaxCpuPerUserLimit` instead of being rejected. If a `long` submission seems to vanish into the queue, check `squeue -u $USER -o "%i %T %r"` for the reason.

!!! tip "Check your QoS"
    ```bash
    # See which QoS tiers you can use
    sacctmgr show associations user=$USER format=Account,QOS

    # See all QoS definitions
    sacctmgr show qos format=Name,Priority,MaxWall,MaxJobsPU,MaxSubmitPU,MaxTRESPU,Flags
    ```
