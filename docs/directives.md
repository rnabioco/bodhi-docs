# Directives: `#BSUB` → `#SBATCH`

Every `#BSUB` directive in your LSF scripts has a SLURM equivalent using `#SBATCH`. The table below covers the most common mappings.

## Directive mapping table

| Purpose | LSF (`#BSUB`) | SLURM (`#SBATCH`) | Notes |
|---|---|---|---|
| Job name | `-J myJob` | `--job-name=myJob` | |
| Queue / Partition | `-q normal` | `--partition=normal` | LSF "queues" are SLURM "partitions" |
| Wall-clock time limit | `-W 60` or `-W 1:00` | `--time=01:00:00` | SLURM uses `HH:MM:SS` or `D-HH:MM:SS` |
| Stdout file | `-o output.%J` | `--output=output.%j` | See filename patterns below |
| Stderr file | `-e error.%J` | `--error=error.%j` | |
| Combine stdout/stderr | `-o output.%J` (default) | `--output=output.%j` | SLURM merges by default when `--error` is omitted |
| Memory per job | `-M 4000` | `--mem=4G` | LSF uses KB by default; SLURM uses MB (suffix `G` for GB) |
| Memory per core | `-R "rusage[mem=4000]"` | `--mem-per-cpu=4G` | |
| Number of cores | `-n 4` | `--ntasks=4` or `--cpus-per-task=4` | Use `--cpus-per-task` for threaded jobs — see [Tasks vs CPUs](pain-points.md#tasks-vs-cpus-ntasks-vs-cpus-per-task) |
| Number of nodes | `-R "span[hosts=1]"` | `--nodes=1` | |
| Exclusive node | `-x` | `--exclusive` | |
| GPU request | `-R "rusage[ngpus_physical=1]"` | `--gpus=1` or `--gres=gpu:1` | Syntax varies by cluster config |
| GPU type | `-R "select[ngpus_physical>0] rusage[ngpus_physical=1]" -q gpu` | `--gpus=a100:1` or `--gres=gpu:a100:1` | |
| Job array | `-J "myJob[1-100]"` | `--array=1-100` | See [Job Arrays](job-arrays.md) |
| Array concurrency limit | `-J "myJob[1-100]%10"` | `--array=1-100%10` | Max simultaneous tasks |
| Dependency (after OK) | `-w "done(12345)"` | `--dependency=afterok:12345` | |
| Dependency (after any) | `-w "ended(12345)"` | `--dependency=afterany:12345` | |
| Email address | `-u user@example.com` | `--mail-user=user@example.com` | |
| Email on start | `-B` | `--mail-type=BEGIN` | |
| Email on end | `-N` | `--mail-type=END` | |
| Email on start and end | `-B -N` | `--mail-type=BEGIN,END` | |
| Project / Account | `-P myproject` | `--account=myproject` | |
| Working directory | (submit from dir) | `--chdir=/path/to/dir` | LSF runs from submission dir by default; so does SLURM |
| Hold job | `-H` | `--hold` | |
| Requeue on failure | `-r` | `--requeue` | |

## Output filename patterns

LSF and SLURM use different tokens for dynamic filenames:

| Meaning | LSF | SLURM |
|---|---|---|
| Job ID | `%J` | `%j` |
| Array index | `%I` | `%a` |
| Job name | `%J` | `%x` |
| Array Job ID | `%J` | `%A` |
| Node (first) | — | `%N` |

!!! warning "Case matters"
    LSF uses uppercase `%J` and `%I`. SLURM uses lowercase `%j` and `%a`. Forgetting to change the case will result in literal `%J` appearing in your filenames.

## Example

=== "LSF"

    ```bash
    #!/bin/bash
    #BSUB -J alignment
    #BSUB -q normal
    #BSUB -W 4:00
    #BSUB -n 8
    #BSUB -M 16000
    #BSUB -o alignment.%J.out
    #BSUB -e alignment.%J.err

    module load samtools
    samtools sort -@ 8 input.bam -o sorted.bam
    ```

=== "SLURM"

    ```bash
    #!/bin/bash
    #SBATCH --job-name=alignment
    #SBATCH --partition=normal
    #SBATCH --time=04:00:00
    #SBATCH --cpus-per-task=8
    #SBATCH --mem=16G
    #SBATCH --output=alignment.%j.out
    #SBATCH --error=alignment.%j.err

    module load samtools
    samtools sort -@ 8 input.bam -o sorted.bam
    ```

!!! note "Memory units"
    LSF's `-M` typically specifies KB. SLURM's `--mem` defaults to MB, but you can use suffixes: `--mem=16G` for 16 GB. Always double-check units when converting.
