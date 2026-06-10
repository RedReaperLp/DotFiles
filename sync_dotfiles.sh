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

# Überprüfen der Abhängigkeiten
if ! command -v gum &>/dev/null; then
  echo "[ERR] 'gum' fehlt! (sudo pacman -S gum)"
  exit 1
fi

# Modernes Header-Design mit abgerundetem Rahmen
print_header() {
  clear
  gum style \
    --border rounded \
    --margin "1 2" \
    --padding "1 4" \
    --border-foreground "$COLOR_PRIMARY" \
    "  DOTFILES ORCHESTRATOR  " \
    " Sync | Packages | Hooks "
}

print_msg() {
  gum style --foreground "$2" " $1"
}

# Liefert ALLE Ordner (aus ~/dotfiles UND ~/.config)
get_all_dirs() {
  local dirs=""
  [ -d "$DOTFILES_DIR" ] && dirs+=$(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" -exec basename {} \;)
  dirs+=$'\n'
  [ -d "$CONFIG_DIR" ] && dirs+=$(find "$CONFIG_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "dotfiles-sync" -exec basename {} \;)

  # Sortieren, Duplikate und leere Zeilen entfernen
  echo "$dirs" | sort -u | grep -v '^\s*$'
}

# ==========================================
# Kern-Funktionen
# ==========================================

check_dirty_repo() {
  cd "$DOTFILES_DIR" || exit 1
  if [ -n "$(git status --porcelain)" ]; then
    print_msg "[WARN] Du hast ungespeicherte Änderungen im Repo!" "$COLOR_WARNING"
    if ! gum confirm "Trotzdem fortfahren?"; then
      print_msg "Abgebrochen." "$COLOR_DANGER"
      exit 1
    fi
  fi
}

install_packages() {
  local PKG_FILE="$1"
  local APP_NAME="$2"

  if [ -f "$PKG_FILE" ]; then
    local REQUIRED=$(cat "$PKG_FILE" | tr '\n' ' ')
    if [ -n "$REQUIRED" ]; then
      print_msg "[PKG] Installiere Pakete für $APP_NAME..." "$COLOR_INFO"
      paru -S --needed --noconfirm $REQUIRED || print_msg "[ERR] Fehler bei Paketinstallation für $APP_NAME!" "$COLOR_WARNING"
    fi
  fi
}

run_hooks() {
  local HOOK_FILE="$1"
  local APP_NAME="$2"

  if [ -f "$HOOK_FILE" ]; then
    print_msg "[HOOK] Führe Post-Sync Hook für $APP_NAME aus..." "$COLOR_INFO"
    bash "$HOOK_FILE"
  fi
}

create_backup() {
  local TIMESTAMP=$(date +%Y%m%d_%H%M%S)
  local BACKUP_PATH="$BACKUP_BASE_DIR/$TIMESTAMP"

  mkdir -p "$BACKUP_PATH"
  print_msg "[SAVE] Erstelle System-Backup ($TIMESTAMP)..." "$COLOR_INFO"

  # Nur konfigurierte Ordner sichern
  for dir in $(get_all_dirs); do
    if [ -d "$CONFIG_DIR/$dir" ]; then
      cp -r "$CONFIG_DIR/$dir" "$BACKUP_PATH/"
    fi
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
  print_msg "[OK] Rollback erfolgreich abgeschlossen." "$COLOR_SUCCESS"
}

apply_sync() {
  local SELECTED="$1"
  local ALL_DIRS=$(get_all_dirs)

  local BACKUP_PATH=$(create_backup)
  echo ""

  for dir in $ALL_DIRS; do
    local SOURCE_DIR="$DOTFILES_DIR/$dir"
    local TARGET_DIR="$CONFIG_DIR/$dir"
    local PKG_FILE="$SOURCE_DIR/packages.txt"
    local HOOK_FILE="$SOURCE_DIR/post-sync.sh"

    # Prüfen, ob dieser Ordner vom Nutzer ausgewählt wurde
    if echo "$SELECTED" | grep -q "^$dir$"; then

      # --- ORDNER IST AKTIVIERT ---
      if [ -L "$TARGET_DIR" ] && [ "$(readlink "$TARGET_DIR")" = "$SOURCE_DIR" ]; then
        # Bereits ein korrekter Symlink, tue nichts
        :
      elif [ -d "$TARGET_DIR" ] && [ ! -d "$SOURCE_DIR" ]; then
        # NEUER ORDNER: Liegt nur in ~/.config, soll jetzt ins Git aufgenommen werden!
        print_msg "[+] Füge neuen Ordner '$dir' zum Git-Repo hinzu..." "$COLOR_PRIMARY"
        mv "$TARGET_DIR" "$SOURCE_DIR"
        ln -s "$SOURCE_DIR" "$TARGET_DIR"
      else
        # Ordner existiert in Git, muss verlinkt werden (Backup alter lokaler Daten)
        print_msg "[LINK] Aktiviere Sync für: $dir" "$COLOR_SUCCESS"
        [ -d "$TARGET_DIR" ] && mv "$TARGET_DIR" "$TARGET_DIR.bak_$(date +%s)"
        ln -s "$SOURCE_DIR" "$TARGET_DIR"
      fi

      # Pakete & Hooks für aktivierte Ordner ausführen
      install_packages "$PKG_FILE" "$dir"
      run_hooks "$HOOK_FILE" "$dir"

    else
      # --- ORDNER IST DEAKTIVIERT ---
      if [ -L "$TARGET_DIR" ] && [ "$(readlink "$TARGET_DIR")" = "$SOURCE_DIR" ]; then
        print_msg "[UNLINK] Entkopple Sync für: $dir" "$COLOR_WARNING"
        rm "$TARGET_DIR"
        cp -r "$SOURCE_DIR" "$TARGET_DIR"
        print_msg "  -> Lokale Kopie erstellt." "$COLOR_INFO"
      fi
    fi
  done

  # Validierungs-Dialog
  echo ""
  if gum confirm "Sync abgeschlossen! Funktioniert alles wie erwartet?"; then
    mkdir -p "$STATE_DIR"
    echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"
    print_msg "[OK] Neuer Status gespeichert." "$COLOR_SUCCESS"
  else
    restore_backup "$BACKUP_PATH"
  fi
}

# ==========================================
# UI Interaktionen (TUI)
# ==========================================

interactive_selection() {
  local ALL_DIRS=$(get_all_dirs)
  local PREV_SELECTION=""
  [ -f "$INDEX_FILE" ] && PREV_SELECTION=$(cat "$INDEX_FILE")

  # Anleitung in einer stilisierten Box
  gum style \
    --border normal \
    --border-foreground "$COLOR_INFO" \
    --padding "0 2" \
    "Wähle die Ordner für den Sync (Space = Check, Enter = Bestätigen)"

  # Die Auswahlliste mit sauberen [x] / [ ] Checkboxen
  local SELECTED=$(echo "$ALL_DIRS" | gum choose \
    --no-limit \
    --selected="$PREV_SELECTION" \
    --height 15 \
    --cursor-prefix " > " \
    --unselected-prefix "[ ] " \
    --selected-prefix "[x] " \
    --cursor.foreground "$COLOR_PRIMARY" \
    --selected.foreground "$COLOR_SUCCESS")

  if [ $? -eq 0 ]; then
    apply_sync "$SELECTED"
  fi
}

pull_configs() {
  print_msg "[DOWN] Lade Updates von GitHub herunter..." "$COLOR_INFO"
  cd "$DOTFILES_DIR" && git pull
  print_msg "[OK] Aktueller Stand heruntergeladen." "$COLOR_SUCCESS"
}

push_configs() {
  echo ""
  if gum confirm "Möchtest du die lokalen Änderungen hochladen?"; then
    local COMMIT_MSG=$(gum input --placeholder "Commit-Nachricht..." --value "Update configs")
    if [ -n "$COMMIT_MSG" ]; then
      print_msg "[UP] Lade zu GitHub hoch..." "$COLOR_INFO"
      cd "$DOTFILES_DIR" && git add . && git commit -m "$COMMIT_MSG" && git push
      print_msg "[OK] Erfolgreich hochgeladen!" "$COLOR_SUCCESS"
    else
      print_msg "[ERR] Abbruch: Keine Nachricht eingegeben." "$COLOR_DANGER"
    fi
  fi
}

# ==========================================
# Argument Handler & Main Loop
# ==========================================

if [[ "$1" == "--sync" ]]; then
  check_dirty_repo
  pull_configs
  if [ -f "$INDEX_FILE" ]; then
    apply_sync "$(cat "$INDEX_FILE" | tr ',' '\n')"
  else
    interactive_selection
  fi
  push_configs
  exit 0
fi

# Hauptmenü-Schleife
while true; do
  print_header

  # Das Hauptmenü als abgerundete Box
  ACTION=$(gum choose \
    "> Configs auswählen & anwenden" \
    "> Herunterladen (Git Pull)" \
    "> Hochladen (Git Push)" \
    "> Auto-Sync (Pull -> Apply -> Push)" \
    "> Beenden" \
    --height 8 \
    --cursor.foreground "$COLOR_PRIMARY")

  case "$ACTION" in
  "> Configs auswählen & anwenden")
    check_dirty_repo
    interactive_selection
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "> Herunterladen (Git Pull)")
    check_dirty_repo
    pull_configs
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "> Hochladen (Git Push)")
    push_configs
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "> Auto-Sync (Pull -> Apply -> Push)")
    check_dirty_repo
    pull_configs
    if [ -f "$INDEX_FILE" ]; then
      apply_sync "$(cat "$INDEX_FILE" | tr ',' '\n')"
    else
      interactive_selection
    fi
    push_configs
    echo ""
    gum confirm "Zurück zum Hauptmenü?" || exit 0
    ;;
  "> Beenden")
    clear
    exit 0
    ;;
  esac
done
