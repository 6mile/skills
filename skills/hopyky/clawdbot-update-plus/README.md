
# 🔄 Clawdbot Update Plus

A comprehensive backup, update, and restore tool for Clawdbot and all installed skills. Features automatic rollback on failure, encrypted backups, and cloud storage sync.

## Quick Start

```bash
# List available backups
clawdbot update-plus list-backups

# Create a backup
clawdbot update-plus backup

# Update everything (creates backup first)
clawdbot update-plus update

# Preview what would be updated (no changes made)
clawdbot update-plus update --dry-run

# Restore from a backup
clawdbot update-plus restore clawdbot-update-2026-01-25-12:00:00.tar.gz
```

## Features

| Feature | Description |
|---------|-------------|
| **Auto Backup** | Creates timestamped backups before every update |
| **Auto Rollback** | Reverts to previous commit if `git pull` fails |
| **Conflict Detection** | Skips skills with uncommitted local changes |
| **Encrypted Backups** | Optional GPG encryption for sensitive data |
| **Cloud Sync** | Upload backups to Google Drive, S3, Dropbox via rclone |
| **Retention Policy** | Automatically deletes old backups (local + remote) |
| **JSON Reports** | Generate detailed update reports for automation |
| **Dry Run Mode** | Preview changes without modifying anything |
| **Notifications** | Get notified on success/error via WhatsApp, Telegram, or Discord |
| **Full Backup** | Backup entire Clawdbot environment (config, workspace, skills) |
| **Multi-Directory** | Separate prod/dev skills with independent update settings |

## Installation

```bash
# Via ClawdHub (recommended)
clawdhub install clawdbot-update-plus

# Or clone manually
git clone https://github.com/YOUR_USER/clawdbot-update-plus.git ~/.clawdbot/skills/clawdbot-update-plus
```

### Dependencies

| Dependency | Required | Purpose |
|------------|----------|---------|
| `git` | Yes | Update skills from repositories |
| `jq` | Yes | Parse JSON configuration |
| `rclone` | No | Cloud storage sync |
| `gpg` | No | Backup encryption |

## Configuration

Create `~/.clawdbot/clawdbot-update.json`:

```json
{
  "workspace": "/home/user/clawd",
  "skills_dir": "/home/user/.clawdbot/skills",
  "backup_dir": "/home/user/.clawdbot/backups",
  "backup_before_update": true,
  "backup_count": 5,
  "excluded_skills": ["my-dev-skill"],
  "remote_storage": {
    "enabled": false,
    "rclone_remote": "gdrive:",
    "path": "clawdbot-backups"
  },
  "encryption": {
    "enabled": false,
    "gpg_recipient": "your-email@example.com"
  },
  "notifications": {
    "enabled": false,
    "target": "+1234567890",
    "on_success": true,
    "on_error": true
  }
}
```

> **Tip:** Copy the example config to get started:
> ```bash
> cp ~/.clawdbot/skills/clawdbot-update-plus/clawdbot-update.example.json ~/.clawdbot/clawdbot-update.json
> ```

### Configuration Reference

| Option | Default | Description |
|--------|---------|-------------|
| `workspace` | `$HOME/clawd` | Your Clawdbot workspace directory |
| `skills_dir` | `$HOME/.clawdbot/skills` | Where skills are installed |
| `backup_dir` | `$HOME/.clawdbot/backups` | Where backups are stored |
| `backup_before_update` | `true` | Create backup before each update |
| `backup_count` | `5` | Number of backups to retain (local + remote) |
| `excluded_skills` | `[]` | Skills to skip during updates |

## Full Environment Backup

Backup your entire Clawdbot environment with `backup_paths`. Separate from skills update logic for clean architecture.

### Configuration

```json
{
  "backup_paths": [
    {"path": "~/.clawdbot", "label": "config", "exclude": ["backups", "logs", "media", "*.lock"]},
    {"path": "~/clawd", "label": "workspace", "exclude": ["node_modules", ".venv"]}
  ],
  "skills_dirs": [
    {"path": "~/.clawdbot/skills", "label": "prod", "update": true},
    {"path": "~/clawd/skills", "label": "dev", "update": false}
  ]
}
```

### backup_paths Options

| Option | Description |
|--------|-------------|
| `path` | Directory to backup (supports `~` and `${HOME}`) |
| `label` | Name shown in logs and backup structure |
| `exclude` | Files/folders to exclude from backup |

### skills_dirs Options

| Option | Description |
|--------|-------------|
| `path` | Skills directory path |
| `label` | Name shown in logs |
| `update` | Run `git pull` on skills (`true`/`false`) |

### Recommended Setup

| What | backup_paths | skills_dirs |
|------|--------------|-------------|
| `~/.clawdbot` (config, credentials, tools) | ✅ Backup | - |
| `~/clawd` (workspace, MEMORY.md, etc.) | ✅ Backup | - |
| `~/.clawdbot/skills` (prod) | (included in config) | ✅ Update |
| `~/clawd/skills` (dev) | (included in workspace) | ❌ No update |

> **Note:** If `backup_paths` is not set, falls back to legacy `skills_dirs` backup behavior.

## Commands

### `backup` — Create a Backup

```bash
# Simple backup
clawdbot update-plus backup

# Output:
# ℹ Creating backup archive...
# ✓ Backup created: ~/.clawdbot/backups/clawdbot-update-2026-01-25-15:00:00.tar.gz (240M)
```

### `list-backups` — List Available Backups

```bash
clawdbot update-plus list-backups

# Output:
# ℹ Available backups:
#   • clawdbot-update-2026-01-25-15:00:00.tar.gz (240M)
#   • clawdbot-update-2026-01-24-15:00:00.tar.gz.gpg (235M) 🔒
#   • clawdbot-update-2026-01-23-15:00:00.tar.gz (238M)
```

### `update` — Update Clawdbot and Skills

```bash
# Standard update (with automatic backup)
clawdbot update-plus update

# Skip backup
clawdbot update-plus update --no-backup

# Preview changes only
clawdbot update-plus update --dry-run

# Generate JSON report
clawdbot update-plus update --json-report

# Force update even if backup fails
clawdbot update-plus update --force
```

**What happens during update:**
1. Creates a backup (unless `--no-backup`)
2. Updates Clawdbot binary via `clawdbot update`
3. Updates each skill via `git pull`
4. Rolls back any skill that fails to update
5. Cleans old backups beyond retention limit

### `restore` — Restore from Backup

```bash
# Interactive restore (asks for confirmation)
clawdbot update-plus restore clawdbot-update-2026-01-25-15:00:00.tar.gz

# Force restore (no confirmation)
clawdbot update-plus restore clawdbot-update-2026-01-25-15:00:00.tar.gz --force

# Restore encrypted backup (will prompt for GPG passphrase)
clawdbot update-plus restore clawdbot-update-2026-01-25-15:00:00.tar.gz.gpg
```

### `diff-backups` — Compare Two Backups

```bash
clawdbot update-plus diff-backups backup1.tar.gz backup2.tar.gz
```

### `check` — Check for Available Updates

Check if updates are available without applying them.

```bash
clawdbot update-plus check

# Output:
#   Clawdbot
#     Installed: 2026.1.22
#     Latest:    2026.1.24
#     → Update available
#
#   Skills
#     ↓ my-skill (3 commits behind)
#     ✓ All 5 skills up to date
#
# ℹ Run 'clawdbot update-plus update' to apply updates
```

## Command Line Options

| Option | Description |
|--------|-------------|
| `--dry-run` | Preview changes without modifying anything |
| `--no-backup` | Skip backup before update |
| `--no-check-disk` | Skip disk space verification |
| `--force` | Continue even if backup fails |
| `--notify` | Send notification after update |
| `--json-report` | Generate JSON report in backup directory |
| `--show-diffs` | Show file changes for each updated skill |

## Cloud Storage Setup (rclone)

### Step 1: Install rclone

```bash
# macOS
brew install rclone

# Linux
curl https://rclone.org/install.sh | sudo bash
```

### Step 2: Configure a Remote

```bash
rclone config

# Follow the interactive setup for your provider:
# - Google Drive: choose "drive"
# - Dropbox: choose "dropbox"
# - AWS S3: choose "s3"
```

### Step 3: Enable in Config

```json
{
  "remote_storage": {
    "enabled": true,
    "rclone_remote": "gdrive:",
    "path": "Backups/clawdbot"
  }
}
```

### Step 4: Test

```bash
# Create a backup and verify upload
clawdbot update-plus backup

# Check remote
rclone ls gdrive:Backups/clawdbot
```

## Encrypted Backups (GPG)

### Step 1: Generate a GPG Key (if needed)

```bash
gpg --full-generate-key
# Choose: RSA and RSA, 4096 bits, no expiration
# Enter your name and email
```

### Step 2: Enable in Config

```json
{
  "encryption": {
    "enabled": true,
    "gpg_recipient": "your-email@example.com"
  }
}
```

### Step 3: Create Encrypted Backup

```bash
clawdbot update-plus backup

# Output:
# ℹ Creating backup archive...
# ℹ Encrypting backup...
# ✓ Backup created: ~/.clawdbot/backups/clawdbot-update-2026-01-25-15:00:00.tar.gz.gpg (235M)
```

Encrypted backups show a 🔒 icon in `list-backups`.

## Notifications

Get notified when updates complete or fail. Notifications are sent via Clawdbot's messaging system, supporting WhatsApp, Telegram, and Discord.

### Enable Notifications

```json
{
  "notifications": {
    "enabled": true,
    "target": "+1234567890",
    "on_success": true,
    "on_error": true
  }
}
```

### Target Format

The target format determines which channel Clawdbot uses:

| Format | Channel |
|--------|---------|
| `+1234567890` | WhatsApp |
| `@username` | Telegram |
| `channel:123456` | Discord |

### Notification Options

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `false` | Enable/disable notifications |
| `target` | `""` | Recipient (phone, username, or channel ID) |
| `on_success` | `true` | Notify when update succeeds |
| `on_error` | `true` | Notify when update fails |

### Force Notification

Use `--notify` flag to send a notification even if disabled in config:

```bash
clawdbot update-plus update --notify
```

> **Tip:** Enable notifications with `on_error: true` for cron jobs to get alerted when automatic updates fail.

## Automatic Updates (Cron)

### Install Cron Job

```bash
# Install with default schedule (daily at 2 AM)
clawdbot update-plus install-cron

# Or specify a custom schedule
clawdbot update-plus install-cron "0 3 * * 0"  # Every Sunday at 3 AM

# Output:
# ℹ Installing cron job...
#   Schedule: 0 2 * * *
#   Command:  ~/.clawdbot/skills/clawdbot-update-plus/bin/update.sh update
#   Log file: ~/.clawdbot/backups/cron-update.log
# ✓ Cron job installed!
```

### Remove Cron Job

```bash
clawdbot update-plus uninstall-cron
```

### Manual Setup (Alternative)

```bash
crontab -e

# Add this line (runs daily at 2 AM):
0 2 * * * ~/.clawdbot/skills/clawdbot-update-plus/bin/update.sh update >> ~/.clawdbot/backups/cron-update.log 2>&1
```

## Excluding Skills

Exclude skills from automatic updates when:
- You have local modifications you want to keep
- The skill is in active development
- You want to pin a specific version

```json
{
  "excluded_skills": ["my-custom-skill", "dev-skill"]
}
```

**Behavior:**
- Excluded skills are completely skipped during `update`
- They still get included in backups
- Use `git pull` manually to update them

## Safety Features

| Feature | How It Works |
|---------|--------------|
| **Pre-update Backup** | Always creates backup before updating (configurable) |
| **Conflict Detection** | Skips skills with uncommitted changes to avoid merge conflicts |
| **Auto Rollback** | If `git pull` fails, automatically runs `git reset --hard` to previous commit |
| **Disk Space Check** | Verifies 500MB available before creating backup |
| **Retention Cleanup** | Deletes old backups beyond `backup_count` (local + remote) |

## Backup Contents

Each backup includes:
- All installed skills (`~/.clawdbot/skills/*`)
- Clawdbot configuration (`~/.clawdbot/clawdbot.json`)

**Excluded from backups:**
- `.venv/` directories
- `node_modules/` directories
- `*.pyc` files and `__pycache__/`

## JSON Reports

When using `--json-report`, a report is saved to the backup directory:

```bash
clawdbot update-plus update --json-report
cat ~/.clawdbot/backups/report-2026-01-25-15:00:00.json
```

```json
{
  "run_timestamp": "2026-01-25T15:00:00Z",
  "status": "success",
  "backup": {
    "status": "created",
    "filename": "clawdbot-update-2026-01-25-15:00:00.tar.gz",
    "size": "240M"
  },
  "clawdbot_update": {
    "status": "updated",
    "from_version": "2026.1.22",
    "to_version": "2026.1.23"
  },
  "skills_updated": [
    {"name": "skill-a", "status": "updated", "from_commit": "abc123", "to_commit": "def456"},
    {"name": "skill-b", "status": "no_change"}
  ],
  "skills_failed": [
    {"name": "skill-c", "status": "failed", "error": "local changes detected"}
  ]
}
```

## Troubleshooting

### "No backups found" but exit code is 0

This was fixed in v1.3.0. Update the skill:
```bash
cd ~/.clawdbot/skills/clawdbot-update-plus && git pull
```

### GPG decryption fails with "Inappropriate ioctl for device"

This happens when GPG can't prompt for a passphrase (e.g., in cron jobs). Solutions:
```bash
# Option 1: Use gpg-agent
echo "use-agent" >> ~/.gnupg/gpg.conf

# Option 2: Set GPG_TTY
export GPG_TTY=$(tty)
```

### Backup fails with "tar creation failed"

Check that your `skills_dir` path is correct in the config:
```bash
ls -la ~/.clawdbot/skills/
```

### rclone upload fails

Verify your remote is configured correctly:
```bash
rclone lsd your-remote:
```

## Changelog

### v1.6.0
- Added `backup_paths` for full environment backup
- Backup config, workspace, and all files (not just skills)
- Separated backup logic from update logic
- Custom exclude patterns per backup path
- Complete disaster recovery support

### v1.5.0
- Added multi-directory support (`skills_dirs` config)
- Separate backup/update settings per directory
- Perfect for prod/dev separation
- Backups now organized by label (prod/, dev/)

### v1.4.0
- Added notifications via Clawdbot messaging (WhatsApp, Telegram, Discord)
- Notifications on both success and error
- Configurable notification preferences in JSON config
- `--notify` flag to force notifications

### v1.3.0
- Added `check` command to see available updates
- Added `diff-backups` command to compare backups
- Added `install-cron` / `uninstall-cron` commands
- Added `-h`/`--help` option
- Fixed exit code propagation for all commands
- Fixed argument parsing (`restore`, `--force`, etc.)
- Fixed backup/restore paths to use `skills_dir` config
- Fixed git rollback syntax
- Added `skills_dir` configuration option
- `check` now respects `excluded_skills` config
- Improved error handling and robustness

### v1.2.0
- Added `--dry-run` mode
- Added `--notify` option
- Added `--json-report` option
- Added disk space check before backup
- Added structured logging to file

### v1.1.0
- Added ClawdHub integration
- Added pnpm/npm/yarn/bun support
- Added fallback to `git pull` if claudhub unavailable

### v1.0.0
- Initial release
- Basic backup, update, restore functionality

## Author

Created by **hopyky**

## License

MIT
