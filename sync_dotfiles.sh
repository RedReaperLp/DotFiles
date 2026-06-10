#!/bin/bash

# ==========================================
# Konfiguration
# ==========================================
DOTFILES_DIR="$HOME/dotfiles"
CONFIG_DIR="$HOME/.config"

# XDG-konformer Pfad für die Status-Datei (außerhalb des Git-Repos!)
STATE_DIR="$CONFIG_DIR/dotfiles-sync"
INDEX_FILE="$STATE_DIR/sync_state"

# Prüfen, ob gum installiert ist
if ! command -v gum &>/dev/null; then
  echo "❌ 'gum' ist nicht installiert. Bitte mit 'sudo pacman -S gum' installieren."
  exit 1
fi

echo -e "\n✨ Willkommen im Dotfiles-Manager\n"

# ==========================================
# 1. Ordner einlesen & Index prüfen
# ==========================================
# Finde alle echten Verzeichnisse im dotfiles-Ordner (ignoriert .git)
AVAILABLE_DIRS=$(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" -exec basename {} \;)

# Lese den aktuellen Index aus ~/.config aus, um Checkboxen vorab auszuwählen
if [ -f "$INDEX_FILE" ]; then
  PREVIOUS_SELECTION=$(cat "$INDEX_FILE")
else
  PREVIOUS_SELECTION=""
fi

# ==========================================
# 2. Das TUI: Auswahl der Sync-Ordner
# ==========================================
echo "Wähle die Konfigurationen, die synchronisiert (verlinkt) werden sollen:"
echo "(Leertaste = Auswählen/Abwählen | Enter = Bestätigen)"

# Gum baut das interaktive Menü
SELECTED=$(echo "$AVAILABLE_DIRS" | gum choose --no-limit --selected="$PREVIOUS_SELECTION" --height 15)

# Wenn der Nutzer abbricht (ESC)
if [ $? -ne 0 ]; then
  echo "Abgebrochen."
  exit 0
fi

# ==========================================
# 3. Logik: Verlinken vs. Entkoppeln
# ==========================================
echo ""
gum spin --spinner dot --title "Verarbeite Konfigurationen..." -- sleep 1

for dir in $AVAILABLE_DIRS; do
  SOURCE_DIR="$DOTFILES_DIR/$dir"
  TARGET_DIR="$CONFIG_DIR/$dir"

  # Prüfen, ob der Ordner in der NEUEN Auswahl ist
  if echo "$SELECTED" | grep -q "^$dir$"; then
    # ORDNER IST AUSGEWÄHLT -> Soll ein Symlink sein
    if [ ! -L "$TARGET_DIR" ]; then
      echo "🔗 Aktiviere Sync für: $dir"
      # Falls ein alter Ordner existiert, sichern wir ihn kurz
      [ -d "$TARGET_DIR" ] && mv "$TARGET_DIR" "$TARGET_DIR.bak_$(date +%s)"
      ln -s "$SOURCE_DIR" "$TARGET_DIR"
    fi
  else
    # ORDNER IST DESELEKTIERT -> Symlink entfernen & aktuellen Stand kopieren
    if [ -L "$TARGET_DIR" ]; then
      echo "✂️  Entkopple Sync für: $dir"
      # Link löschen
      rm "$TARGET_DIR"
      # Den aktuellen Stand als echten lokalen Ordner kopieren
      cp -r "$SOURCE_DIR" "$TARGET_DIR"
      echo "   -> Aktueller Stand wurde als lokaler Ordner nach ~/.config/$dir geschrieben."
    fi
  fi
done

# ==========================================
# 4. Status sicher speichern
# ==========================================
# Erstelle den versteckten Config-Ordner, falls er nicht existiert
mkdir -p "$STATE_DIR"
# Speichere die Auswahl (Komma-separiert für gum)
echo "$SELECTED" | tr '\n' ',' | sed 's/,$//' >"$INDEX_FILE"

# ==========================================
# 5. Der Git-Upload (Interaktiv)
# ==========================================
echo ""
if gum confirm "Möchtest du die aktuellen Änderungen jetzt auf GitHub hochladen?"; then
  COMMIT_MSG=$(gum input --placeholder "Commit-Nachricht eingeben..." --value "Update dotfiles")

  if [ -n "$COMMIT_MSG" ]; then
    echo ""
    gum spin --spinner line --title "Lade zu GitHub hoch..." -- bash -c "
            cd '$DOTFILES_DIR' && \
            git add . && \
            git commit -m '$COMMIT_MSG' && \
            git push
        "
    echo "✅ Erfolgreich hochgeladen!"
  else
    echo "Upload abgebrochen (Keine Nachricht eingegeben)."
  fi
else
  echo "Upload übersprungen. Alles ist lokal eingerichtet!"
fi
