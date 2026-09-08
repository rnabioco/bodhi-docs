# Bodhi HPC User Guide

Documentation site for the Bodhi HPC cluster — SLURM usage, backups, and support contacts.

**Live site:** <https://rnabioco.github.io/bodhi-docs/>

## Local development

Requires [pixi](https://pixi.sh):

```bash
# Serve docs locally at http://localhost:8000
pixi run docs

# Build the site (strict mode)
pixi run build
```

## Installing the scripts

The `bodhi-splash` login splash and the `quota_check` helper install via
`make`:

```bash
# Per-user install (default): copies into ~/.local/bin
make install

# System-wide install (as root): quota_check to /usr/local/bin and the
# login splash to /etc/profile.d/bodhi-splash.sh
sudo make install
```

Override the per-user location with `PREFIX`, e.g. `make install PREFIX=~/bin`.
`make install-quota-check` installs just `quota_check` and its man page.

`/usr/local` is node-local, so the compute nodes need their own copy of
`quota_check`: `sudo make quota-nodes` fans it out and `make quota-nodes-check`
reports what each node actually has. The hard-quota table is published to the
shared mount with `sudo make publish-quota-file`.

`make install-repo-audit` installs `repo-audit` and its Slurm driver
`repo-audit-slurm`. `repo-audit` is a read-only-by-default auditor for git
worktree/branch/cargo-`target/` cleanup candidates across one or more
directory trees (`repo-audit scan ~/devel ~/projects`), plus an `apply` mode
that re-verifies each candidate against live state before acting and only
ever prints what it would do unless given `--yes`. It never touches a
worktree containing pod5/fast5/bam/cram/npz/npy/parquet/fastq/arrow files —
those are always left for a human to look at.

A scan over a large tree is real CPU and I/O, not something to run in an
interactive shell. `repo-audit-slurm` submits `scan` as its own sbatch job
and returns immediately with a job id:

```bash
repo-audit-slurm ~/devel/rnabioco
```

Report and candidates land under `~/scratch/repo-audit/<timestamp>/` by
default (`--out DIR` to override); `--cpus`/`--mem`/`--walltime`/`--partition`
size the allocation, and anything else is passed straight through to
`repo-audit scan` (`--hours`, etc.). Only `scan` is ever queued this way —
`apply` acts on live git state and stays a foreground, attended command.

### `sinteractive` lives elsewhere

`sinteractive` is no longer part of this repository. It is maintained at
[rnabioco/sinteractive](https://github.com/rnabioco/sinteractive) — install it
from that checkout (`make install`, or `sudo make nodes` to put the binary on
every compute node), not from here. The
[user guide](https://rnabioco.github.io/bodhi-docs/sinteractive/) on this site
still covers it for Bodhi users.

## Upgrading tmux

`sinteractive` has zellij compiled in since 1.0 and no longer needs tmux, so
these targets exist only for users who run tmux themselves. `/usr/local` is
node-local, so a build has to be fanned out to every node. They **must be run
as root** on the head node:

```bash
# One-time: install build dependencies (RHEL/Rocky 9)
sudo make tmux-deps

# Download, build, and install into /usr/local
sudo make tmux

# Copy the built binary to every Slurm compute node
sudo make tmux-push

# Or do the build + push in one step
sudo make tmux-all
```

- Bump the version with `TMUX_VERSION`, e.g. `sudo make tmux TMUX_VERSION=3.8`.
- Restrict the push to specific nodes with `NODES`, e.g.
  `sudo make tmux-push NODES="compute00 compute01"` (defaults to all Slurm
  nodes from `sinfo`).
- `tmux-push` copies to a temp name and renames into place, so running tmux
  servers aren't disturbed.

## Converter script

A sed-based helper that converts common `#BSUB` directives and `$LSB_*` variables to SLURM equivalents:

```bash
bash scripts/lsf2slurm.sh myjob.lsf > myjob.slurm
```

See the [converter documentation](https://rnabioco.github.io/bodhi-docs/conversion-script/) for details on what it does and doesn't handle.

## Deployment

Pushes to `main` automatically build and deploy to GitHub Pages via GitHub Actions. The site is served from the `gh-pages` branch.

To enable: **Settings → Pages → Source → `gh-pages` branch**.
