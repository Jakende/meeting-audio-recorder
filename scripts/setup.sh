#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

echo "================================================"
echo "  Meeting Audio Recorder - Einrichtungsassistent"
echo "================================================"
echo ""

# Step 1: Check dependencies
echo "Schritt 1/4: Abhängigkeiten prüfen..."
echo ""

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "  [FEHLT] ffmpeg"
  read -r -p "  Soll ffmpeg installiert werden? [j/N] " response
  case "$response" in
    [jJ][aA]|[yY][eE][sS]|[jJ])
      echo "  Installiere ffmpeg..."
      brew install ffmpeg || {
        echo "  FEHLER: Konnte ffmpeg nicht installieren!"
        echo "  Installieren Sie ffmpeg manuell: brew install ffmpeg"
        exit 1
      }
      ;;
    *)
      echo "  ffmpeg ist erforderlich. Installieren Sie es mit: brew install ffmpeg"
      exit 1
      ;;
  esac
else
  echo "  [OK] ffmpeg: $(ffmpeg -version 2>&1 | head -1)"
fi

# Step 2: Check BlackHole
echo ""
echo "Schritt 2/4: BlackHole 2ch prüfen..."
echo ""

if extract_audio_device_names | grep -q "BlackHole 2ch"; then
  echo "  [OK] BlackHole 2ch gefunden"
else
  echo "  [FEHLT] BlackHole 2ch"
  echo ""
  echo "  BlackHole 2ch ist erforderlich für die Audio-Aufzeichnung."
  echo ""
  echo "  Installationsoptionen:"
  echo "  1) Download von: https://existential.audio/blackhole/"
  echo "  2) Via Homebrew: brew install --cask blackhole-2ch"
  echo ""
  read -r -p "  Haben Sie BlackHole 2ch installiert? [j/N] " response
  case "$response" in
    [jJ][aA]|[yY][eE][sS]|[jJ])
      # Try again
      if extract_audio_device_names | grep -q "BlackHole 2ch"; then
        echo "  [OK] BlackHole 2ch jetzt gefunden"
      else
        echo "  FEHLER: BlackHole 2ch immer noch nicht gefunden!"
        echo "  Bitte installieren Sie es und starten Sie den Setup neu."
        exit 1
      fi
      ;;
    *)
      echo "  BlackHole 2ch ist erforderlich. Bitte installieren Sie es."
      exit 1
      ;;
  esac
fi

# Step 3: Configure microphone
echo ""
echo "Schritt 3/4: Mikrofon konfigurieren..."
echo ""

echo "  Verfügbare Audio-Geräte:"
local count=1
local devices
while IFS= read -r device; do
  devices[$count]="$device"
  echo "    $count) $device"
  count=$((count + 1))
done < <(extract_audio_device_names)

echo ""
if [[ ${#devices[@]} -gt 0 ]]; then
  read -r -p "  Wählen Sie Ihr Mikrofon (Nummer, Standard: 2 für MacBook Pro Microphone): " choice
  if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#devices[@]} ]]; then
    MIC_DEVICE="${devices[$choice]}"
    echo "  Mikrofon gesetzt auf: $MIC_DEVICE"
  else
    MIC_DEVICE="MacBook Pro Microphone"
    echo "  Mikrofon gesetzt auf Standard: $MIC_DEVICE"
  fi
else
  MIC_DEVICE="MacBook Pro Microphone"
  echo "  Keine Geräte gefunden. Standard verwendet: $MIC_DEVICE"
fi

# Step 4: Create config file
echo ""
echo "Schritt 4/4: Konfiguration speichern..."
echo ""

# Get project root absolute path
ABS_PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

cat > "$ABS_PROJECT_ROOT/config.env" <<EOF
# Meeting Audio Recorder Configuration
# Automatisch generiert: $(date)

# Audio Geräte
BLACKHOLE_DEVICE="BlackHole 2ch"
MIC_DEVICE="$MIC_DEVICE"

# Ausgabe Einstellungen
OUTPUT_DIR="$ABS_PROJECT_ROOT/recordings"

# Audio Parameter
SAMPLE_RATE="48000"
BITRATE="192k"
AUDIO_CODEC="aac"
CONTAINER_FORMAT="m4a"
EOF

echo "  [OK] Konfiguration gespeichert in: $ABS_PROJECT_ROOT/config.env"

# Create output directory
mkdir -p "$ABS_PROJECT_ROOT/recordings"
echo "  [OK] Ausgabeordner erstellt: $ABS_PROJECT_ROOT/recordings"

echo ""
echo "================================================"
echo "  Einrichtung abgeschlossen!"
echo "================================================"
echo ""
echo "Nächste Schritte:"
echo ""
echo "1. Richten Sie Ihr Audio-MIDI-Setup ein (siehe README.md):"
echo "   - Erstellen Sie ein Multi-Output Device mit BlackHole 2ch"
echo "   - Setzen Sie dies als Standard-Ausgabegerät"
echo ""
echo "2. Testen Sie die Einrichtung:"
echo "   $(basename "$0") check"
echo ""
echo "3. Starten Sie eine Aufnahme:"
echo "   ./scripts/record.sh start-a    (nur Systemaudio)"
echo "   ./scripts/record.sh start-b    (Systemaudio + Mikrofon)"
echo ""
echo "4. Oder verwenden Sie das interaktive Menü:"
echo "   ./scripts/record.sh"
echo ""
