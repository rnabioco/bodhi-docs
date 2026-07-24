# Interactive Sessions with `sinteractive`

The `sinteractive` script launches a persistent interactive session on a
compute node using tmux. It is developed in its own repository —
[rnabioco/sinteractive](https://github.com/rnabioco/sinteractive) — which
holds the script, man page, full documentation, and admin build targets. This
page covers using it on Bodhi.

## Why use `sinteractive` instead of `srun --pty bash`?

| | `srun --pty bash` | `sinteractive` |
|---|---|---|
| Survives SSH disconnects | No — session is lost | Yes — tmux keeps it alive |
| Multiple terminal panes | No | Yes — tmux split/window support |
| X11 forwarding | Manual setup | Automatic on connect (`ssh -X`) |
| Reconnect to session | Not possible | `sinteractive --attach JOBID` |

!!! tip "When to use which"
    Use `srun --pty bash` for quick, throwaway interactive work. Use `sinteractive` when you need a session that persists through network interruptions or when you want tmux features like split panes.

## Installation

`sinteractive` is installed cluster-wide on Bodhi at
`/usr/local/bin/sinteractive`, so it should already be on your `PATH`. To
install your own copy (or to use it on another cluster):

```bash
git clone https://github.com/rnabioco/sinteractive
cd sinteractive
make install    # copies to ~/.local/bin and installs the man page
```

## Usage

```bash
sinteractive [OPTIONS] [SBATCH_ARGS...]
```

Common options (see `sinteractive --help` or `man sinteractive` for the full
list, including `--detach`, `--status`, and `--json` for scripting):

| Option | Description | Default |
|---|---|---|
| `--node NODE` | Request a specific compute node | any available |
| `--partition PART` | SLURM partition | `interactive` |
| `--time TIME` | Wall time limit (supports `8h`, `30m`, `1d12h`, …) | `1 day` |
| `-j`, `--threads N` | Number of CPUs (alias for `--cpus-per-task`) | `2` |
| `-m`, `--mem SIZE` | Memory | `8G` |
| `-n`, `--name NAME` | Tag the session with a name for easy reattach (`--attach NAME`) | |
| `--mouse` | Enable tmux mouse support (scroll, click panes, drag to resize) | off |
| `-a`, `--attach JOBID` | Reattach to a running session | |
| `-l`, `--list` | List running sinteractive sessions | |

All other arguments are passed directly to `sbatch`, so you can use any
`sbatch` option. Personal defaults can be set with `SINTERACTIVE_*`
environment variables in your `~/.bashrc` — see the
[repo README](https://github.com/rnabioco/sinteractive#environment-variables),
which also covers configuring it for other clusters such as CU Alpine.

### Examples

```bash
# Default: 1-day session, 2 CPUs, 8G memory
sinteractive

# Run on a specific node
sinteractive --node compute01

# 2-hour session on the rna partition
sinteractive --time=2:00:00 --partition=rna

# Override default memory and CPUs
sinteractive --mem=16G --cpus-per-task=4

# GPU session
sinteractive --partition=gpu --gpus=1 --mem=16G

# Longer session on the normal partition (up to 3 days)
sinteractive --time=1-12:00:00 --partition=normal
```

## Reconnecting after a disconnect

If your SSH connection drops or you intentionally detach (`Ctrl-b d`), the tmux session **keeps running** on the compute node and your work is safe. To reconnect from the login node:

```bash
# List your running sessions
sinteractive --list
#   JOBID       NAME                  NODE            PARTITION     ELAPSED     TIMELIMIT   CWD
#   12345       rna-seq               compute01       cpu           01:23:45    1-00:00:00  ~/projects/rna-seq

# Reattach
sinteractive --attach 12345
```

Sessions launched with `-n NAME` can be reattached by name (`sinteractive --attach NAME`). Forgot to name one? Press `Ctrl-b $` inside the session to name (or rename) it in place — the new name shows up in the status bar, `squeue`, `--list`, and works with `--attach NAME`.

!!! info "This is the key advantage over `srun --pty bash`"
    With `srun`, a dropped SSH connection kills your session and any running processes. With `sinteractive`, you just reconnect and pick up where you left off.

## Scripting and agent use

`sinteractive` has a headless mode (`--detach`, `--status`, `--json`) designed
for scripts and coding agents, plus a
[Claude Code skill](https://github.com/rnabioco/sinteractive#scripting-and-agent-use)
that teaches agents cluster etiquette (run heavy work in an allocation, reuse
sessions, check the time budget). See the repo README for details; install the
skill from a checkout with `make skill-install`.

## Tips

### Basic tmux commands

| Action | Key |
|---|---|
| Show help popup (job info, keys) | `Ctrl-b h` |
| Detach from session | `Ctrl-b d` |
| Name/rename session (updates squeue and `--attach` name) | `Ctrl-b $` |
| Split pane horizontally | `Ctrl-b "` |
| Split pane vertically | `Ctrl-b %` |
| Switch between panes | `Ctrl-b arrow-key` |
| Scroll up | `Ctrl-b [` then arrow keys (press `q` to exit) |

!!! tip "Mouse support"
    Start with `sinteractive --mouse` to scroll with the wheel, click to switch
    panes, and drag borders to resize. Mouse mode captures terminal selection,
    so hold **Shift** when you want to select text for an OS-level copy (tmux's
    own mouse selection is copied out over SSH automatically).

### Cancelling the job

Exiting the tmux session (type `exit` or `Ctrl-d` in all panes) automatically cancels the SLURM job. You can also cancel it directly:

```bash
scancel <JOBID>
```

!!! warning "Wall time"
    `sinteractive` defaults to a **1 day** wall time on the `interactive` partition. For longer sessions, switch to the `normal` partition (up to 3 days): `sinteractive --partition=normal --time=2-00:00:00`.

!!! info "Job limit"
    The `interactive` partition limits each user to **3 concurrent jobs**. If you need more simultaneous sessions, use the `normal` partition.
