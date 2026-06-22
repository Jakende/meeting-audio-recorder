#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

show_banner

echo "=== Systemprüfung für Meeting Audio Recorder ==="
echo ""

# Test 1: ffmpeg
log_info "Test 1: Prüfe ffmpeg..."
if command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
  version="$("$FFMPEG_BIN" -version 2>&1 | head -1)"
  log_info "OK: ffmpeg gefunden: $version"
else
  log_error "FEHLER: ffmpeg nicht gefunden!"
  echo ""
  echo "Installationshinweis:"
  echo "  brew install ffmpeg"
  exit 1
fi

# Test 2: BlackHole device
log_info "Test 2: Prüfe BlackHole Gerät..."
if extract_audio_device_names | grep -Fx "$BLACKHOLE_DEVICE" >/dev/null 2>&1; then
  log_info "OK: BlackHole Gerät gefunden: $BLACKHOLE_DEVICE"
else
  log_error "FEHLER: BlackHole Gerät nicht gefunden: $BLACKHOLE_DEVICE"
  echo ""
  echo "Verfügbare Audio-Geräte:"
  extract_audio_device_names
  echo ""
  echo "Hinweis: Installieren Sie BlackHole 2ch:"
  echo "  https://existential.audio/blackhole/"
  exit 1
fi

# Test 3: Microphone device
log_info "Test 3: Prüfe Mikrofon-Gerät..."
if extract_audio_device_names | grep -Fx "$MIC_DEVICE" >/dev/null 2>&1; then
  log_info "OK: Mikrofon gefunden: $MIC_DEVICE"
else
  log_warn "WARNUNG: Mikrofon nicht gefunden: $MIC_DEVICE"
  echo ""
  echo "Verfügbare Audio-Geräte:"
  extract_audio_device_names
  echo ""
  echo "Setzen Sie MIC_DEVICE Umgebungsvariable oder bearbeiten Sie config.env"
fi

# Test 4: Output directory
log_info "Test 4: Prüfe Ausgabeordner..."
if [[ -d "$OUTPUT_DIR" ]]; then
  log_info "OK: Ausgabeordner existiert: $OUTPUT_DIR"
else
  mkdir -p "$OUTPUT_DIR"
  log_info "OK: Ausgabeordner erstellt: $OUTPUT_DIR"
fi

# Test 5: Write permissions
echo "" > "$OUTPUT_DIR/.write_test" 2>/dev/null && rm -f "$OUTPUT_DIR/.write_test"
if [[ $? -eq 0 ]]; then
  log_info "OK: Schreibrechte für Ausgabeordner vorhanden"
else
  log_error "FEHLER: Keine Schreibrechte für: $OUTPUT_DIR"
  exit 1
fi

# Test 6: ffmpeg can see devices
log_info "Test 5: Prüfe ffmpeg Gerätezugriff..."
if list_audio_devices_raw | grep -q "AVFoundation audio devices"; then
  log_info "OK: ffmpeg kann Audio-Geräte zugreifen"
else
  log_error "FEHLER: ffmpeg kann keine Audio-Geräte finden"
  exit 1
fi

# Summary
echo ""
log_info "=========================================="
log_info "Alle Prüfungen erfolgreich!"
log_info "=========================================="
echo ""
echo "System ist bereit für Aufnahmen."
echo ""
echo "Konfiguration:"
echo "  BlackHole: $BLACKHOLE_DEVICE"
echo "  Mikrofon: $MIC_DEVICE"
echo "  Ausgabe: $OUTPUT_DIR"
echo "  Sample Rate: $SAMPLE_RATE Hz"
echo "  Bitrate: $BITRATE"
echo "  Codec: $AUDIO_CODEC"
echo "  Format: $CONTAINER_FORMAT"
echo ""
echo "Starten Sie eine Aufnahme mit:"
echo "  ./scripts/record.sh start-a    (nur Systemaudio)"
echo "  ./scripts/record.sh start-b    (Systemaudio + Mikrofon)"
echo ""
