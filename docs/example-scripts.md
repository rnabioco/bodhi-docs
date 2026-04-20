# Example Scripts

Complete before/after examples for common job types. Each example shows the full LSF script alongside its SLURM equivalent.

## Simple job

=== "LSF"

    ```bash
    #!/bin/bash
    #BSUB -J simple_job
    #BSUB -q normal
    #BSUB -W 1:00
    #BSUB -n 1
    #BSUB -M 4000
    #BSUB -o simple.%J.out
    #BSUB -e simple.%J.err

    module load R/4.3.0

    Rscript my_analysis.R
    ```

=== "SLURM"

    ```bash
    #!/bin/bash
    #SBATCH --job-name=simple_job
    #SBATCH --partition=normal
    #SBATCH --time=01:00:00
    #SBATCH --ntasks=1
    #SBATCH --mem=4G
    #SBATCH --output=simple.%j.out
    #SBATCH --error=simple.%j.err

    module load R/4.3.0

    Rscript my_analysis.R
    ```

## Array job

=== "LSF"

    ```bash
    #!/bin/bash
    #BSUB -J "align[1-50]%10"
    #BSUB -q normal
    #BSUB -W 4:00
    #BSUB -n 8
    #BSUB -M 16000
    #BSUB -o logs/align.%J.%I.out
    #BSUB -e logs/align.%J.%I.err

    module load samtools/1.17
    module load bwa/0.7.17

    SAMPLE=$(sed -n "${LSB_JOBINDEX}p" samples.txt)
    R1=fastq/${SAMPLE}_R1.fastq.gz
    R2=fastq/${SAMPLE}_R2.fastq.gz

    bwa mem -t 8 ref/genome.fa $R1 $R2 \
        | samtools sort -@ 4 -o bam/${SAMPLE}.sorted.bam

    samtools index bam/${SAMPLE}.sorted.bam
    ```

=== "SLURM"

    ```bash
    #!/bin/bash
    #SBATCH --job-name=align
    #SBATCH --partition=normal
    #SBATCH --time=04:00:00
    #SBATCH --cpus-per-task=8
    #SBATCH --mem=16G
    #SBATCH --array=1-50%10
    #SBATCH --output=logs/align.%A.%a.out
    #SBATCH --error=logs/align.%A.%a.err

    module load samtools/1.17
    module load bwa/0.7.17

    SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" samples.txt)
    R1=fastq/${SAMPLE}_R1.fastq.gz
    R2=fastq/${SAMPLE}_R2.fastq.gz

    bwa mem -t 8 ref/genome.fa $R1 $R2 \
        | samtools sort -@ 4 -o bam/${SAMPLE}.sorted.bam

    samtools index bam/${SAMPLE}.sorted.bam
    ```

## GPU job

=== "LSF"

    ```bash
    #!/bin/bash
    #BSUB -J gpu_train
    #BSUB -q gpu
    #BSUB -W 24:00
    #BSUB -n 4
    #BSUB -M 32000
    #BSUB -R "select[ngpus_physical>0] rusage[ngpus_physical=1]"
    #BSUB -o train.%J.out
    #BSUB -e train.%J.err

    module load cuda/11.8
    module load anaconda3

    conda activate ml_env

    python train.py \
        --epochs 100 \
        --batch-size 64 \
        --gpus 1
    ```

=== "SLURM"

    ```bash
    #!/bin/bash
    #SBATCH --job-name=gpu_train
    #SBATCH --partition=gpu
    #SBATCH --account=<your_gpu_account>
    #SBATCH --time=24:00:00
    #SBATCH --cpus-per-task=4
    #SBATCH --mem=32G
    #SBATCH --gres=gpu:1
    #SBATCH --output=train.%j.out
    #SBATCH --error=train.%j.err

    module load cuda/11.8
    module load anaconda3

    conda activate ml_env

    python train.py \
        --epochs 100 \
        --batch-size 64 \
        --gpus 1
    ```

!!! note "GPU partition requires an account"
    The `gpu` partition is gated by `AllowAccounts`. You must pass `--account=<your_gpu_account>` or submissions will be rejected. See the [GPU Jobs](gpu.md) guide for details on hardware, limits, and requesting access.

## Job with dependencies

=== "LSF"

    ```bash
    # Step 1: Alignment
    JOB1=$(bsub -J align -q normal -W 4:00 -n 8 -o align.%J.out < align.sh | grep -oP '\d+')

    # Step 2: Sort (after align completes successfully)
    JOB2=$(bsub -J sort -q normal -W 2:00 -n 4 -w "done($JOB1)" -o sort.%J.out < sort.sh | grep -oP '\d+')

    # Step 3: Stats (after sort completes successfully)
    bsub -J stats -q short -W 0:30 -n 1 -w "done($JOB2)" -o stats.%J.out < stats.sh
    ```

=== "SLURM"

    ```bash
    # Step 1: Alignment
    JOB1=$(sbatch --job-name=align --partition=normal --time=04:00:00 --cpus-per-task=8 --output=align.%j.out align.sh | awk '{print $4}')

    # Step 2: Sort (after align completes successfully)
    JOB2=$(sbatch --job-name=sort --partition=normal --time=02:00:00 --cpus-per-task=4 --dependency=afterok:$JOB1 --output=sort.%j.out sort.sh | awk '{print $4}')

    # Step 3: Stats (after sort completes successfully)
    sbatch --job-name=stats --partition=short --time=00:30:00 --ntasks=1 --dependency=afterok:$JOB2 --output=stats.%j.out stats.sh
    ```

!!! note "Capturing the job ID"
    - LSF: `bsub` prints `Job <12345> is submitted to queue <normal>.` — parse with `grep -oP '\d+'`
    - SLURM: `sbatch` prints `Submitted batch job 12345` — parse with `awk '{print $4}'`

## Interactive session

=== "LSF"

    ```bash
    # Basic interactive session
    bsub -Is -q interactive bash

    # With resources
    bsub -Is -q interactive -n 4 -M 8000 -W 2:00 bash

    # Interactive with GPU
    bsub -Is -q gpu -R "rusage[ngpus_physical=1]" -n 4 -M 16000 bash
    ```

=== "SLURM"

    ```bash
    # Basic interactive session
    srun --pty bash

    # With resources
    srun --partition=interactive --cpus-per-task=4 --mem=8G --time=02:00:00 --pty bash

    # Interactive with GPU
    srun --partition=gpu --gpus=1 --cpus-per-task=4 --mem=16G --pty bash
    ```

!!! tip "Interactive jobs"
    In SLURM, `srun --pty bash` gives you an interactive shell on a compute node. You can also use `salloc` to allocate resources first, then `srun` within that allocation.

    For a **persistent** interactive session that survives SSH disconnects, see the [`sinteractive` script](sinteractive.md).
