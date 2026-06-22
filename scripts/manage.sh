#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

ACTION="${1:-list}"

show_help() {
  cat <<EOF
Verwendung: $(basename "$0") [ACTION]

Aktionen:
  list          - Liste alle Aufnahmen
  clean [TAGE]  - Lösche alte Aufnahmen (Standard: 30 Tage)
  info FILE     - Zeige Information zu einer Aufnahme
  open          - Öffne den Aufnahmen-Ordner
  help          - Diese Hilfe anzeigen

Beispiele:
  $(basename "$0") list                          # Alle Aufnahmen auflisten
  $(basename "$0") clean                         # Alte Aufnahmen löschen (30 Tage)
  $(basename "$0") clean 7                      # Aufnahmen älter als 7 Tage löschen
  $(basename "$0") info recordings/meeting_20240101_1200.m4a
  $(basename "$0") open                          # Aufnahmen-Ordner öffnen
EOF
}

do_list() {
  echo "=== Alle Aufnahmen in $OUTPUT_DIR ==="
  echo ""
  
  local count=0
  if [[ -d "$OUTPUT_DIR" ]]; then
    for file in "$OUTPUT_DIR"/*.m4a "$OUTPUT_DIR"/*.mp3 "$OUTPUT_DIR"/*.wav "$OUTPUT_DIR"/*.aac; do
      if [[ -f "$file" ]]; then
        local size
        size="$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)"
        local size_human
        if [[ "$size" -gt 1048576 ]]; then
          size_human="$(echo "scale=2; $size/1048576" | bc) MB"
        elif [[ "$size" -gt 1024 ]]; then
          size_human="$(echo "scale=2; $size/1024" | bc) KB"
        else
          size_human="$size B"
        fi
        
        local mtime
        mtime="$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null || stat -c %y "$file" 2>/dev/null | cut -d'.' -f1)"
        
        local duration
        duration="$(get_audio_duration "$file")"
        
        printf "  %-40s %10s %s\n" "$(basename "$file")" "$size_human" "$mtime"
        count=$((count + 1))
      fi
    done
  fi
  
  if [[ $count -eq 0 ]]; then
    echo "  Keine Aufnahmen gefunden."
  else
    echo ""
    echo "Gesamt: $count Dateien"
    echo "Gesamtgröße: $(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)"
  fi
}

get_audio_duration() {
  local file="$1"
  local duration
  duration="$("$FFMPEG_BIN" -i "$file" 2>&1 | grep Duration | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)"
  if [[ -z "$duration" ]]; then
    echo "N/A"
  else
    echo "$duration"
  fi
}

do_clean() {
  local days="${1:-30}"
  echo "Lösche Aufnahmen älter als $days Tage aus $OUTPUT_DIR..."
  echo ""
  
  cleanup_old_recordings "$days"
  
  echo ""
  do_list
}

do_info() {
  local file="${1:-}"
  
  if [[ ! -f "$file" ]]; then
    log_error "Datei nicht gefunden: $file"
    exit 1
  fi
  
  echo "=== Informationen zu: $file ==="
  echo ""
  
  local size
  size="$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)"
  echo "Größe: $(echo "scale=2; $size/1048576" | bc) MB"
  
  local mtime
  mtime="$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$file" 2>/dev/null || stat -c %y "$file" 2>/dev/null | cut -d'.' -f1)"
  echo "Erstellt: $mtime"
  
  local duration
  duration="$(get_audio_duration "$file")"
  echo "Dauer: $duration"
  
  echo ""
  echo "ffmpeg Info:"
  "$FFMPEG_BIN" -i "$file" 2>&1 | grep -E "Duration|Stream|Audio|Video|Bitrate" || true
}

do_open() {
  if [[ -d "$OUTPUT_DIR" ]]; then
    echo "Öffne $OUTPUT_DIR"
    open "$OUTPUT_DIR" 2>/dev/null || xdg-open "$OUTPUT_DIR" 2>/dev/null || echo "Kann Ordner nicht öffnen: $OUTPUT_DIR"
  else
    log_error "Ausgabeordner nicht gefunden: $OUTPUT_DIR"
    exit 1
  fi
}

# Main
case "$ACTION" in
  list|l)
    do_list
    ;;
  clean|c)
    shift
    do_clean "${1:-30}"
    ;;
  info|i)
    shift
    do_info "$1"
    ;;
  open|o)
    do_open
    ;;
  help|--help|-h|h)
    show_help
    ;;
  *)
    show_help
    ;;
esac
