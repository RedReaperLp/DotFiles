#!/bin/bash

# ==========================================
# Configuration & Paths
# ==========================================
# Resolves the directory where *this script* is located (regardless of where it's called from)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$HOME/.config"
STATE_DIR="$CONFIG_DIR/dotfiles-sync"
INDEX_FILE="$STATE_DIR/sync_state"
BACKUP_BASE_DIR="$STATE_DIR/history"
GLOBAL_PKGS_FILE="$DOTFILES_DIR/global_packages.txt"

# ==========================================
# Styling & UI Setup (via gum)
# ==========================================
COLOR_PRIMARY="212"
COLOR_SUCCESS="46"
COLOR_WARNING="214"
COLOR_DANGER="196"
COLOR_INFO="39"
COLOR_MUTED="245"

# Check dependencies
if ! command -v gum &>/dev/null; then
  echo "[ERR] 'gum' is missing! (sudo pacman -S gum)"
  exit 1
fi
if ! command -v paru &>/dev/null; then
  echo "[ERR] 'paru' is missing!"
  exit 1
fi
if ! command -v expac &>/dev/null; then
  echo "[ERR] 'expac' is missing! (sudo pacman -S expac)"
  exit 1
fi

print_header() {
  clear
  gum style --border rounded --margin "1 2" --padding "1 4" --border-foreground "$COLOR_PRIMARY" \
    "  DOTFILES ORCHESTRATOR  " " Sync | Configs | Packages " \
    " $(gum style --foreground "$COLOR_MUTED" "Path: $DOTFILES_DIR") "
}

print_msg() { gum style --foreground "$2" " $1"; }

get_all_dirs() {
  local dirs=""
  [ -d "$DOTFILES_DIR" ] && dirs+=$(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" -exec basename {} \;)
  dirs+=$'\n'
  [ -d "$CONFIG_DIR" ] && dirs+=$(find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "dotfiles-sync" -exec basename {} \;)
  echo "$dirs" | tr -d '\r' | sort -u | grep -v '^\s*$'
}

check_dirty_repo() {
  cd "$DOTFILES_DIR" || exit 1
  if [ -n "$(git status --porcelain)" ]; then
    print_msg "[WARN] You have uncommitted changes in the repository!" "$COLOR_WARNING"
    gum confirm "Continue anyway?" || exit 1
  fi
}

# ==========================================
# 1. Config & Symlink Logic
# ==========================================
create_backup() {
  local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local BACKUP_PATH="$BACKUP_BASE_DIR/$TIMESTAMP"
  mkdir -p "$BACKUP_PATH"

  for dir in $(get_all_dirs); do
    [ -d "$CONFIG_DIR/$dir" ] && cp -r "$CONFIG_DIR/$dir" "$BACKUP_PATH/"
  done
  echo "$BACKUP_PATH"
}

restore_backup() {
  local BACKUP_PATH="$1"
  print_msg "[UNDO] Restoring backup..." "$COLOR_WARNING"
  for dir in $(ls "$BACKUP_PATH"); do
    rm -rf "$CONFIG_DIR/$dir"
    cp -r "$BACKUP_PATH/$dir" "$CONFIG_DIR/"
  done
  print_msg "[OK] Rollback complete." "$COLOR_SUCCESS"
}

apply_configs() {
  local SELECTED=$(echo "$1" | tr -d '\r')
  local ALL_DIRS=$(get_all_dirs)

  print_msg "Backing up current state..." "$COLOR_MUTED"
  local BACKUP_PATH=$(create_backup)
  echo ""

  local CHANGES_MADE=false

  for dir in $ALL_DIRS; do
    local SOURCE_DIR="$DOTFILES_DIR/$dir"
    local TARGET_DIR="$CONFIG_DIR/$dir"

    if echo "$SELECTED" | grep -q "^$dir$"; then
      if [ -L "$TARGET_DIR" ] && [ "$(readlink "$TARGET_DIR")" = "$SOURCE_DIR" ]; then
        print_msg "[SKIP] Already linked: $dir" "$COLOR_MUTED"
      elif [ -d "$TARGET_DIR" ] && [ ! -d "$SOURCE_DIR" ]; then
        print_msg "[+] Adding new folder '$dir' to Git repository..." "$COLOR_PRIMARY"
        mv "$TARGET_DIR" "$SOURCE_DIR"
        ln -s "$SOURCE_DIR" "$TARGET_DIR"
        CHANGES_MADE=true
      else
        print_msg "[LINK] Enabling sync for: $dir" "$COLOR_SUCCESS"
        [ -d "$TARGET_DIR" ] && mv "$TARGET_DIR" "$TARGET_DIR.bak_$(date +%s)"
        ln -s "$SOURCE_DIR" "$TARGET_DIR"
        CHANGES_MADE=true
      fi

      # Execute post-sync hook if available
      if [ -f "$SOURCE_DIR/post-sync.sh" ]; then
        print_msg "[HOOK] Running post-sync hook: $dir" "$COLOR_INFO"
        bash "$SOURCE_DIR/post-sync.sh"
      fi
    else
      if [ -L "$TARGET_DIR" ] && [ "$(readlink "$TARGET_DIR")" = "$SOURCE_DIR" ]; then
        print_msg "[UNLINK] Disconnecting sync for: $dir" "$COLOR_WARNING"
        rm "$TARGET_DIR"
        cp -r "$SOURCE_DIR" "$TARGET_DIR"
        CHANGES_MADE=true
      fi
    fi
  done

  echo ""
  if [ "$CHANGES_MADE" = true ]; then
    if gum confirm "Configs applied! Is everything working properly?"; then
      mkdir -p "$STATE_DIR"
      echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"
      print_msg "[OK] New config state saved." "$COLOR_SUCCESS"
    else
      restore_backup "$BACKUP_PATH"
    fi
  else
    mkdir -p "$STATE_DIR"
    echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"
    print_msg "[OK] Symlinks unchanged." "$COLOR_SUCCESS"
  fi
}

interactive_configs() {
  local ALL_DIRS=$(get_all_dirs)
  local PREV_SELECTION=""
  [ -f "$INDEX_FILE" ] && PREV_SELECTION=$(cat "$INDEX_FILE" | tr -d '\r')

  gum style --border normal --border-foreground "$COLOR_INFO" --padding "0 2" "Select configs to sync (Type to search)"
  local SELECTED=$(echo "$ALL_DIRS" | gum choose --no-limit --selected="$PREV_SELECTION" --height 15 --cursor-prefix " > " --unselected-prefix "[ ] " --selected-prefix "[x] " --cursor.foreground "$COLOR_PRIMARY" --selected.foreground "$COLOR_SUCCESS")

  [ $? -eq 0 ] && apply_configs "$SELECTED"
}

# ==========================================
# 2. Global Package Logic (paru/pacman)
# ==========================================
apply_global_packages() {
  if [ -f "$GLOBAL_PKGS_FILE" ]; then
    local PKGS=$(cat "$GLOBAL_PKGS_FILE" | tr -d '\r' | tr '\n' ' ')
    local MISSING_PKGS=""

    for pkg in $PKGS; do
      if ! pacman -Qq "$pkg" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
      fi
    done

    if [ -n "$MISSING_PKGS" ]; then
      print_msg "[PKG] Installing missing global packages:$MISSING_PKGS" "$COLOR_INFO"
      paru -S --needed $MISSING_PKGS || print_msg "[ERR] Global package installation failed!" "$COLOR_WARNING"
    else
      print_msg "[SKIP] All global packages are already installed." "$COLOR_MUTED"
    fi
  fi
}

interactive_packages() {
  local SORT_MODE=$(gum choose \
    "🔤 Alphabetical (Default)" \
    "📅 By Date (Newest first)" \
    "💾 By Size (Largest first)" \
    --header "How should the packages be sorted?" --height 6 --cursor.foreground "$COLOR_PRIMARY")

  [ $? -ne 0 ] && return

  print_msg "Loading and sorting packages..." "$COLOR_MUTED"

  local INSTALLED_PKGS
  case "$SORT_MODE" in
  "📅 By Date (Newest first)")
    INSTALLED_PKGS=$(expac "%t %n" $(paru -Qqe) | sort -nr | awk '{print $2}')
    ;;
  "💾 By Size (Largest first)")
    INSTALLED_PKGS=$(expac "%m %n" $(paru -Qqe) | sort -nr | awk '{print $2}')
    ;;
  *)
    INSTALLED_PKGS=$(paru -Qqe | sort)
    ;;
  esac

  if [ -f "$GLOBAL_PKGS_FILE" ]; then
    INSTALLED_PKGS=$(echo -e "$INSTALLED_PKGS\n$(cat "$GLOBAL_PKGS_FILE" | tr -d '\r')" | awk '!seen[$0]++' | grep -v '^\s*$')
  fi

  local PREV_PKGS=""
  [ -f "$GLOBAL_PKGS_FILE" ] && PREV_PKGS=$(cat "$GLOBAL_PKGS_FILE" | tr -d '\r' | tr '\n' ',')

  clear
  gum style --border normal --border-foreground "$COLOR_INFO" --padding "0 2" "Select packages to sync (Type to search)"

  local SELECTED_PKGS=$(echo "$INSTALLED_PKGS" | gum choose --no-limit --selected="${PREV_PKGS%,}" --height 20 --cursor-prefix " > " --unselected-prefix "[ ] " --selected-prefix "[x] " --cursor.foreground "$COLOR_PRIMARY" --selected.foreground "$COLOR_SUCCESS")

  if [ $? -eq 0 ]; then
    echo "$SELECTED_PKGS" >"$GLOBAL_PKGS_FILE"
    print_msg "[OK] Global package list saved." "$COLOR_SUCCESS"
    echo ""
    apply_global_packages
  fi
}

# ==========================================
# 3. Git Logic
# ==========================================
pull_configs() {
  print_msg "[DOWN] Pulling updates..." "$COLOR_INFO"
  cd "$DOTFILES_DIR" && git pull
  print_msg "[OK] Git pull successful." "$COLOR_SUCCESS"
}

push_configs() {
  cd "$DOTFILES_DIR" || return

  # Redundancy Check 1: Are there any local changes to push?
  if [ -z "$(git status --porcelain)" ]; then
    print_msg "[SKIP] No local changes found to push." "$COLOR_MUTED"
    return
  fi

  # Redundancy Check 2: Does the user have push permissions / a writable remote?
  # Tests via --dry-run whether the remote accepts pushes (skips if cloned read-only via HTTPS)
  local REMOTE_URL=$(git config --get remote.origin.url)
  if [[ "$REMOTE_URL" == https://* ]] && ! git push --dry-run origin HEAD &>/dev/null; then
    print_msg "[SKIP] Read-only repository (external clone). Skipping git push." "$COLOR_MUTED"
    return
  fi

  echo ""
  if gum confirm "You have uncommitted changes. Push now?"; then
    local COMMIT_MSG=$(gum input --placeholder "Commit message..." --value "Update configs & packages")
    if [ -n "$COMMIT_MSG" ]; then
      print_msg "[UP] Pushing to GitHub..." "$COLOR_INFO"
      git add . && git commit -m "$COMMIT_MSG" && git push
      print_msg "[OK] Pushed successfully!" "$COLOR_SUCCESS"
    fi
  fi
}

# ==========================================
# Argument Handler & Main Loop
# ==========================================
if [[ "$1" == "--sync" ]]; then
  pull_configs
  apply_global_packages
  [ -f "$INDEX_FILE" ] && apply_configs "$(cat "$INDEX_FILE" | tr ',' '\n')" || interactive_configs
  push_configs
  exit 0
fi

while true; do
  print_header
  ACTION=$(gum choose \
    "> 📁 Manage Config Folders (Symlinks)" \
    "> 📦 Manage System Packages (paru/pacman)" \
    "> ⬇️  Download Updates (Git Pull)" \
    "> ⬆️  Upload Changes (Git Push)" \
    "> 🚀 Auto-Sync (Pull -> Apply -> Push)" \
    "> ❌ Exit" \
    --height 9 --cursor.foreground "$COLOR_PRIMARY")

  case "$ACTION" in
  "> 📁 Manage Config Folders (Symlinks)")
    interactive_configs
    echo ""
    gum confirm "Back to menu?" || exit 0
    ;;
  "> 📦 Manage System Packages (paru/pacman)")
    interactive_packages
    echo ""
    gum confirm "Back to menu?" || exit 0
    ;;
  "> ⬇️  Download Updates (Git Pull)")
    pull_configs
    echo ""
    gum confirm "Back to menu?" || exit 0
    ;;
  "> ⬆️  Upload Changes (Git Push)")
    push_configs
    echo ""
    gum confirm "Back to menu?" || exit 0
    ;;
  "> 🚀 Auto-Sync (Pull -> Apply -> Push)")
    pull_configs
    apply_global_packages
    [ -f "$INDEX_FILE" ] && apply_configs "$(cat "$INDEX_FILE" | tr ',' '\n')" || interactive_configs
    push_configs
    echo ""
    gum confirm "Back to menu?" || exit 0
    ;;
  "> ❌ Exit")
    clear
    exit 0
    ;;
  esac
done
