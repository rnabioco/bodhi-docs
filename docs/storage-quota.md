# Storage Quota: `quota_check`

`/beevol` is not one filesystem sitting on one machine — your files are spread across nine storage servers. Each one runs a small quota daemon that knows only its own share, so "how much am I using?" has nine answers that have to be added up.

[`quota_check`](https://github.com/rnabioco/bodhi-docs/blob/main/scripts/quota_check) asks all nine at once and gives you the total.

## Usage

```bash
quota_check
```

```text
User                       Used   Hard Quota   % Used
-------------------- ---------- ------------ --------
jdoe                      12.4T          30T    41.3%
```

That is the whole thing for most people. Three columns: what you are using, what you are allowed, and how close you are.

### Which server is holding it all

```bash
quota_check --full
```

```text
==================================================
User:       jdoe
Total used: 12.4T
Hard quota: 30T
% used:     41.3%
Hosts OK:   9/9

Per-host breakdown:
  172.20.8.116                         2.1T  (16.9%)
  172.20.8.118                         1.8T  (14.5%)
  ...
==================================================
```

The breakdown is worth a look when the total surprises you: the servers each hold a slice of your directory tree, so an unbalanced split usually means one project has grown much faster than the rest.

### Someone else, or a script

```bash
quota_check -u jdoe            # another user (you need to be able to see their account)
quota_check --json             # machine-readable
quota_check --json | jq -r '.percent'
```

`--json` reports sizes twice, as raw `_kb` integers and as the formatted strings the tables print, so you do not have to parse `30.2T` back into a number.

!!! note "`-b` still works"
    The summary above used to require `-b`, and the over-quota notification mail told people to run `quota_check -b`. The flag is still accepted and now does nothing — the summary is what you get by default. Ask for `--full` when you want the old, longer output.

## Over quota?

Being over quota is not an error and `quota_check` will not fail because of it — the percentage is the answer. But writes will start failing once the filesystem enforces the limit, so treat anything past ~90% as something to act on.

Before asking for more space, find out what is actually using it:

```bash
# biggest directories under your home, largest first
du -sh ~/* 2>/dev/null | sort -rh | head -20
```

Common culprits on Bodhi:

- **Pipeline work directories** — `work/`, `.nextflow/`, `.snakemake/` and friends keep every intermediate. They are usually safe to delete once a run has been archived.
- **Conda/pixi environments and package caches** — `~/.conda/pkgs`, `~/.cache/pixi`, `~/.cache/uv`. Clearing the caches costs you a re-download, nothing more.
- **Old sequencing data** already backed up elsewhere. See [Backup Instructions](backups.md) before deleting anything you cannot re-download.

If the usage is legitimate, contact the storage administrator listed in [Getting Help](getting-help.md) to ask for an increase.

## Running it on a compute node

`quota_check` needs nothing but `bash` and coreutils — it speaks to the storage daemons over TCP directly — so it runs anywhere on the cluster, including inside a batch job or an [interactive session](sinteractive.md).

One caveat: the *limits* live in `/etc/quota_current.txt`, which exists on the head node only. On a compute node without it, usage still reports correctly but the `Hard Quota` and `% Used` columns read `-`:

```text
User                       Used   Hard Quota   % Used
-------------------- ---------- ------------ --------
jdoe                      12.4T            -        -
```

Admins can close that gap by publishing the file to `/cluster/share`, which every node mounts — see [the admin guide](admin.md#storage-quotas).

## Full documentation

```bash
man quota_check
```

The man page covers `--all`, the `--email` notification run, the `QUOTA_CHECK_*` environment variables, and the quota file format.
