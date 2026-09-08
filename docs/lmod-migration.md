# Lmod Migration

An audit of Bodhi's current environment-modules setup and a phased plan for
migrating to [Lmod](https://lmod.readthedocs.io/), the Lua-based module system.

!!! note "Audience"
    This is an **admin/infrastructure** document. Migrating the module system is
    a cluster-wide change that affects every user's `module load`; it is not a
    per-user action. Nothing here should be executed without coordinating a
    maintenance window (see [Admin Guide](admin.md#scheduling-maintenance)).

---

## TL;DR

Bodhi already runs **environment-modules 5.3.0** — the modern Tcl implementation,
not the legacy 3.x most Lmod migration horror stories describe. The software tree
is **small (~124 packages), flat, and syntactically simple**. Lmod reads Tcl
modulefiles natively, so **no bulk rewrite to Lua is required**. This is a
**low-complexity** migration whose main payoff is ergonomics (`ml`, `module
spider`, user collections) and alignment with the wider HPC world — not a
performance necessity at this scale.

---

## Current state (audit)

| Property | Value |
|---|---|
| Implementation | environment-modules **5.3.0** (2023-05-14), Tcl |
| `modulecmd` | `/usr/share/Modules/libexec/modulecmd.tcl` |
| Tcl available | 8.6 (`/usr/bin/tclsh`) |
| Lua available | 5.4.4 (`/usr/bin/lua`) |
| Lmod present | **No** |
| Distinct software packages | ~124 |
| Modulefiles (`modules-sw`) | 237 files across 125 subdirs |
| Lua modulefiles | 0 (all Tcl) |
| Module hierarchy | None (flat MODULEPATH) |

### MODULEPATH

Seven entries are configured, but **only two are populated**:

```
/etc/scl/modulefiles                              # system (empty on Bodhi)
/usr/share/Modules/modulefiles                    # system defaults
/etc/modulefiles                                  # empty
/usr/share/modulefiles                            # empty
/cluster/software/modules-sw/modulefiles          # ← main software tree (237 files)
/cluster/software/modules-perl/modulefiles        # 1 file
/cluster/software/modules-openmpi/modulefiles     # ← MISSING directory (stale entry)
```

!!! warning "Stale MODULEPATH entry"
    `/cluster/software/modules-openmpi/modulefiles` is in MODULEPATH but the
    directory does not exist. Harmless today, but it should be removed as part of
    the cleanup — Lmod will warn about missing MODULEPATH components.

### Modulefile syntax profile

A scan of all `modules-sw` modulefiles for Lmod-relevant constructs:

| Construct | Files | Lmod compatibility |
|---|---|---|
| `prepend-path` | 128 | ✅ native |
| `append-path` | 6 | ✅ native |
| `setenv` | 11 | ✅ native |
| `module-whatis` | 131 | ✅ native |
| `proc ModulesHelp` / `puts stderr` | 132 | ✅ native (help block) |
| `module-version … default` (in `.modulerc`) | 104 | ⚠️ works, validate (see below) |
| `if {…}` / `[ … ]` Tcl logic | 34 | ⚠️ runs via Tcl bridge, spot-check |
| `module load` inside a modulefile | 35 | ⚠️ works; prefer `depends-on` |
| `exec` | 1 | ⚠️ review (google-cloud-sdk) |
| `conflict` | 0 | — |
| `prereq` | 0 | — |
| `module switch` / `set-alias` / `source-sh` / `system` | 0 | — |

The overwhelming majority of files are trivial `PATH` prepends. Representative
example (`bwa/0.7.19`):

```tcl
#%Module1.0#####################################################################
proc ModulesHelp { } {
        puts stderr "\tAdds BWA 0.7.19 to environment paths\n"
}
module-whatis   "loads BWA 0.7.19 module"
set             bwaroot      /cluster/software/modules-sw/bwa/bwa-0.7.19
prepend-path    PATH         $bwaroot
prepend-path    PATH         $bwaroot/bwakit
```

### Default-version mechanism

Defaults are set with **104 `.modulerc` files**, each of the form:

```tcl
#%Module1.0#####################################################################
module-version bcftools/1.22.1 default
```

There are **no `.version` files** (the older, deprecated mechanism) — good. Lmod
honors `module-version … default` from `.modulerc`, but default resolution
differs subtly from Tcl Modules, so every default must be validated after the
switch (see Phase 3).

---

## Issues to fix before/during migration

These are the only non-mechanical items the audit surfaced:

1. **`trimmomatic/0.38` is missing the `#%Module` magic cookie.** Lmod requires
   the `#%Module` first-line cookie to recognize a Tcl modulefile; without it the
   file will misparse or be skipped. Add the cookie.
2. **`google-cloud-sdk/544.0.0` uses `exec`** to run a bash completion include at
   load time:
   ```tcl
   if { [file exists …/completion.bash.inc] } {
       exec …/completion.bash.inc
   }
   ```
   This is fragile under any module system (its stdout is discarded; it doesn't
   actually source completions into the user's shell). Rewrite to not `exec` at
   load — drop it, or ship the completion via a shell profile snippet.
3. **35 modulefiles chain `module load`** (e.g. `RingMapper/1.3` loads
   `python/2.7.18` via `is-loaded` + `module load`). These work under Lmod, but
   the idiomatic and safer form is `depends-on`, which reference-counts the
   dependency so it unloads cleanly. Optional but recommended.
4. **Remove the stale `modules-openmpi` MODULEPATH entry.**

---

## Why Lmod (and the honest ROI)

**Wins that apply at Bodhi's scale:**

- `ml` shorthand (`ml bwa`, `ml -gcc`, `ml`), and `module spider` for
  case-insensitive search across the whole tree — much better discovery than
  `module avail | grep`.
- **User collections**: `module save <name>` / `module restore <name>` so users
  can snapshot a working toolset. Frequently requested; env-modules 5 has a
  weaker version of this.
- Familiarity — most national HPC centers (TACC, CURC/Alpine, etc.) run Lmod, so
  new users and docs line up.

**Wins that don't really matter here (yet):**

- *Hierarchical modules* (compiler/MPI-dependent trees) — Bodhi's tree is flat
  and has no MPI stack, so the headline Lmod feature is unused. Worth adopting
  only if a toolchain hierarchy is introduced later.
- *Module caching* — a speed feature for trees with thousands of modules; at ~124
  packages `module avail` is already instant.

!!! tip "Is it worth doing?"
    At this scale the case is **ergonomics and ecosystem alignment, not
    necessity**. env-modules 5.3.0 is perfectly serviceable. The migration is
    cheap and low-risk, so it's a reasonable "yes" — but it's a quality-of-life
    upgrade, not a fix for a broken system.

---

## Migration plan

Lmod can run **alongside** env-modules and consume the **existing Tcl tree
read-only**, so this is a low-stakes, reversible rollout.

### Phase 0 — Prerequisites

Install Lmod and its Lua dependencies. Bodhi is RHEL 9 (el9); EPEL packages Lmod
directly:

```bash
# On the login node + all compute nodes (or the shared /cluster image)
dnf install epel-release
dnf install Lmod            # pulls lua, lua-posix, lua-filesystem, tcl
```

Alternatively build from source or via Spack if a specific Lmod version is
wanted. Confirm `tclsh` (8.6, present) is available on every node — Lmod shells
out to it to interpret Tcl modulefiles.

!!! warning
    Install on **every node**, not just the login node. Compute nodes must
    resolve `module load` inside batch jobs.

### Phase 1 — Parallel install, no default change

- Configure Lmod's `MODULEPATH` to point at the **existing**
  `/cluster/software/modules-sw/modulefiles` (and `modules-perl`). No files are
  copied or rewritten.
- Do **not** touch `/etc/profile.d/modules.sh`. Env-modules stays the default.
- Make Lmod opt-in for testing via an explicit init source, e.g.
  `source /usr/share/lmod/lmod/init/bash`.

### Phase 2 — Fix flagged files & clean up

Apply the four fixes from [Issues to fix](#issues-to-fix-beforeduring-migration):
add the trimmomatic cookie, rewrite the gcloud `exec`, optionally convert
`module load` → `depends-on`, and drop the stale MODULEPATH entry. All are safe
under env-modules too, so they can land before the cutover.

### Phase 3 — Smoke test every package

Validate that all ~124 packages load and that defaults resolve correctly under
Lmod. A mechanical sweep:

```bash
source /usr/share/lmod/lmod/init/bash
export MODULEPATH=/cluster/software/modules-sw/modulefiles

fail=0
for m in $(module -t --redirect avail 2>/dev/null); do
  if module load "$m" 2>err.log; then
    module unload "$m" 2>/dev/null
  else
    echo "LOAD FAIL: $m"; cat err.log; fail=1
  fi
done
echo "done (fail=$fail)"

# Confirm each package's *default* matches the old .modulerc default:
module -t --redirect avail | sort > /tmp/lmod-avail.txt
module -D --redirect avail 2>&1 | grep -i default   # inspect (D)efault markers
```

Pay special attention to the 34 files with `if`/`[…]` logic and the 104
`.modulerc` defaults.

### Phase 4 — Cutover

During a maintenance window
([reservation](admin.md#scheduling-maintenance)):

- Swap the shell init so new logins get Lmod:
  `/etc/profile.d/modules.sh` → Lmod's `z00_lmod.sh` (`profile.d`).
- **Keep env-modules installed** for rollback — reverting is a one-line
  profile.d swap.
- Update the [login splash](login-splash.md) / user docs to mention `ml` and
  `module spider`.
- Announce user-facing changes (below).

### Phase 5 — Soak & decommission

After a soak period (e.g. one maintenance cycle) with no regressions, remove the
env-modules profile.d hooks. Leave the package installed until confidence is
high.

---

## User-facing changes to announce

Almost everything is identical; the deltas worth a heads-up:

| Old (env-modules) | New (Lmod) | Notes |
|---|---|---|
| `module load bwa` | `module load bwa` **or** `ml bwa` | unchanged; `ml` is the new shorthand |
| `module avail` | `module avail` / `module spider bwa` | `spider` searches the whole tree |
| `module list` | `ml` (no args) | shorthand |
| — | `module save fqxv` / `module restore fqxv` | **new**: save/restore toolsets |
| `module load bcftools` (→ default) | same | *validate the default resolves the same version* |

!!! note "`.bashrc` impact"
    User `.bashrc` files that call `module load modules-init` (as the reference
    `bashrc.example` does) keep working — the `module` function is provided by
    whichever system is active. No user `.bashrc` edits are required for the
    cutover.

---

## Rollback

Because Lmod never modifies the Tcl modulefiles and env-modules stays installed
through Phase 5, rollback at any point is: **restore the original
`/etc/profile.d/modules.sh` and remove the Lmod profile.d snippet.** New logins
revert immediately; no data or modulefile changes to undo.
