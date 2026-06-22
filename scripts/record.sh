#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

# Parse command line arguments
ACTION="${1:-menu}"

show_help() {
  cat <<EOF
Verwendung: $(basename "$0") [ACTION]

Aktionen:
  start-a          - Starte Aufnahme Variante A (nur Systemaudio)
  start-b          - Starte Aufnahme Variante B (Systemaudio + Mikrofon)
  stop             - Stoppe aktuelle Aufnahme
  status           - Zeige Status der aktuellen Aufnahme
  list             - Liste alle Aufnahmen
  clean [TAGE]     - Lösche alte Aufnahmen (Standard: 30 Tage)
  check            - Überprüfe Systemeinrichtung
  config           - Zeige/Speichere Konfiguration
  devices          - Liste verfügbare Audio-Geräte
  help             - Diese Hilfe anzeigen
  menu             - Interaktives Menü (Standard)

Umgebungsvariablen:
  BLACKHOLE_DEVICE - Name des BlackHole-Geräts (Standard: BlackHole 2ch)
  MIC_DEVICE       - Name des Mikrofon-Geräts (Standard: MacBook Pro Microphone)
  OUTPUT_DIR       - Zielordner für Aufnahmen (Standard: ./recordings)
  SAMPLE_RATE      - Abtrastrate (Standard: 48000)
  BITRATE          - Bitrate (Standard: 192k)

Beispiele:
  $(basename "$0") start-a                                    # Variante A starten
  $(basename "$0") start-b                                    # Variante B starten
  MIC_DEVICE="External Mic" $(basename "$0") start-b          # Variante B mit andere Mikrofon
  $(basename "$0") stop                                      # Aktuelle Aufnahme stoppen
  $(basename "$0") list                                      # Aufnahmen auflisten
EOF
}

show_status() {
  echo "=== Aufnahme-Status ==="
  if is_recording; then
    local pid
    pid="$(get_pid)"
    echo "Status: LAEUFT"
    echo "PID: $pid"
    echo "Laufzeit: $(ps -p "$pid" -o etimes= 2>/dev/null || echo "unbekannt") Sekunden"
    
    # Try to get recording info from ffmpeg process
    local ffmpeg_cmd
    ffmpeg_cmd="$(ps -p "$pid" -o args= 2>/dev/null | grep ffmpeg | head -1)"
    if [[ -n "$ffmpeg_cmd" ]]; then
      echo "Befehl: $ffmpeg_cmd"
    fi
  else
    echo "Status: KEINE AKTIVE AUFNAHME"
    if [[ -f "$PID_FILE" ]]; then
      echo "WARNUNG: PID-Datei existiert aber Prozess läuft nicht!"
    fi
  fi
  echo ""
  
  # Show recent recordings
  echo "=== Letzte Aufnahmen ==="
  list_recordings | tail -5 || echo "Keine Aufnahmen gefunden"
}

start_variant_a() {
  require_command "$FFMPEG_BIN"
  require_audio_device "$BLACKHOLE_DEVICE"
  
  if is_recording; then
    log_error "Eine Aufnahme läuft bereits! (PID: $(get_pid))"
    echo "Stoppen mit: $(basename "$0") stop"
    exit 1
  fi
  
  OUTFILE="$(meeting_output_file)"
  print_run_header "Starte Variante A: nur Systemaudio über '$BLACKHOLE_DEVICE'" "$OUTFILE"
  
  log_info "Starting recording (Variant A): $OUTFILE"
  
  # Build ffmpeg command with speed correction
  local cmd=(
    "$FFMPEG_BIN"
    -hide_banner
    -nostdin
    -loglevel
    warning
    -f
    avfoundation
    -thread_queue_size
    512
    -use_wallclock_as_timestamps
    1
    -i
    ":$BLACKHOLE_DEVICE"
    -vn
    -ar
    "$SAMPLE_RATE"
    -ac
    2
    -async
    1
    -c:a
    "$AUDIO_CODEC"
    -b:a
    "$BITRATE"
    -y
    "$OUTFILE"
  )
  
  echo "Stoppen mit Ctrl+C oder: $(basename "$0") stop"
  echo ""
  
  # Save PID
  save_pid
  
  # Execute
  exec "${cmd[@]}"
}

start_variant_b() {
  require_command "$FFMPEG_BIN"
  require_audio_device "$BLACKHOLE_DEVICE"
  require_audio_device "$MIC_DEVICE"
  
  if is_recording; then
    log_error "Eine Aufnahme läuft bereits! (PID: $(get_pid))"
    echo "Stoppen mit: $(basename "$0") stop"
    exit 1
  fi
  
  OUTFILE="$(meeting_output_file)"
  print_run_header "Starte Variante B: Systemaudio '$BLACKHOLE_DEVICE' + Mikrofon '$MIC_DEVICE'" "$OUTFILE"
  
  log_info "Starting recording (Variant B): $OUTFILE"
  
  # Build ffmpeg command with mixing and speed correction
  local cmd=(
    "$FFMPEG_BIN"
    -hide_banner
    -nostdin
    -loglevel
    warning
    -f
    avfoundation
    -thread_queue_size
    512
    -use_wallclock_as_timestamps
    1
    -i
    ":$BLACKHOLE_DEVICE"
    -f
    avfoundation
    -thread_queue_size
    512
    -use_wallclock_as_timestamps
    1
    -i
    ":$MIC_DEVICE"
    -filter_complex
    "[0:a]aresample=async=1:first_pts=0[a1];[1:a]aresample=async=1:first_pts=0[a2];[a1][a2]amix=inputs=2:duration=longest:dropout_transition=2,volume=2[a]"
    -map
    "[a]"
    -vn
    -ar
    "$SAMPLE_RATE"
    -ac
    2
    -async
    1
    -c:a
    "$AUDIO_CODEC"
    -b:a
    "$BITRATE"
    -y
    "$OUTFILE"
  )
  
  echo "Stoppen mit Ctrl+C oder: $(basename "$0") stop"
  echo ""
  
  # Save PID
  save_pid
  
  # Execute
  exec "${cmd[@]}"
}

do_stop() {
  if stop_recording; then
    echo "Aufnahme erfolgreich gestoppt."
  else
    echo "Keine aktive Aufnahme zum Stoppen gefunden."
  fi
}

do_list() {
  echo "=== Alle Aufnahmen ==="
  list_recordings
  echo ""
  echo "Gesamt: $(list_recordings | wc -l | tr -d ' ') Dateien"
}

do_clean() {
  local days="${1:-30}"
  echo "Lösche Aufnahmen älter als $days Tage..."
  cleanup_old_recordings "$days"
}

do_check() {
  echo "=== Systemprüfung ==="
  validate_setup
  local result=$?
  
  if [[ $result -eq 0 ]]; then
    echo ""
    log_info "Alle Prüfungen erfolgreich!"
    
    echo ""
    echo "Verfügbare Audio-Geräte:"
    extract_audio_device_names
    
    echo ""
    echo "Konfiguration:"
    echo "  BlackHole: $BLACKHOLE_DEVICE"
    echo "  Mikrofon: $MIC_DEVICE"
    echo "  Ausgabeordner: $OUTPUT_DIR"
    echo "  Sample Rate: $SAMPLE_RATE Hz"
    echo "  Bitrate: $BITRATE"
  else
    log_error "Systemprüfung fehlgeschlagen!"
    exit 1
  fi
}

do_config() {
  echo "=== Aktuelle Konfiguration ==="
  echo "BLACKHOLE_DEVICE: $BLACKHOLE_DEVICE"
  echo "MIC_DEVICE: $MIC_DEVICE"
  echo "OUTPUT_DIR: $OUTPUT_DIR"
  echo "SAMPLE_RATE: $SAMPLE_RATE"
  echo "BITRATE: $BITRATE"
  echo "AUDIO_CODEC: $AUDIO_CODEC"
  echo "CONTAINER_FORMAT: $CONTAINER_FORMAT"
  echo ""
  
  read -r -p "Konfiguration speichern? [j/N] " response
  case "$response" in
    [jJ][aA]|[yY][eE][sS]|[jJ])
      save_config
      echo "Konfiguration gespeichert in $CONFIG_FILE"
      ;;
    *)
      echo "Konfiguration nicht gespeichert."
      ;;
  esac
}

do_devices() {
  echo "=== Verfügbare Audio-Geräte ==="
  list_audio_devices_clean
  echo ""
  echo "=== Audio-Geräte (Namen) ==="
  extract_audio_device_names
}

# Interactive menu
show_menu() {
  while true; do
    clear
    show_banner
    show_status
    
    cat <<EOF
Hauptmenü:
----------
  1) Aufnahme starten (Variante A - nur Systemaudio)
  2) Aufnahme starten (Variante B - Systemaudio + Mikrofon)
  3) Aufnahme stoppen
  4) Aufnahmen anzeigen
  5) Alte Aufnahmen bereinigen
  6) Systemprüfung
  7) Konfiguration anzeigen/speichern
  8) Audio-Geräte anzeigen
  
  h) Hilfe
  q) Beenden

Auswahl: 
EOF
    
    read -r choice
    
    case "$choice" in
      1)
        start_variant_a
        ;;
      2)
        start_variant_b
        ;;
      3)
        do_stop
        ;;
      4)
        do_list
        ;;
      5)
        read -r -p "Tage (Standard: 30): " days
        do_clean "${days:-30}"
        ;;
      6)
        do_check
        ;;
      7)
        do_config
        ;;
      8)
        do_devices
        ;;
      h)
        show_help
        ;;
      q)
        echo "Auf Wiedersehen!"
        exit 0
        ;;
      *)
        echo "Ungültige Auswahl!"
        ;;
    esac
    
    read -r -p "Drücken Sie ENTER zum Fortfahren..." _
  done
}

# Main
case "$ACTION" in
  start-a|start_a|a)
    start_variant_a
    ;;
  start-b|start_b|b)
    start_variant_b
    ;;
  stop|s)
    do_stop
    ;;
  status|st)
    show_status
    ;;
  list|l)
    do_list
    ;;
  clean|c)
    shift
    do_clean "${1:-30}"
    ;;
  check|chk)
    do_check
    ;;
  config|conf|cfg)
    do_config
    ;;
  devices|dev|d)
    do_devices
    ;;
  help|--help|-h|h)
    show_help
    ;;
  menu|m|*)
    show_menu
    ;;
esac
