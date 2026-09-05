# Interactive Sessions with `sinteractive`

`sinteractive` gives you a shell on a compute node that **survives an SSH
disconnect**. It submits a batch job that starts a terminal multiplexer on the
allocated node and connects you to it; when your laptop sleeps or the VPN
drops, the job keeps running and you reattach where you left off.

It is maintained at [**rnabioco/sinteractive**](https://github.com/rnabioco/sinteractive),
with the full reference — every command, every environment variable, the
Claude Code integration — at <https://rnabioco.github.io/sinteractive/>. This
page covers what a Bodhi user needs.

!!! note "Version 1.0 changed the command line"
    `sinteractive` was rewritten as a single binary with
    [zellij](https://zellij.dev) compiled into it. Two things changed for you:

    - **Subcommands replaced flags.** `sinteractive attach 12345`, not
      `--attach 12345`; `sinteractive list`, not `--list`. The old spellings
      are gone.
    - **Nothing needs installing on the compute nodes.** The multiplexer is
      inside the binary, so there is no separate `tmux` to keep current.

    `Ctrl+b` is still the prefix key, so the muscle memory carries over.

## Why not just `srun --pty bash`?

| | `srun --pty bash` | `sinteractive` |
|---|---|---|
| Survives SSH disconnects | No — the session is lost | Yes — the session keeps running |
| Reconnect | Not possible | `sinteractive attach JOBID\|NAME` |
| Multiple panes | No | Splits, zoom, searchable scrollback |
| Status bar | None | Job id, node, walltime left, queue, notices |
| Resource monitor | None | `Ctrl+b m` — CPU, memory and GPU bars, in-session |
| X11 forwarding | Manual | `sinteractive attach --ssh` |

Use `srun --pty bash` for a quick throwaway command. Use `sinteractive` for
anything you would be annoyed to lose.

## Installation

Check what you have, and whether it can actually start a session:

```bash
sinteractive --version
sinteractive doctor      # is this install able to run a session from here?
```

`doctor` is the answer to "why did that not work" — it checks the binary, the
cache directory, the Slurm commands and whether the compute nodes can see the
binary. If it reports a problem, or `sinteractive` is missing or old, install
your own copy from the
[releases page](https://github.com/rnabioco/sinteractive/releases) (built for
Rocky 8 / glibc 2.28, x86_64):

```bash
mkdir -p ~/.local/bin
mv sinteractive-x86_64-linux-gnu-glibc2.28 ~/.local/bin/sinteractive
chmod +x ~/.local/bin/sinteractive
sinteractive doctor
```

Make sure `~/.local/bin` is on your `$PATH` (add
`export PATH="$HOME/.local/bin:$PATH"` to `~/.bashrc` if it is not).

!!! warning "The binary has to live where the compute nodes can see it"
    The batch job runs *this same binary* on the allocated node, so it must be
    on a shared filesystem. `~/.local/bin` is under `/beevol` and is visible
    everywhere, which is why the per-user install always works. A copy in a
    node-local path (`/usr/local/bin`, `/tmp`) only works on nodes where that
    exact file exists — `sinteractive doctor --nodes` is what tells you.

## Launching a session

```bash
sinteractive
```

That is a 1-day session on the `interactive` partition with 2 CPUs and 8 GB.
Override any of it:

| Option | Description | Default |
|---|---|---|
| `-p`, `--partition PART` | Slurm partition | `interactive` |
| `-t`, `--time TIME` | Wall time (`8h`, `30m`, `1d12h`, or `D-HH:MM:SS`) | `24:00:00` |
| `-j`, `--threads N` | CPUs (`--cpus-per-task`) | `2` |
| `-m`, `--mem SIZE` | Memory | `8G` |
| `-n`, `--name NAME` | Tag the session, so you can `attach NAME` | |
| `--node NODE` | A specific node (`--nodelist`) | any |
| `--detach` | Launch without attaching, print the details and return | |
| `--no-mouse` | Turn mouse mode off | mouse is on |

Anything else is passed straight through to `sbatch`, in any order — so
`--gres=gpu:1`, `--qos=long`, `--account=...` all work.

```bash
# Named, 8 hours, 4 CPUs, 16 GB
sinteractive -n rna-seq -t 8h -j 4 -m 16G

# A GPU session
sinteractive -p gpu --gres=gpu:1 -m 16G

# Launch it now, come back to it later
sinteractive --detach -n build
sinteractive attach build
```

### Bodhi's `interactive` partition

| | |
|---|---|
| Nodes | `compute[04,06-07]` (264 CPUs total) |
| Max wall time | 5 days |
| Default wall time | 8 hours (`sinteractive` asks for 1 day) |
| QoS | none imposed — your jobs land on `normal` |

Because the partition imposes no QoS, a session here runs under the default
`normal` QoS and is bounded by the partition's own `MaxTime`. The
`interactive` QoS — 12 hours, 16 CPUs, 8 GB — applies **only** if you ask for
it with `--qos=interactive`.

The partition is small and it carries everyone's shells, so treat a session as
a place to *orchestrate* work, not to run it. Heavy jobs belong in their own
allocation on a compute partition:

```bash
srun -p rna -c 16 --mem 64G -t 4:00:00 -J bwa-align --comment=bwa-align -- ./run.sh
```

!!! info "Sessions are trimmed to fit maintenance"
    Bodhi's monthly maintenance window is a Slurm `MAINT` reservation. A
    session that would overlap it is shortened to end just before it starts,
    and the session tells you so in its notices (`Ctrl+b n`).

## Managing sessions

| Command | What it does |
|---|---|
| `sinteractive list` | Your running sessions |
| `sinteractive attach [TARGET]` | Reattach by JOBID or NAME; no target = your only session |
| `sinteractive attach --ssh` | Reattach over `ssh -X`, for X11 forwarding |
| `sinteractive status [TARGET]` | State, node, time remaining |
| `sinteractive cancel TARGET` | End a session |
| `sinteractive queue` | All your jobs: running, pending with reasons, recent history |
| `sinteractive monitor [TARGET]` | Live CPU/GPU/process view of a session's node |
| `sinteractive quota` | Your `/beevol` storage usage |
| `sinteractive doctor [--nodes]` | Check the install, and optionally every node |

```bash
sinteractive list
sinteractive attach rna-seq
```

!!! note "X11 after reattaching"
    A plain `attach` reconnects through `srun --overlap`, which carries no
    `DISPLAY`. If you need to launch GUI apps after reattaching, use
    `sinteractive attach --ssh`.

## Inside a session

`Ctrl+b` is the only chord: press it, then one key. `Ctrl+b h` shows this
legend in the status bar.

| Keys | Action |
|---|---|
| `Ctrl+b d` | Detach — the session keeps running |
| `Ctrl+b h` | Key legend; again for the next page, `Esc` to close |
| `Ctrl+b n` | Read the notices (quota, trimmed end time, hints) |
| `Ctrl+b m` | Focus the monitor panel — CPU, memory and GPU bars for this session and every job launched from it; `t` for the full process view, `esc` back to the shell |
| `Ctrl+b q` | Your queue in a floating pane; `q` or `Esc` closes it |
| `Ctrl+b c` | New pane |
| `Ctrl+b "` / `Ctrl+b %` | Split down / split right |
| `Ctrl+b z` | Zoom the focused pane |
| `Ctrl+b o`, `Ctrl+b ←↑→↓` | Move between panes |
| `Ctrl+b x` | Close the focused pane |
| `Ctrl+b [` | Scroll mode: `j`/`k`, `PgUp`/`PgDn`, `/` to search, `q` to leave |
| `Ctrl+b Ctrl+b` | Send a literal `Ctrl+b` |

The status bar reads like this:

```
● sint 261172 · bodhi · compute07 · 22h left · jobs 3R · ^b h help
```

The dot spins while the session starts, then turns yellow and red as the
walltime runs down. `jobs` counts your running and pending jobs, and a
`⚠ N notices` counter appears when the session has something to tell you —
red while you are over your storage quota.

Mouse mode is on: scroll with the wheel, click to focus a pane, drag borders
to resize, and select text to copy it to your local clipboard. Hold **Shift**
to select with the terminal instead.

### Ending a session

Exiting the last shell (`exit` or `Ctrl+d`) ends the job. From the login node,
`sinteractive cancel NAME|JOBID` — or `scancel JOBID` — does the same.

## Personal defaults

Set these in `~/.bashrc`; explicit flags always win.

| Variable | Description | Default |
|---|---|---|
| `SINTERACTIVE_TIME` | Default wall time | `24:00:00` |
| `SINTERACTIVE_PARTITION` | Default partition | `interactive` |
| `SINTERACTIVE_CPUS` | Default CPU count | `2` |
| `SINTERACTIVE_MEM` | Default memory | `8G` |
| `SINTERACTIVE_MOUSE` | `on` / `off` | `on` |
| `SINTERACTIVE_THEME` | `dark`, `light` or `auto` | `auto` |

```bash
export SINTERACTIVE_MEM=16G
export SINTERACTIVE_CPUS=4
```

The [full list](https://rnabioco.github.io/sinteractive/) covers the cache
directory, warning thresholds, quota daemons and the Claude Code hooks.

## Scripting and coding agents

Every reporting command takes `--json`, and a session can be driven from
outside it — which is how a coding agent such as
[Claude Code](https://code.claude.com/docs/) works on the cluster without
running anything on the login node:

```bash
# Reuse the session named 'agent', or launch it if it isn't there
sinteractive session ensure agent

# Read the last 40 lines of its screen
sinteractive session peek agent -n 40

# Type a command into it
sinteractive session send agent 'make test'

# Machine-readable state
sinteractive list --json
sinteractive status agent --json
```

To run a command in a session's allocation and get its exit code back:

```bash
srun --overlap --jobid=JOBID -- bash -lc 'make test'
```

!!! tip "Claude Code integration"
    `sinteractive claude install` installs skills that teach Claude Code how
    work is done here — heavy work goes in its own allocation, jobs get named,
    `/tmp` is node-local — along with a status line, session hooks and an MCP
    server. See the
    [upstream docs](https://rnabioco.github.io/sinteractive/) for what it
    writes into your settings.
