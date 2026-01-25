#!/usr/bin/env bash
set -euo pipefail

# Clawdbot Update Plus - Backup, Update, Restore
# Author: hopyky
# Version: 1.6.0
# License: MIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DEFAULT="${HOME}/clawd"
BACKUP_DIR_DEFAULT="${HOME}/.clawdbot/backups"
CONFIG_FILE="${HOME}/.clawdbot/clawdbot-update.json"
LOG_FILE="${HOME}/.clawdbot/backups/update.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1" >&2
  log_to_file "ERROR: $1"
}

log_to_file() {
  local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  echo "[$timestamp] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log_dry_run() {
  if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}[DRY-RUN]${NC} $1"
  fi
}

# Global variables
OS="$(uname)"
DRY_RUN=false
FORCE_UPDATE=false
CHECK_DISK=true
NOTIFICATION_ENABLED=false
LOG_FORMAT="text"
JSON_REPORT=false
SHOW_DIFFS=false

# Load configuration (parse JSON)
load_config() {
  # Default values FIRST
  WORKSPACE="${WORKSPACE:-$WORKSPACE_DEFAULT}"
  SKILLS_DIR="${HOME}/.clawdbot/skills"
  SKILLS_DIRS_JSON=""
  BACKUP_PATHS_JSON=""
  BACKUP_DIR="${BACKUP_DIR:-$BACKUP_DIR_DEFAULT}"
  AUTO_UPDATE="false"
  BACKUP_BEFORE_UPDATE="true"
  BACKUP_COUNT="5"
  EXCLUDED_SKILLS=""
  REMOTE_STORAGE_ENABLED="false"
  RCLONE_REMOTE=""
  REMOTE_STORAGE_PATH=""
  ENCRYPTION_ENABLED="false"
  GPG_RECIPIENT=""
  NOTIFY_ENABLED="false"
  NOTIFY_TARGET=""
  NOTIFY_ON_SUCCESS="true"
  NOTIFY_ON_ERROR="true"

  # Then try to load from JSON config
  if [[ -f "$CONFIG_FILE" ]]; then
    WORKSPACE=$(jq -r '.workspace // "'"$WORKSPACE_DEFAULT"'"' "$CONFIG_FILE")
    BACKUP_DIR=$(jq -r '.backup_dir // "'"$BACKUP_DIR_DEFAULT"'"' "$CONFIG_FILE")
    AUTO_UPDATE=$(jq -r '.auto_update // "false"' "$CONFIG_FILE")
    BACKUP_BEFORE_UPDATE=$(jq -r '.backup_before_update // "true"' "$CONFIG_FILE")
    BACKUP_COUNT=$(jq -r '.backup_count // 5' "$CONFIG_FILE")
    EXCLUDED_SKILLS=$(jq -r '.excluded_skills | @json' "$CONFIG_FILE")
    REMOTE_STORAGE_ENABLED=$(jq -r '.remote_storage.enabled // "false"' "$CONFIG_FILE")
    RCLONE_REMOTE=$(jq -r '.remote_storage.rclone_remote // ""' "$CONFIG_FILE")
    REMOTE_STORAGE_PATH=$(jq -r '.remote_storage.path // ""' "$CONFIG_FILE")
    ENCRYPTION_ENABLED=$(jq -r '.encryption.enabled // "false"' "$CONFIG_FILE")
    GPG_RECIPIENT=$(jq -r '.encryption.gpg_recipient // ""' "$CONFIG_FILE")
    NOTIFY_ENABLED=$(jq -r '.notifications.enabled // "false"' "$CONFIG_FILE")
    NOTIFY_TARGET=$(jq -r '.notifications.target // ""' "$CONFIG_FILE")
    NOTIFY_ON_SUCCESS=$(jq -r '.notifications.on_success // "true"' "$CONFIG_FILE")
    NOTIFY_ON_ERROR=$(jq -r '.notifications.on_error // "true"' "$CONFIG_FILE")

    # Load backup_paths (new full backup system)
    if jq -e '.backup_paths' "$CONFIG_FILE" >/dev/null 2>&1; then
      BACKUP_PATHS_JSON=$(jq -c '.backup_paths' "$CONFIG_FILE")
    else
      # Legacy: no backup_paths, will use skills_dirs for backup
      BACKUP_PATHS_JSON=""
    fi

    # Load skills_dirs (for updates only now)
    if jq -e '.skills_dirs' "$CONFIG_FILE" >/dev/null 2>&1; then
      SKILLS_DIRS_JSON=$(jq -c '.skills_dirs' "$CONFIG_FILE")
    else
      # Legacy format: single skills_dir
      SKILLS_DIR=$(jq -r '.skills_dir // "'"${HOME}/.clawdbot/skills"'"' "$CONFIG_FILE")
      SKILLS_DIRS_JSON=$(jq -n --arg path "$SKILLS_DIR" '[{path: $path, label: "default", update: true}]')
    fi
  else
    # No config file, use defaults
    SKILLS_DIRS_JSON=$(jq -n --arg path "$SKILLS_DIR" '[{path: $path, label: "default", update: true}]')
    BACKUP_PATHS_JSON=""
  fi

  # Ensure directories exist
  mkdir -p "$WORKSPACE"
  mkdir -p "$BACKUP_DIR"
}

validate_config() {
    log_info "Validating configuration..."

    if [[ -f "$CONFIG_FILE" ]]; then
        if ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
            log_error "Configuration file $CONFIG_FILE is not a valid JSON."
            return 1
        fi
    fi

    if [[ ! -d "$WORKSPACE" ]]; then
        log_error "Workspace directory $WORKSPACE does not exist."
        return 1
    fi

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory $BACKUP_DIR does not exist."
        return 1
    fi

    log_success "Configuration is valid."
    return 0
}

check_connection() {
    log_info "Checking internet connection..."
    if ! ping -c 1 github.com &> /dev/null; then
        log_error "No internet connection detected."
        return 1
    fi
    log_success "Internet connection is available."
    return 0
}

# Check if skill is excluded
is_excluded() {
  local skill_name="$1"

  # Parse EXCLUDED_SKILLS into array safely
  if [[ -n "$EXCLUDED_SKILLS" ]] && [[ "$EXCLUDED_SKILLS" != "()" ]]; then
    # Remove leading/trailing characters
    local excluded_list_str="${EXCLUDED_SKILLS#[\([]}"
    excluded_list_str="${excluded_list_str%[\])]}"

    # Convert to array
    IFS=',' read -ra excluded_list <<< "$excluded_list_str"

    for excluded in "${excluded_list[@]}"; do
      # Remove quotes and spaces
      excluded="${excluded//\'}"
      excluded="${excluded//\"/}"
      excluded="${excluded// /}"

      if [[ -n "$excluded" ]] && [[ "$skill_name" == "$excluded" ]]; then
        return 0
      fi
    done
  fi

  return 1
}

# Detect workspace automatically
detect_workspace() {
  log_info "Detecting workspace..."

  # Check common workspace locations
  local possible_workspaces=(
    "${HOME}/clawd"
    "${HOME}/Documents/clawd"
    "${HOME}/workspace/clawd"
    "$(pwd)"
  )

  for ws in "${possible_workspaces[@]}"; do
    if [[ -d "$ws" ]] && [[ -f "$ws/CLAWDBOT.md" ]] || [[ -f "$ws/AGENTS.md" ]]; then
      WORKSPACE="$ws"
      log_success "Workspace found: $WORKSPACE"
      return
    fi
  done

  log_warning "Could not detect workspace automatically, using: $WORKSPACE_DEFAULT"
  WORKSPACE="$WORKSPACE_DEFAULT"
}

# Check available disk space
check_disk_space() {
  if [[ "$CHECK_DISK" != true ]]; then
    return 0
  fi

  local required_mb=500  # 500MB minimum required
  local available_mb

  if [[ "$OS" == "Darwin" ]]; then
    available_mb=$(df -m "${BACKUP_DIR}" 2>/dev/null | awk 'NR==2 {print $4}')
  else
    available_mb=$(df -BM --output=avail "${BACKUP_DIR}" 2>/dev/null | tail -n 1 | sed 's/M//')
  fi
  
  available_mb=${available_mb:-0}

  if [[ $available_mb -lt $required_mb ]]; then
    log_error "Insufficient disk space: ${available_mb}MB available, ${required_mb}MB required"
    return 1
  fi

  log_info "Disk space check: ${available_mb}MB available (OK)"
  return 0
}

# Create timestamped backup
create_backup() {
  local backup_name="clawdbot-update-$(date +%Y-%m-%d-%H:%M:%S).tar.gz"
  local backup_path="${BACKUP_DIR}/${backup_name}"
  local tmp_backup_dir=$(mktemp -d)
  local dirs_backed_up=0

  # Determine what to backup: backup_paths (new) or skills_dirs (legacy)
  local backup_source_json=""
  if [[ -n "$BACKUP_PATHS_JSON" ]] && [[ "$BACKUP_PATHS_JSON" != "null" ]]; then
    backup_source_json="$BACKUP_PATHS_JSON"
  else
    # Legacy fallback: use skills_dirs with backup=true
    backup_source_json=$(echo "$SKILLS_DIRS_JSON" | jq -c '[.[] | select(.backup == true) | {path: .path, label: .label, exclude: [".venv", "node_modules", "*.pyc", "__pycache__"]}]')
  fi

  if [[ "$DRY_RUN" == true ]]; then
    if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
      backup_name+=".gpg"
    fi
    log_dry_run "Would create backup: ${BACKUP_DIR}/${backup_name}"
    # Show which dirs would be backed up
    echo "$backup_source_json" | jq -r '.[] | "  → \(.label): \(.path)"' | while read -r line; do
      log_dry_run "$line"
    done
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "skipped", filename: $filename}' --arg filename "$backup_name")
    echo "$backup_name"
    return 0
  fi

  log_info "Creating backup archive..."

  # Iterate over backup paths
  while IFS= read -r dir_config; do
    local dir_path=$(echo "$dir_config" | jq -r '.path' | sed "s|\${HOME}|$HOME|g" | sed "s|~|$HOME|g")
    local dir_label=$(echo "$dir_config" | jq -r '.label')
    local dir_excludes=$(echo "$dir_config" | jq -r '.exclude // [] | .[]' 2>/dev/null)

    if [[ ! -d "$dir_path" ]]; then
      log_warning "Directory not found: $dir_path ($dir_label), skipping"
      continue
    fi

    log_info "Backing up $dir_label: $dir_path"

    # Create subdirectory in temp for this label
    mkdir -p "$tmp_backup_dir/$dir_label"

    # Build rsync exclude arguments
    local rsync_excludes=""
    while IFS= read -r exclude; do
      if [[ -n "$exclude" ]]; then
        rsync_excludes+="--exclude=$exclude "
      fi
    done <<< "$dir_excludes"

    # Default excludes if none specified
    if [[ -z "$rsync_excludes" ]]; then
      rsync_excludes="--exclude=.venv --exclude=node_modules --exclude=*.pyc --exclude=__pycache__"
    fi

    # Copy to temp dir
    eval rsync -a $rsync_excludes "$dir_path/" "$tmp_backup_dir/$dir_label/" 2>/dev/null || {
      log_warning "Failed to backup $dir_label, continuing..."
      continue
    }

    dirs_backed_up=$((dirs_backed_up + 1))
  done < <(echo "$backup_source_json" | jq -c '.[]')

  if [[ $dirs_backed_up -eq 0 ]]; then
    log_error "No directories were backed up"
    rm -rf "$tmp_backup_dir"
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "failed", error: "no directories backed up"}')
    return 1
  fi

  # Create tar archive
  tar -czf "$backup_path" -C "$tmp_backup_dir" . 2>/dev/null || {
    log_error "Failed to create backup archive"
    rm -rf "$tmp_backup_dir"
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "failed", error: "tar creation failed"}')
    return 1
  }

  # Cleanup temp dir
  rm -rf "$tmp_backup_dir"

  if [[ "$ENCRYPTION_ENABLED" == "true" ]]; then
    if ! command -v gpg &>/dev/null; then
        log_error "gpg command not found, cannot encrypt."
        REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "failed", error: "gpg not found"}')
        rm -f "$backup_path"
        return 1
    fi
    if [[ -z "$GPG_RECIPIENT" ]]; then
      log_error "Encryption enabled, but no GPG recipient set."
      REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "failed", error: "GPG recipient not set"}')
      rm -f "$backup_path"
      return 1
    fi
    log_info "Encrypting backup..."
    if ! gpg --encrypt --recipient "$GPG_RECIPIENT" --output "${backup_path}.gpg" "$backup_path"; then
      log_error "Failed to encrypt backup."
      REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "failed", error: "GPG encryption failed"}')
      rm -f "$backup_path"
      return 1
    fi
    rm -f "$backup_path"
    backup_name+=".gpg"
    backup_path+=".gpg"
  fi

  local backup_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
  log_success "Backup created: $backup_path ($backup_size)"
  REPORT_JSON=$(echo "$REPORT_JSON" | jq '.backup = {status: "created", filename: $filename, size: $size}' --arg filename "$backup_name" --arg size "$backup_size")

  upload_to_remote "$backup_path"
  clean_old_backups
  
  echo "$backup_name"
}

upload_to_remote() {
    local file_path="$1"

    if [[ "$REMOTE_STORAGE_ENABLED" != "true" ]]; then
        return 0
    fi

    if ! command -v rclone &> /dev/null; then
        log_error "rclone command not found, cannot upload to remote storage."
        return 1
    fi

    log_info "Uploading backup to remote storage..."
    if ! rclone copy "$file_path" "${RCLONE_REMOTE}/${REMOTE_STORAGE_PATH}"; then
        log_error "Failed to upload backup to remote storage."
        return 1
    fi

    log_success "Backup successfully uploaded to remote storage."
}

# Clean old backups
clean_old_backups() {
  log_info "Cleaning old local backups..."
  ls -1t "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null | tail -n +$((BACKUP_COUNT + 1)) | while read -r old_backup; do
    rm -f "$old_backup"
    log_info "Deleted local backup: $(basename "$old_backup")"
  done

  if [[ "$REMOTE_STORAGE_ENABLED" == "true" ]] && command -v rclone &>/dev/null; then
    log_info "Cleaning old remote backups..."
    rclone lsf "${RCLONE_REMOTE}/${REMOTE_STORAGE_PATH}" | sort -r | tail -n +$((BACKUP_COUNT + 1)) | while read -r old_backup; do
      if [[ -n "$old_backup" ]]; then
        rclone deletefile "${RCLONE_REMOTE}/${REMOTE_STORAGE_PATH}/${old_backup}"
        log_info "Deleted remote backup: $old_backup"
      fi
    done
  fi
}

# Update Clawdbot binary
update_clawdbot() {
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would update Clawdbot (dry-run mode)"
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.clawdbot_update = {status: "skipped"}')
    return 0
  fi

  log_info "Updating Clawdbot..."

  if ! command -v clawdbot &>/dev/null; then
    log_error "clawdbot command not found"
    log_to_file "ERROR: clawdbot command not found"
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.clawdbot_update = {status: "not_found"}')
    return 1
  fi
  
  local current_version
  current_version=$(clawdbot --version 2>&1 | head -1 || echo "unknown")
  log_info "Current version: $current_version"
  log_to_file "Clawdbot current version: $current_version"

  # ... (rest of the detection logic remains the same for now)
  local install_type="git" # Simplified for now

  if ! (case "$install_type" in
    git)
      log_info "Updating via clawdbot update..."
      clawdbot update
      ;;
    *)
      log_error "Unknown installation type, cannot update"
      return 1
      ;;
  esac); then
    log_error "Clawdbot update failed"
    log_to_file "ERROR: Clawdbot update failed"
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.clawdbot_update = {status: "failed", from_version: $from}' --arg from "$current_version")
    return 1
  fi

  local new_version
  new_version=$(clawdbot --version 2>&1 | head -1 || echo "unknown")
  if [[ "$current_version" != "$new_version" ]]; then
    log_success "Clawdbot updated successfully to $new_version"
    log_to_file "Clawdbot updated: $current_version -> $new_version"
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.clawdbot_update = {status: "updated", from_version: $from, to_version: $to}' --arg from "$current_version" --arg to "$new_version")
  else
    log_info "Clawdbot is already up to date."
    REPORT_JSON=$(echo "$REPORT_JSON" | jq '.clawdbot_update = {status: "no_change", from_version: $from}' --arg from "$current_version")
  fi
}

# Update all skills
update_skills() {
  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would update skills (dry-run mode)"
    # Show what would be updated
    log_info "Checking for skill updates..."

    if command -v claudhub &>/dev/null; then
      log_info "Installed skills (via claudhub):"
      claudhub list 2>/dev/null || true
    fi
    update_git_skills
    return 0
  fi

  log_info "Updating all skills..."
  log_to_file "Starting skills update"

  # If claudhub is available, use it
  if command -v claudhub &>/dev/null; then
    log_info "Updating skills via claudhub..."
    if ! claudhub update --all; then
        log_warning "claudhub update --all failed. Will try to update git skills individually."
    fi
  else
    log_info "claudhub not found, updating git skills individually."
  fi
  
  # Always run git skill update
  update_git_skills
}

# Update skills via git pull
update_git_skills() {
  # Iterate over skills_dirs with update=true
  while IFS= read -r dir_config; do
    local dir_path=$(echo "$dir_config" | jq -r '.path' | sed "s|\${HOME}|$HOME|g" | sed "s|~|$HOME|g")
    local dir_label=$(echo "$dir_config" | jq -r '.label')
    local dir_update=$(echo "$dir_config" | jq -r '.update')

    if [[ "$dir_update" != "true" ]]; then
      log_info "Skipping $dir_label (update disabled)"
      continue
    fi

    if [[ ! -d "$dir_path" ]]; then
      log_warning "Skills directory not found: $dir_path ($dir_label), skipping"
      continue
    fi

    log_info "Checking Git-based skills in: $dir_path ($dir_label)"

    for skill_dir in "$dir_path"/*/; do
      if [[ -d "$skill_dir/.git" ]]; then
        local skill_name
        skill_name=$(basename "$skill_dir")

        cd "$skill_dir"

        if is_excluded "$skill_name"; then
          log_info "Skipping excluded skill: $skill_name"
          REPORT_JSON=$(echo "$REPORT_JSON" | jq '.skills_updated += [{name: $name, status: "skipped", source: $source}]' --arg name "$skill_name" --arg source "$dir_label")
          continue
        fi

        if [[ -n "$(git status --porcelain)" ]]; then
          log_warning "$skill_name has local changes, skipping."
          REPORT_JSON=$(echo "$REPORT_JSON" | jq '.skills_failed += [{name: $name, status: "failed", error: "local changes detected", source: $source}]' --arg name "$skill_name" --arg source "$dir_label")
          continue
        fi

        log_info "Updating: $skill_name ($dir_label)"
        local current_commit
        current_commit=$(git rev-parse --short HEAD)

        if ! git pull --quiet; then
          log_error "$skill_name update failed. Rolling back..."
          git reset --hard --quiet "$current_commit"
          REPORT_JSON=$(echo "$REPORT_JSON" | jq '.skills_failed += [{name: $name, status: "failed", error: "pull failed, rolled back", source: $source}]' --arg name "$skill_name" --arg source "$dir_label")
        else
          local new_commit
          new_commit=$(git rev-parse --short HEAD)
          if [[ "$current_commit" != "$new_commit" ]]; then
            log_success "$skill_name updated ($current_commit → $new_commit)"
            REPORT_JSON=$(echo "$REPORT_JSON" | jq '.skills_updated += [{name: $name, status: "updated", from_commit: $from, to_commit: $to, source: $source}]' --arg name "$skill_name" --arg from "$current_commit" --arg to "$new_commit" --arg source "$dir_label")
          else
            log_info "$skill_name already up to date"
            REPORT_JSON=$(echo "$REPORT_JSON" | jq '.skills_updated += [{name: $name, status: "no_change", source: $source}]' --arg name "$skill_name" --arg source "$dir_label")
          fi
        fi
      fi
    done
  done < <(echo "$SKILLS_DIRS_JSON" | jq -c '.[]')
}

# Restore from backup
restore_backup() {
  local backup_id="$1"
  local force_restore="${2:-}"

  if [[ -z "$backup_id" ]]; then
    log_error "Please specify a backup ID"
    list_backups
    return 1
  fi

  local backup_path="${BACKUP_DIR}/${backup_id}"
  local decrypted_path=""
  local should_cleanup_decrypted=false

  if [[ ! -f "$backup_path" ]]; then
    log_error "Backup not found: $backup_path"
    list_backups
    return 1
  fi

  if [[ "$force_restore" != "--force" ]]; then
    log_warning "This will restore your skills from backup: $backup_id"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      log_info "Restore cancelled"
      return 0
    fi
  fi

  log_info "Restoring from backup..."

  if [[ "${backup_path##*.}" == "gpg" ]]; then
    if ! command -v gpg &>/dev/null; then
        log_error "gpg command not found, cannot decrypt."
        return 1
    fi
    log_info "Decrypting backup..."
    decrypted_path=$(mktemp)
    if ! gpg --decrypt --output "$decrypted_path" "$backup_path"; then
      log_error "Failed to decrypt backup."
      rm -f "$decrypted_path"
      return 1
    fi
    backup_path="$decrypted_path"
    should_cleanup_decrypted=true
  fi

  if ! tar -xzf "$backup_path" -C "${SKILLS_DIR}"; then
    log_error "Failed to extract backup."
    if [[ "$should_cleanup_decrypted" == true ]]; then rm -f "$decrypted_path"; fi
    return 1
  fi

  if [[ "$should_cleanup_decrypted" == true ]]; then
    rm -f "$decrypted_path"
  fi

  log_success "Restore completed from: $backup_id"
}

# List available backups
list_backups() {
  log_info "Available backups:"

  if [[ ! -d "$BACKUP_DIR" ]]; then
    log_warning "No backups found"
    return 1
  fi

  # Count backups first (avoid subshell variable scope issue with pipe)
  local backup_count
  backup_count=$(ls -1 "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null | wc -l | tr -d ' ')

  if [[ "$backup_count" -eq 0 ]]; then
    log_info "No backups found."
    return 1
  fi

  # Use process substitution to avoid subshell
  while read -r backup_path; do
    local backup_file=$(basename "$backup_path")
    local backup_size=$(du -h "$backup_path" | cut -f1)
    local encrypted_symbol=""
    if [[ "${backup_file##*.}" == "gpg" ]]; then
      encrypted_symbol=" 🔒"
    fi
    echo "  • $backup_file ($backup_size)${encrypted_symbol}"
  done < <(ls -1t "${BACKUP_DIR}"/*.tar.gz* 2>/dev/null)

  return 0
}

# Send notification via Clawdbot
send_notification() {
  local status="$1"  # "success" or "error"
  local details="${2:-}"

  # Check if notifications are enabled
  if [[ "$NOTIFY_ENABLED" != "true" ]] && [[ "$NOTIFICATION_ENABLED" != "true" ]]; then
    return 0
  fi

  # Check notification type preference
  if [[ "$status" == "success" ]] && [[ "$NOTIFY_ON_SUCCESS" != "true" ]]; then
    return 0
  fi
  if [[ "$status" == "error" ]] && [[ "$NOTIFY_ON_ERROR" != "true" ]]; then
    return 0
  fi

  # Check if target is configured
  if [[ -z "$NOTIFY_TARGET" ]]; then
    log_warning "Notification enabled but no target configured"
    return 0
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log_dry_run "Would send notification to $NOTIFY_TARGET"
    return 0
  fi

  log_info "Sending notification..."

  # Check if clawdbot command is available
  if ! command -v clawdbot &>/dev/null; then
    log_warning "clawdbot command not found, skipping notification"
    return 0
  fi

  # Build message based on status
  local message=""
  if [[ "$status" == "success" ]]; then
    message="✅ *Clawdbot Update Complete*"
    message+="\n\n📦 Skills and Clawdbot updated successfully."
  else
    message="❌ *Clawdbot Update Failed*"
    message+="\n\n⚠️ An error occurred during the update."
  fi

  if [[ -n "$details" ]]; then
    message+="\n\n$details"
  fi

  message+="\n\n🕐 $(date '+%Y-%m-%d %H:%M:%S')"

  # Send via clawdbot message
  if clawdbot message send --target "$NOTIFY_TARGET" --message "$message" 2>/dev/null; then
    log_success "Notification sent to $NOTIFY_TARGET"
    log_to_file "Notification sent to $NOTIFY_TARGET"
  else
    log_warning "Could not send notification (check gateway status)"
    log_to_file "WARNING: Could not send notification"
  fi
}

# Show help
show_help() {
  cat <<'EOF'
Clawdbot Update Plus v1.6.0
Backup, update, and restore Clawdbot and all installed skills.

USAGE
  clawdbot update-plus <command> [options]

COMMANDS
  backup                  Create a backup of all skills
  list-backups            List available backups
  update                  Update Clawdbot and all skills (with backup)
  restore <backup_id>     Restore skills from a backup
  diff-backups <a> <b>    Compare two backups
  check                   Check for available updates
  install-cron [schedule] Install automatic update cron job (default: 2 AM daily)
  uninstall-cron          Remove the cron job

OPTIONS
  --dry-run               Preview changes without modifying anything
  --no-backup             Skip backup before update
  --no-check-disk         Skip disk space check
  --force                 Continue even if backup fails or skip confirmation
  --notify                Force send notification (overrides config)
  --json-report           Generate JSON report of the update
  --show-diffs            Show file changes for each updated skill

FULL ENVIRONMENT BACKUP
  Configure what to backup with backup_paths:
    "backup_paths": [
      {"path": "~/.clawdbot", "label": "config", "exclude": ["backups", "logs"]},
      {"path": "~/clawd", "label": "workspace", "exclude": ["node_modules"]}
    ]

SKILLS UPDATE
  Configure which skills directories to update:
    "skills_dirs": [
      {"path": "~/.clawdbot/skills", "label": "prod", "update": true},
      {"path": "~/clawd/skills", "label": "dev", "update": false}
    ]

NOTIFICATIONS
  Configure in ~/.clawdbot/clawdbot-update.json:
    "notifications": {
      "enabled": true,
      "target": "+1234567890",
      "on_success": true,
      "on_error": true
    }

  Target format determines channel (handled by Clawdbot):
    +1234567890     → WhatsApp
    @username       → Telegram
    channel:123     → Discord

EXAMPLES
  # Create a backup
  clawdbot update-plus backup

  # Preview what would be updated
  clawdbot update-plus update --dry-run

  # Update everything with JSON report
  clawdbot update-plus update --json-report

  # Restore from a specific backup
  clawdbot update-plus restore clawdbot-update-2026-01-25-12:00:00.tar.gz

  # Force restore without confirmation
  clawdbot update-plus restore backup.tar.gz --force

  # Compare two backups
  clawdbot update-plus diff-backups backup1.tar.gz backup2.tar.gz

CONFIGURATION
  Config file: ~/.clawdbot/clawdbot-update.json
  Log file:    ~/.clawdbot/backups/update.log
  Backups:     ~/.clawdbot/backups/

AUTO-UPDATE (cron)
  0 2 * * * ~/.clawdbot/skills/clawdbot-update-plus/bin/update.sh update

For full documentation, see SKILL.md or visit:
  https://github.com/hopyky/clawdbot-update-plus
EOF
}

clean_logs() {
    log_info "Cleaning up old log files..."
    find "${BACKUP_DIR}" -name "*.log" -mtime +30 -delete
    log_success "Old logs cleaned."
}

generate_json_report() {
    if [[ "$JSON_REPORT" != true ]]; then
        return 0
    fi

    log_info "Generating JSON report..."
    local report_file="${BACKUP_DIR}/report-$(date +%Y-%m-%d-%H:%M:%S).json"
    
    # Finalize status
    if [[ $(echo "$REPORT_JSON" | jq '(.clawdbot_update.status == "failed") or (.skills_failed | length > 0)') == "true" ]]; then
        REPORT_JSON=$(echo "$REPORT_JSON" | jq '.status = "failure"')
    else
        REPORT_JSON=$(echo "$REPORT_JSON" | jq '.status = "success"')
    fi

    echo "$REPORT_JSON" > "$report_file"
    log_success "JSON report generated: $report_file"
}

diff_backups() {
    local backup1="$1"
    local backup2="$2"

    if [[ -z "$backup1" ]] || [[ -z "$backup2" ]]; then
        log_error "Please provide two backup IDs to compare."
        list_backups || return 1 # Ensure list_backups error propagates
        return 1
    fi

    local backup1_path="${BACKUP_DIR}/${backup1}"
    local backup2_path="${BACKUP_DIR}/${backup2}"

    if [[ ! -f "$backup1_path" ]]; then
        log_error "Backup not found: $backup1_path"
        return 1
    fi
    if [[ ! -f "$backup2_path" ]]; then
        log_error "Backup not found: $backup2_path"
        return 1
    fi

    local tmp_dir1=$(mktemp -d)
    local tmp_dir2=$(mktemp -d)

    log_info "Decompressing backups to compare..."
    if ! tar -xzf "$backup1_path" -C "$tmp_dir1"; then
        log_error "Failed to decompress $backup1."
        rm -rf "$tmp_dir1" "$tmp_dir2"
        return 1
    fi
    if ! tar -xzf "$backup2_path" -C "$tmp_dir2"; then
        log_error "Failed to decompress $backup2."
        rm -rf "$tmp_dir1" "$tmp_dir2"
        return 1
    fi

    log_info "Comparing backups..."
    diff -r -u "$tmp_dir1" "$tmp_dir2" || true # Diff returns non-zero if differences are found, which is fine

    rm -rf "$tmp_dir1" "$tmp_dir2"
    log_info "Cleanup complete."
    return 0
}

# Check for available updates
check_updates() {
    local updates_available=0

    log_info "Checking for updates..."
    echo ""

    # Check Clawdbot version
    if command -v clawdbot &>/dev/null; then
        local current_version
        current_version=$(clawdbot --version 2>/dev/null | head -1 || echo "unknown")

        # Try to get latest version from npm
        local latest_version="unknown"
        if command -v npm &>/dev/null; then
            latest_version=$(npm view clawdbot version 2>/dev/null || echo "unknown")
        elif command -v pnpm &>/dev/null; then
            latest_version=$(pnpm view clawdbot version 2>/dev/null || echo "unknown")
        fi

        echo -e "  ${BLUE}Clawdbot${NC}"
        echo -e "    Installed: $current_version"
        if [[ "$latest_version" != "unknown" ]]; then
            echo -e "    Latest:    $latest_version"
            if [[ "$current_version" != "$latest_version" ]]; then
                echo -e "    ${YELLOW}→ Update available${NC}"
                updates_available=1
            else
                echo -e "    ${GREEN}✓ Up to date${NC}"
            fi
        else
            echo -e "    Latest:    ${YELLOW}Unable to check${NC}"
        fi
        echo ""
    fi

    # Check skills
    local skills_dir="${SKILLS_DIR:-${HOME}/.clawdbot/skills}"
    local skills_with_updates=0
    local skills_checked=0

    echo -e "  ${BLUE}Skills${NC}"

    for skill_dir in "$skills_dir"/*/; do
        if [[ -d "$skill_dir/.git" ]]; then
            local skill_name
            skill_name=$(basename "$skill_dir")

            # Skip excluded skills
            if is_excluded "$skill_name"; then
                echo -e "    ${BLUE}○${NC} $skill_name (excluded)"
                continue
            fi

            skills_checked=$((skills_checked + 1))

            cd "$skill_dir"

            # Fetch without merging to check for updates
            git fetch --quiet 2>/dev/null || continue

            local local_commit
            local remote_commit
            local_commit=$(git rev-parse HEAD 2>/dev/null)
            remote_commit=$(git rev-parse @{u} 2>/dev/null || echo "")

            if [[ -n "$remote_commit" ]] && [[ "$local_commit" != "$remote_commit" ]]; then
                local behind_count
                behind_count=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
                if [[ "$behind_count" -gt 0 ]]; then
                    echo -e "    ${YELLOW}↓${NC} $skill_name (${behind_count} commits behind)"
                    skills_with_updates=$((skills_with_updates + 1))
                    updates_available=1
                fi
            fi
        fi
    done

    if [[ $skills_checked -eq 0 ]]; then
        echo -e "    ${YELLOW}No Git-based skills found${NC}"
    elif [[ $skills_with_updates -eq 0 ]]; then
        echo -e "    ${GREEN}✓ All $skills_checked skills up to date${NC}"
    else
        echo -e "    ${YELLOW}$skills_with_updates of $skills_checked skills have updates${NC}"
    fi

    echo ""

    if [[ $updates_available -eq 1 ]]; then
        log_info "Run 'clawdbot update-plus update' to apply updates"
        return 0
    else
        log_success "Everything is up to date!"
        return 0
    fi
}

# Install cron job for automatic updates
install_cron() {
    local cron_comment="# Clawdbot Update Plus - Auto-update"
    local cron_schedule="${1:-0 2 * * *}"  # Default: 2 AM daily
    local script_path="${HOME}/.clawdbot/skills/clawdbot-update-plus/bin/update.sh"
    local log_path="${HOME}/.clawdbot/backups/cron-update.log"
    local cron_cmd="${cron_schedule} ${script_path} update >> ${log_path} 2>&1"

    # Check if already installed
    if crontab -l 2>/dev/null | grep -q "clawdbot-update-plus"; then
        log_warning "Cron job already installed. Use 'uninstall-cron' first to reinstall."
        echo ""
        echo "Current cron entry:"
        crontab -l | grep -A1 "Clawdbot Update Plus"
        return 1
    fi

    log_info "Installing cron job..."
    echo ""
    echo "  Schedule: ${cron_schedule}"
    echo "  Command:  ${script_path} update"
    echo "  Log file: ${log_path}"
    echo ""

    # Get current crontab and append new entry
    {
        crontab -l 2>/dev/null || true
        echo ""
        echo "$cron_comment"
        echo "$cron_cmd"
    } | crontab -

    log_success "Cron job installed!"
    echo ""
    log_info "To change schedule, edit with: crontab -e"
    log_info "To remove, run: clawdbot update-plus uninstall-cron"
}

# Uninstall cron job
uninstall_cron() {
    if ! crontab -l 2>/dev/null | grep -q "clawdbot-update-plus"; then
        log_warning "No cron job found for clawdbot-update-plus"
        return 1
    fi

    log_info "Removing cron job..."

    # Remove lines containing clawdbot-update-plus
    crontab -l 2>/dev/null | grep -v "clawdbot-update-plus" | grep -v "Clawdbot Update Plus" | crontab -

    log_success "Cron job removed!"
}

# Main
main() {
  local command="check"
  local positional_args=()
  local do_backup=""
  local do_notify=false
  JSON_REPORT=false

  # Parse options - collect positional args separately
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --no-backup)
        do_backup="false"
        shift
        ;;
      --dry-run)
        DRY_RUN=true
        shift
        ;;
      --no-check-disk)
        CHECK_DISK=false
        shift
        ;;
      --notify)
        do_notify=true
        NOTIFICATION_ENABLED=true
        shift
        ;;
      --auto)
        AUTO_UPDATE=true
        shift
        ;;
      --force)
        FORCE_UPDATE=true
        shift
        ;;
      --json-report)
        JSON_REPORT=true
        shift
        ;;
      --show-diffs)
        SHOW_DIFFS=true
        shift
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      -*)
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
      *)
        positional_args+=("$1")
        shift
        ;;
    esac
  done

  # Extract command and arguments from positional args
  if [[ ${#positional_args[@]} -gt 0 ]]; then
    command="${positional_args[0]}"
  fi

  # Load configuration FIRST (before using BACKUP_BEFORE_UPDATE)
  load_config
  validate_config || exit 1

  # If no --no-backup flag, use config value
  if [[ "$do_backup" == "" ]]; then
    do_backup="$BACKUP_BEFORE_UPDATE"
  fi

  # Auto-detect workspace
  detect_workspace

  # Initialize REPORT_JSON with default empty object (used by backup/update commands)
  REPORT_JSON="${REPORT_JSON:-$(jq -n '{backup: {}}')}"

  case "$command" in
    check)
      check_updates
      ;;

    backup)
      create_backup || exit 1
      ;;

    update)
      if [[ "$DRY_RUN" == true ]]; then
        echo ""
        log_warning "DRY-RUN MODE - No changes will be made"
        echo ""
      fi

      log_info "Starting update process..."
      log_to_file "=== Update started $(date '+%Y-%m-%d %H:%M:%S') ==="
      
      REPORT_JSON=$(jq -n '{run_timestamp: (now | todate), status: "pending", clawdbot_update: {}, skills_updated: [], skills_failed: [], backup: {}}')

      # Check disk space
      if ! check_disk_space; then
        send_notification "error" "Insufficient disk space"
        exit 1
      fi

      # Check internet connection
      if ! check_connection; then
        send_notification "error" "No internet connection"
        exit 1
      fi

      # Create backup if enabled
      local backup_name=""
      if [[ "$do_backup" == true ]]; then
        if ! backup_name=$(create_backup); then
            if [[ "$FORCE_UPDATE" == true ]]; then
                log_warning "Backup failed, but --force is enabled. Continuing without backup."
            else
                log_error "Backup failed. Use --force to continue without backup."
                send_notification "error" "Backup creation failed"
                exit 1
            fi
        fi
      fi

      # Update Clawdbot
      if ! update_clawdbot; then
          log_error "Clawdbot update failed. Rolling back..."
          if [[ -n "$backup_name" ]]; then
              restore_backup "$backup_name" --force
          else
              log_error "No backup available to restore from."
          fi
          send_notification "error" "Clawdbot update failed"
          exit 1
      fi

      # Update skills
      update_skills

      # Summary
      echo ""
      log_success "Update completed!"
      log_to_file "=== Update completed $(date '+%Y-%m-%d %H:%M:%S') ==="
      if [[ -n "$backup_name" ]]; then
        log_info "Backup: $backup_name"
        log_to_file "Backup created: $backup_name"
      fi

      # Send success notification
      send_notification "success" "Backup: ${backup_name:-none}"

      # Clean old logs
      clean_logs

      # Generate JSON report
      generate_json_report
      ;;

    restore)
      local force_flag=""
      [[ "$FORCE_UPDATE" == true ]] && force_flag="--force"
      restore_backup "${positional_args[1]:-}" "$force_flag"
      ;;

    list-backups)
      list_backups || exit 1
      ;;

    diff-backups)
      diff_backups "${positional_args[1]:-}" "${positional_args[2]:-}"
      ;;

    install-cron)
      install_cron "${positional_args[1]:-}"
      ;;

    uninstall-cron)
      uninstall_cron
      ;;

    *)
      show_help
      exit 1
      ;;
  esac
}

main "$@"
