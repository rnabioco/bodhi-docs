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

The `sinteractive` and `bodhi-splash` helpers install via `make`:

```bash
# Per-user install (default): copies into ~/.local/bin
make install

# System-wide install (as root): sinteractive to /usr/local/bin and the
# login splash to /etc/profile.d/bodhi-splash.sh
sudo make install
```

Override the per-user location with `PREFIX`, e.g. `make install PREFIX=~/bin`.

## Upgrading tmux

`sinteractive` runs `tmux` **on the allocated compute node**, and `/usr/local`
is node-local, so the latest tmux must be installed on every node. These targets
build the latest [tmux release](https://github.com/tmux/tmux/wiki) from source
and fan it out to the cluster. They **must be run as root** on the head node:

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
- `tmux-push` copies to a temp name and renames into place, so running
  `sinteractive` sessions aren't disturbed.

## Converter script

A sed-based helper that converts common `#BSUB` directives and `$LSB_*` variables to SLURM equivalents:

```bash
bash scripts/lsf2slurm.sh myjob.lsf > myjob.slurm
```

See the [converter documentation](https://rnabioco.github.io/bodhi-docs/conversion-script/) for details on what it does and doesn't handle.

## Deployment

Pushes to `main` automatically build and deploy to GitHub Pages via GitHub Actions. The site is served from the `gh-pages` branch.

To enable: **Settings → Pages → Source → `gh-pages` branch**.
