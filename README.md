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

## sinteractive

The `sinteractive` helper (persistent tmux-backed interactive sessions on
compute nodes) lives in its own repository, along with its man page, build
targets, and Claude Code skill: <https://github.com/rnabioco/sinteractive>.
The user-facing guide stays on this site at
[Interactive Sessions](https://rnabioco.github.io/bodhi-docs/sinteractive/).

## Installing the splash

The `bodhi-splash` login banner installs via `make`:

```bash
# Per-user install (default): copies into ~/.local/bin
make install

# System-wide install (as root): to /etc/profile.d/bodhi-splash.sh
sudo make install
```

Override the per-user location with `PREFIX`, e.g. `make install PREFIX=~/bin`.

## Converter script

A sed-based helper that converts common `#BSUB` directives and `$LSB_*` variables to SLURM equivalents:

```bash
bash scripts/lsf2slurm.sh myjob.lsf > myjob.slurm
```

See the [converter documentation](https://rnabioco.github.io/bodhi-docs/conversion-script/) for details on what it does and doesn't handle.

## Deployment

Pushes to `main` automatically build and deploy to GitHub Pages via GitHub Actions. The site is served from the `gh-pages` branch.

To enable: **Settings → Pages → Source → `gh-pages` branch**.
