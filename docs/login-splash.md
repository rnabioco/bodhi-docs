# Login Splash Screen

The `bodhi-splash` script displays a login splash screen with system information, admin announcements, and a maintenance countdown banner.

## What users see

```
┌──────────────────────────────────────────────────────────────────────┐
│ UPCOMING MAINTENANCE: Thursday, March 26, 2026                       │
│ Scheduled maintenance in 3 days. Plan accordingly.                   │
├──────────────────────────────────────────────────────────────────────┤
│ BODHI HPC Cluster                                        amc-bodhi   │
├──────────────────────────────────────────────────────────────────────┤
│ OS:       Rocky Linux 9.6                                            │
│ Kernel:   5.14.0-570.17.1.el9_6.x86_64                              │
│ Uptime:   102 days, 18:26                                            │
│ Load:     1.58, 1.81, 1.63                                           │
├──────────────────────────────────────────────────────────────────────┤
│ >>> New GPU partition available                                       │
│     The 'a100' partition is now available for jobs.                   │
├──────────────────────────────────────────────────────────────────────┤
│ Help:  David Farrell                                                 │
│ Docs:  https://rnabioco.github.io/bodhi-docs/                       │
└──────────────────────────────────────────────────────────────────────┘
```

## Maintenance banner

Cluster maintenance is scheduled for the **last Thursday of every month**. The banner appears automatically:

| Timeframe | Color | Example text |
|-----------|-------|-------------|
| 2-5 days before | **Yellow** background | "UPCOMING MAINTENANCE: Thursday, March 26, 2026" |
| 1 day before (Wednesday) | **Red** background | "MAINTENANCE TOMORROW: Thursday, March 26, 2026" |
| Day of maintenance | **Red** background | "MAINTENANCE TODAY: Thursday, March 26, 2026" |
| More than 5 days out | No banner | — |

No configuration is needed — the script calculates the next last-Thursday automatically.

## Admin messages

Admins can post announcements that appear in the splash screen.

### Using the drop-in directory (recommended)

Create files in `/etc/bodhi/motd.d/`:

```bash
# Create the directory (first time only)
sudo mkdir -p /etc/bodhi/motd.d

# Add a message
sudo tee /etc/bodhi/motd.d/01-gpu-partition.txt << 'EOF'
New GPU partition available
The 'a100' partition is now available for jobs.
Request access via ServiceNow.
EOF

# Remove a message when no longer relevant
sudo rm /etc/bodhi/motd.d/01-gpu-partition.txt
```

- Files are displayed in alphabetical order — use numeric prefixes (`01-`, `02-`) to control ordering
- The first line of each file is shown as a heading; subsequent lines are indented
- Files starting with `.`, ending with `.bak` or `~`, and empty files are skipped
- Output is capped at 20 lines per file and 50 lines total

### Using a single file (alternative)

If the directory doesn't exist, the script falls back to `/etc/bodhi/motd`:

```bash
sudo tee /etc/bodhi/motd << 'EOF'
Storage maintenance completed
All /beevol mounts have been migrated to the new storage array.
EOF
```

## Suppressing the splash

Users can suppress the splash in three ways:

| Method | Scope |
|--------|-------|
| `export BODHI_NOSPLASH=1` in `~/.bashrc` | Per-user, permanent |
| `BODHI_NOSPLASH=1 ssh bodhi` | Single session |
| `touch ~/.hushlogin` | Per-user, standard Unix convention |

The splash also skips non-interactive shells automatically (e.g., `ssh bodhi command`).

## Installation

### System-wide (recommended)

```bash
sudo cp scripts/bodhi-splash /etc/profile.d/bodhi-splash.sh
sudo chmod +x /etc/profile.d/bodhi-splash.sh
sudo mkdir -p /etc/bodhi/motd.d
```

### Per-user

```bash
make install  # installs to ~/.local/bin
echo 'source ~/.local/bin/bodhi-splash' >> ~/.bashrc
```

## Configuration

All settings are controlled via environment variables with sensible defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `BODHI_NOSPLASH` | *(unset)* | Set to any value to suppress the splash |
| `BODHI_SPLASH_THEME` | *(auto-detect)* | Force `light` or `dark` color scheme (auto-detects via `COLORFGBG`) |
| `BODHI_MOTD_DIR` | `/etc/bodhi/motd.d` | Directory for admin message files |
| `BODHI_MOTD_FILE` | `/etc/bodhi/motd` | Single admin message file (fallback) |
| `BODHI_SPLASH_HOSTS` | *(unset — show everywhere)* | Hostname glob to restrict to login nodes |
| `BODHI_HELP_CONTACT` | `David Farrell` | Help contact name |
| `BODHI_HELP_EMAIL` | *(unset)* | Help contact email |
| `BODHI_DOCS_URL` | `https://rnabioco.github.io/bodhi-docs/` | Documentation URL |

To restrict the splash to login nodes only:

```bash
# In /etc/profile.d/bodhi-splash.sh or before sourcing:
export BODHI_SPLASH_HOSTS="amc-bodhi"
```

## Testing

Use `_BODHI_DEBUG_DATE` to simulate different dates:

```bash
# Test yellow banner (3 days before March 26 maintenance)
_BODHI_DEBUG_DATE=$(date -d "2026-03-23" +%s) ./scripts/bodhi-splash

# Test red banner (1 day before)
_BODHI_DEBUG_DATE=$(date -d "2026-03-25" +%s) ./scripts/bodhi-splash

# Test red banner (day of)
_BODHI_DEBUG_DATE=$(date -d "2026-03-26" +%s) ./scripts/bodhi-splash

# Test no banner (10 days out)
_BODHI_DEBUG_DATE=$(date -d "2026-03-16" +%s) ./scripts/bodhi-splash

# Test with admin messages
mkdir -p /tmp/test-motd.d
echo -e "Test announcement\nThis is a test message." > /tmp/test-motd.d/01-test.txt
BODHI_MOTD_DIR=/tmp/test-motd.d ./scripts/bodhi-splash
```
