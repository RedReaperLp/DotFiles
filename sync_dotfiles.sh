#!/bin/bash

# ==========================================
# Konfiguration & Pfade
# ==========================================
DOTFILES_DIR="$HOME/dotfiles"
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

# Abhängigkeiten prüfen
if ! command -v gum &>/dev/null; then
  echo "[ERR] 'gum' fehlt! (sudo pacman -S gum)"
  exit 1
fi
if ! command -v paru &>/dev/null; then
  echo "[ERR] 'paru' fehlt!"
  exit 1
fi
if ! command -v expac &>/dev/null; then
  echo "[ERR] 'expac' fehlt! (sudo pacman -S expac)"
  exit 1
fi

print_header() {
  clear
  gum style --border rounded --margin "1 2" --padding "1 4" --border-foreground "$COLOR_PRIMARY" \
    "  DOTFILES ORCHESTRATOR  " " Sync | Configs | Packages "
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
    print_msg "[WARN] Du hast ungespeicherte Änderungen im Repo!" "$COLOR_WARNING"
    gum confirm "Trotzdem fortfahren?" || exit 1
  fi
}

# ==========================================
# 1. Config & Symlink Logik
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
  print_msg "[UNDO] Stelle Backup wieder her..." "$COLOR_WARNING"
  for dir in $(ls "$BACKUP_PATH"); do
    rm -rf "$CONFIG_DIR/$dir"
    cp -r "$BACKUP_PATH/$dir" "$CONFIG_DIR/"
  done
  print_msg "[OK] Rollback abgeschlossen." "$COLOR_SUCCESS"
}

apply_configs() {
  local SELECTED=$(echo "$1" | tr -d '\r')
  local ALL_DIRS=$(get_all_dirs)

  print_msg "Sichere aktuellen Zustand..." "$COLOR_MUTED"
  local BACKUP_PATH=$(create_backup)
  echo ""

  local CHANGES_MADE=false

  for dir in $ALL_DIRS; do
    local SOURCE_DIR="$DOTFILES_DIR/$dir"
    local TARGET_DIR="$CONFIG_DIR/$dir"

    if echo "$SELECTED" | grep -q "^$dir$"; then
      if [ -L "$TARGET_DIR" ] && [ "$(readlink "$TARGET_DIR")" = "$SOURCE_DIR" ]; then
        print_msg "[SKIP] Bereits verlinkt: $dir" "$COLOR_MUTED"
      elif [ -d "$TARGET_DIR" ] && [ ! -d "$SOURCE_DIR" ]; then
        print_msg "[+] Füge neuen Ordner '$dir' zum Git-Repo hinzu..." "$COLOR_PRIMARY"
        mv "$TARGET_DIR" "$SOURCE_DIR"
        ln -s "$SOURCE_DIR" "$TARGET_DIR"
        CHANGES_MADE=true
      else
        print_msg "[LINK] Aktiviere Sync für: $dir" "$COLOR_SUCCESS"
        [ -d "$TARGET_DIR" ] && mv "$TARGET_DIR" "$TARGET_DIR.bak_$(date +%s)"
        ln -s "$SOURCE_DIR" "$TARGET_DIR"
        CHANGES_MADE=true
      fi

      # Post-Sync Hook für die Config ausführen
      if [ -f "$SOURCE_DIR/post-sync.sh" ]; then
        print_msg "[HOOK] Führe Hook aus: $dir" "$COLOR_INFO"
        bash "$SOURCE_DIR/post-sync.sh"
      fi
    else
      if [ -L "$TARGET_DIR" ] && [ "$(readlink "$TARGET_DIR")" = "$SOURCE_DIR" ]; then
        print_msg "[UNLINK] Entkopple Sync für: $dir" "$COLOR_WARNING"
        rm "$TARGET_DIR"
        cp -r "$SOURCE_DIR" "$TARGET_DIR"
        CHANGES_MADE=true
      fi
    fi
  done

  echo ""
  if [ "$CHANGES_MADE" = true ]; then
    if gum confirm "Configs angewendet! Klappt alles?"; then
      mkdir -p "$STATE_DIR"
      echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"
      print_msg "[OK] Neuer Config-Status gespeichert." "$COLOR_SUCCESS"
    else
      restore_backup "$BACKUP_PATH"
    fi
  else
    mkdir -p "$STATE_DIR"
    echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"
    print_msg "[OK] Symlinks unverändert." "$COLOR_SUCCESS"
  fi
}

interactive_configs() {
  local ALL_DIRS=$(get_all_dirs)
  local PREV_SELECTION=""
  [ -f "$INDEX_FILE" ] && PREV_SELECTION=$(cat "$INDEX_FILE" | tr -d '\r')

  gum style --border normal --border-foreground "$COLOR_INFO" --padding "0 2" "Configs auswählen (Tippen zum Suchen)"
  local SELECTED=$(echo "$ALL_DIRS" | gum choose --no-limit --selected="$PREV_SELECTION" --height 15 --cursor-prefix " > " --unselected-prefix "[ ] " --selected-prefix "[x] " --cursor.foreground "$COLOR_PRIMARY" --selected.foreground "$COLOR_SUCCESS")

  [ $? -eq 0 ] && apply_configs "$SELECTED"
}

# ==========================================
# 2. Globale Paket-Logik (paru/pacman)
# ==========================================
apply_global_packages() {
  if [ -f "$GLOBAL_PKGS_FILE" ]; then
    local PKGS=$(cat "$GLOBAL_PKGS_FILE" | tr -d '\r' | tr '\n' ' ')
    local MISSING_PKGS=""

    # Redundanz-Check: Fehlt wirklich etwas?
    for pkg in $PKGS; do
      if ! pacman -Qq "$pkg" &>/dev/null; then
        MISSING_PKGS="$MISSING_PKGS $pkg"
      fi
    done

    if [ -n "$MISSING_PKGS" ]; then
      print_msg "[PKG] Installiere fehlende globale Pakete:$MISSING_PKGS" "$COLOR_INFO"
      # --noconfirm entfernt, damit paru pausiert und Diffs/Bestätigung anzeigt
      paru -S --needed $MISSING_PKGS || print_msg "[ERR] Fehler bei globaler Paketinstallation!" "$COLOR_WARNING"
    else
      print_msg "[SKIP] Alle System-Pakete sind bereits installiert." "$COLOR_MUTED"
    fi
  fi
}

interactive_packages() {
  local SORT_MODE=$(gum choose \
    "🔤 Alphabetisch (Standard)" \
    "📅 Nach Datum (Neueste zuerst)" \
    "💾 Nach Größe (Größte zuerst)" \
    --header "Wie sollen die Pakete sortiert werden?" --height 6 --cursor.foreground "$COLOR_PRIMARY")

  [ $? -ne 0 ] && return

  print_msg "Lade und sortiere Pakete..." "$COLOR_MUTED"

  local INSTALLED_PKGS
  case "$SORT_MODE" in
  "📅 Nach Datum (Neueste zuerst)")
    INSTALLED_PKGS=$(expac "%t %n" $(paru -Qqe) | sort -nr | awk '{print $2}')
    ;;
  "💾 Nach Größe (Größte zuerst)")
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
  gum style --border normal --border-foreground "$COLOR_INFO" --padding "0 2" "Pakete für Sync auswählen (Tippen = Suchen!)"

  local SELECTED_PKGS=$(echo "$INSTALLED_PKGS" | gum choose --no-limit --selected="${PREV_PKGS%,}" --height 20 --cursor-prefix " > " --unselected-prefix "[ ] " --selected-prefix "[x] " --cursor.foreground "$COLOR_PRIMARY" --selected.foreground "$COLOR_SUCCESS")

  if [ $? -eq 0 ]; then
    echo "$SELECTED_PKGS" >"$GLOBAL_PKGS_FILE"
    print_msg "[OK] Globale Paketliste gespeichert." "$COLOR_SUCCESS"
    echo ""
    apply_global_packages
  fi
}

# ==========================================
# 3. Git Logik
# ==========================================
pull_configs() {
  print_msg "[DOWN] Lade Updates..." "$COLOR_INFO"
  cd "$DOTFILES_DIR" && git pull
  print_msg "[OK] Git Pull ausgeführt." "$COLOR_SUCCESS"
}

push_configs() {
  cd "$DOTFILES_DIR" || return

  # Redundanz-Check: Gibt es überhaupt Änderungen zum Hochladen?
  if [ -z "$(git status --porcelain)" ]; then
    print_msg "[SKIP] Keine lokalen Änderungen zum Hochladen gefunden." "$COLOR_MUTED"
    return
  fi

  echo ""
  if gum confirm "Du hast ungespeicherte Änderungen. Jetzt hochladen?"; then
    local COMMIT_MSG=$(gum input --placeholder "Commit-Nachricht..." --value "Update configs & packages")
    if [ -n "$COMMIT_MSG" ]; then
      print_msg "[UP] Lade zu GitHub hoch..." "$COLOR_INFO"
      git add . && git commit -m "$COMMIT_MSG" && git push
      print_msg "[OK] Hochgeladen!" "$COLOR_SUCCESS"
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
    "> 📁 Config-Ordner (Symlinks) verwalten" \
    "> 📦 System-Pakete (paru/pacman) verwalten" \
    "> ⬇️  Herunterladen (Git Pull)" \
    "> ⬆️  Hochladen (Git Push)" \
    "> 🚀 Auto-Sync (Pull -> Apply -> Push)" \
    "> ❌ Beenden" \
    --height 9 --cursor.foreground "$COLOR_PRIMARY")

  case "$ACTION" in
  "> 📁 Config-Ordner (Symlinks) verwalten")
    interactive_configs
    echo ""
    gum confirm "Zurück?" || exit 0
    ;;
  "> 📦 System-Pakete (paru/pacman) verwalten")
    interactive_packages
    echo ""
    gum confirm "Zurück?" || exit 0
    ;;
  "> ⬇️  Herunterladen (Git Pull)")
    pull_configs
    echo ""
    gum confirm "Zurück?" || exit 0
    ;;
  "> ⬆️  Hochladen (Git Push)")
    push_configs
    echo ""
    gum confirm "Zurück?" || exit 0
    ;;
  "> 🚀 Auto-Sync (Pull -> Apply -> Push)")
    pull_configs
    apply_global_packages
    [ -f "$INDEX_FILE" ] && apply_configs "$(cat "$INDEX_FILE" | tr ',' '\n')" || interactive_configs
    push_configs
    echo ""
    gum confirm "Zurück?" || exit 0
    ;;
  "> ❌ Beenden")
    clear
    exit 0
    ;;
  esac
done
