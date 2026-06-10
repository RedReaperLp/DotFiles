#!/bin/bash

# ==========================================
# Konfiguration & Pfade
# ==========================================
DOTFILES_DIR="$HOME/dotfiles"
CONFIG_DIR="$HOME/.config"
STATE_DIR="$CONFIG_DIR/dotfiles-sync"
INDEX_FILE="$STATE_DIR/sync_state"
BACKUP_BASE_DIR="$STATE_DIR/history"

# ==========================================
# Styling & UI Setup (via gum)
# ==========================================
COLOR_PRIMARY="212" # Pink/Magenta
COLOR_SUCCESS="46"  # Grün
COLOR_WARNING="214" # Orange
COLOR_DANGER="196"  # Rot
COLOR_INFO="39"     # Blau

print_header() {
  clear
  gum style \
    --border rounded \
    --margin "1 2" \
    --padding "1 4" \
    --border-foreground "$COLOR_PRIMARY" \
    "✨ Dotfiles Orchestrator ✨" \
    "Manage deine Symlinks, Pakete und Backups"
}

print_msg() {
  gum style --foreground "$2" " $1"
}

# Voraussetzungen prüfen
if ! command -v gum &>/dev/null; then
  echo "❌ 'gum' fehlt! Bitte ausführen: sudo pacman -S gum"
  exit 1
fi
if ! command -v paru &>/dev/null; then
  echo "❌ 'paru' fehlt! Bitte installiere einen AUR-Helper."
  exit 1
fi

# ==========================================
# Kern-Funktionen
# ==========================================

check_dirty_repo() {
  cd "$DOTFILES_DIR" || exit 1
  if [ -n "$(git status --porcelain)" ]; then
    print_msg "⚠️ WARNUNG: Du hast ungespeicherte Änderungen im Repo!" "$COLOR_WARNING"
    if ! gum confirm "Möchtest du trotzdem fortfahren?"; then
      print_msg "Abgebrochen." "$COLOR_DANGER"
      exit 1
    fi
  fi
}

install_packages() {
  local PKG_FILE="$1"
  local APP_NAME="$2"
  local DRY_RUN="$3"

  if [ -f "$PKG_FILE" ]; then
    local REQUIRED
    REQUIRED=$(cat "$PKG_FILE" | tr '\n' ' ')

    if [ -n "$REQUIRED" ]; then
      if [ "$DRY_RUN" = true ]; then
        print_msg "📦 [DRY RUN] Würde installieren für $APP_NAME: $REQUIRED" "$COLOR_INFO"
      else
        print_msg "📦 Installiere Pakete für $APP_NAME..." "$COLOR_INFO"
        paru -S --needed --noconfirm $REQUIRED || print_msg "⚠️ Fehler bei Paketinstallation für $APP_NAME!" "$COLOR_WARNING"
      fi
    fi
  fi
}

run_hooks() {
  local HOOK_FILE="$1"
  local APP_NAME="$2"
  local DRY_RUN="$3"

  if [ -f "$HOOK_FILE" ]; then
    if [ "$DRY_RUN" = true ]; then
      print_msg "🪝 [DRY RUN] Würde Hook ausführen für $APP_NAME" "$COLOR_INFO"
    else
      print_msg "🪝 Führe Post-Sync Hook für $APP_NAME aus..." "$COLOR_INFO"
      bash "$HOOK_FILE"
    fi
  fi
}

create_backup() {
  local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local BACKUP_PATH="$BACKUP_BASE_DIR/$TIMESTAMP"
  local SELECTED="$1"

  mkdir -p "$BACKUP_PATH"
  print_msg "💾 Erstelle System-Backup ($TIMESTAMP)..." "$COLOR_INFO"

  for dir in $(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" -exec basename {} \;); do
    if [ -d "$CONFIG_DIR/$dir" ]; then
      cp -r "$CONFIG_DIR/$dir" "$BACKUP_PATH/"
    fi
  done
  echo "$BACKUP_PATH"
}

restore_backup() {
  local BACKUP_PATH="$1"
  print_msg "⏪ Stelle Backup wieder her..." "$COLOR_WARNING"

  for dir in $(ls "$BACKUP_PATH"); do
    rm -rf "$CONFIG_DIR/$dir"
    cp -r "$BACKUP_PATH/$dir" "$CONFIG_DIR/"
  done
  print_msg "✅ Rollback erfolgreich abgeschlossen." "$COLOR_SUCCESS"
}

apply_sync() {
  local SELECTED="$1"
  local DRY_RUN="$2"
  local AVAILABLE_DIRS=$(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" -exec basename {} \;)

  local BACKUP_PATH=""
  if [ "$DRY_RUN" = false ]; then
    BACKUP_PATH=$(create_backup "$SELECTED")
  fi

  echo ""
  for dir in $AVAILABLE_DIRS; do
    local SOURCE_DIR="$DOTFILES_DIR/$dir"
    local TARGET_DIR="$CONFIG_DIR/$dir"
    local PKG_FILE="$SOURCE_DIR/packages.txt"
    local HOOK_FILE="$SOURCE_DIR/post-sync.sh"

    if echo "$SELECTED" | grep -q "\b$dir\b"; then
      # --- ORDNER AKTIVIERT ---
      if [ "$DRY_RUN" = true ]; then
        print_msg "🔗 [DRY RUN] Würde Sync aktivieren für: $dir" "$COLOR_SUCCESS"
        install_packages "$PKG_FILE" "$dir" true
        run_hooks "$HOOK_FILE" "$dir" true
      else
        if [ ! -L "$TARGET_DIR" ]; then
          print_msg "🔗 Aktiviere Sync für: $dir" "$COLOR_SUCCESS"
          rm -rf "$TARGET_DIR" 2>/dev/null
          ln -s "$SOURCE_DIR" "$TARGET_DIR"
        fi
        install_packages "$PKG_FILE" "$dir" false
        run_hooks "$HOOK_FILE" "$dir" false
      fi
    else
      # --- ORDNER DEAKTIVIERT ---
      if [ -L "$TARGET_DIR" ]; then
        if [ "$DRY_RUN" = true ]; then
          print_msg "✂️  [DRY RUN] Würde Sync entkoppeln für: $dir" "$COLOR_WARNING"
        else
          print_msg "✂️  Entkopple Sync für: $dir" "$COLOR_WARNING"
          rm "$TARGET_DIR"
          cp -r "$SOURCE_DIR" "$TARGET_DIR"
          print_msg "   -> Lokale Kopie erstellt." "$COLOR_INFO"
        fi
      fi
    fi
  done

  # Validierungs-Dialog
  if [ "$DRY_RUN" = false ]; then
    echo ""
    if gum confirm "Sync abgeschlossen! Funktioniert alles wie erwartet?"; then
      mkdir -p "$STATE_DIR"
      echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"
      print_msg "✅ Neuer Status gespeichert." "$COLOR_SUCCESS"
    else
      restore_backup "$BACKUP_PATH"
    fi
  fi
}

pull_configs() {
  print_msg "⬇️  Lade Updates von GitHub herunter..." "$COLOR_INFO"
  cd "$DOTFILES_DIR" && git pull
  print_msg "✅ Aktueller Stand heruntergeladen." "$COLOR_SUCCESS"
}

push_configs() {
  echo ""
  if gum confirm "Möchtest du die lokalen Änderungen hochladen?"; then
    local COMMIT_MSG=$(gum input --placeholder "Commit-Nachricht..." --value "Update configs")
    if [ -n "$COMMIT_MSG" ]; then
      print_msg "⬆️  Lade zu GitHub hoch..." "$COLOR_INFO"
      cd "$DOTFILES_DIR" && git add . && git commit -m "$COMMIT_MSG" && git push
      print_msg "✅ Erfolgreich hochgeladen!" "$COLOR_SUCCESS"
    else
      print_msg "❌ Abbruch: Keine Nachricht eingegeben." "$COLOR_DANGER"
    fi
  fi
}

interactive_selection() {
  local AVAILABLE_DIRS=$(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" -exec basename {} \;)
  local PREV_SELECTION=""
  [ -f "$INDEX_FILE" ] && PREV_SELECTION=$(cat "$INDEX_FILE")

  print_msg "Wähle die Konfigurationen für den Sync:" "$COLOR_PRIMARY"
  local SELECTED=$(echo "$AVAILABLE_DIRS" | gum choose --no-limit --selected="$PREV_SELECTION" --height 15 --cursor-prefix "( ) " --selected-prefix "(x) ")

  if [ $? -eq 0 ]; then
    apply_sync "$SELECTED" false
  fi
}

# ==========================================
# Argument Handler & Main Loop
# ==========================================

if [[ "$1" == "--sync" ]]; then
  check_dirty_repo
  pull_configs
  if [ -f "$INDEX_FILE" ]; then
    apply_sync "$(cat "$INDEX_FILE" | tr ',' '\n')" false
  else
    interactive_selection
  fi
  push_configs
  exit 0
elif [[ "$1" == "--dry" ]]; then
  print_header
  print_msg "🔍 DRY RUN MODUS AKTIV - Es werden keine Änderungen vorgenommen" "$COLOR_WARNING"
  if [ -f "$INDEX_FILE" ]; then
    apply_sync "$(cat "$INDEX_FILE" | tr ',' '\n')" true
  else
    print_msg "Kein Index gefunden. Bitte erstelle zuerst einen Sync-Status." "$COLOR_DANGER"
  fi
  exit 0
fi

while true; do
  print_header
  ACTION=$(gum choose \
    "⚙️  Configs auswählen & anwenden" \
    "⬇️  Herunterladen (Git Pull)" \
    "⬆️  Hochladen (Git Push)" \
    "🚀 Auto-Sync (Pull -> Apply -> Push)" \
    "🔍 Dry-Run (Änderungen simulieren)" \
    "❌ Beenden" \
    --height 10)

  case "$ACTION" in
  "⚙️  Configs auswählen & anwenden")
    check_dirty_repo
    interactive_selection
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "⬇️  Herunterladen (Git Pull)")
    check_dirty_repo
    pull_configs
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "⬆️  Hochladen (Git Push)")
    push_configs
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "🚀 Auto-Sync (Pull -> Apply -> Push)")
    check_dirty_repo
    pull_configs
    if [ -f "$INDEX_FILE" ]; then
      apply_sync "$(cat "$INDEX_FILE" | tr ',' '\n')" false
    else
      interactive_selection
    fi
    push_configs
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "🔍 Dry-Run (Änderungen simulieren)")
    if [ -f "$INDEX_FILE" ]; then
      apply_sync "$(cat "$INDEX_FILE" | tr ',' '\n')" true
    else
      print_msg "Kein Index gefunden. Bitte wähle erst Configs aus." "$COLOR_DANGER"
    fi
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "❌ Beenden")
    clear
    exit 0
    ;;
  esac
done
