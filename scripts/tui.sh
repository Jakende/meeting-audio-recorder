#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

# Clear screen
clear

# Global variable for recording PID
RECORDING_PID=""

# ============================================================================
# DISPLAY FUNCTIONS
# ============================================================================

draw_header() {
  echo "=============================================="
  echo "  MEETING AUDIO RECORDER"
  echo "  Terminal User Interface"
  echo "=============================================="
  echo ""
}

draw_footer() {
  echo ""
  echo "----------------------------------------------"
  echo "  q = Zurueck    h = Hilfe    x = Beenden"
  echo "=============================================="
}

draw_separator() {
  echo "----------------------------------------------"
}

draw_menu() {
  local title="$1"
  echo ""
  echo ":: $title"
  draw_separator
}

draw_menu_item() {
  local num="$1"
  local text="$2"
  printf "  %2d) %s\n" "$num" "$text"
}

draw_status_indicator() {
  if is_recording; then
    echo " [LAEUFT - PID: $(get_pid)]"
  else
    echo " [STOPPED]"
  fi
}

# ============================================================================
# RECORDING FUNCTIONS
# ============================================================================

start_recording_variant_a() {
  require_command "$FFMPEG_BIN"
  require_audio_device "$BLACKHOLE_DEVICE"
  
  if is_recording; then
    show_message "Fehler" "Eine Aufnahme laeuft bereits! (PID: $(get_pid))"
    return 1
  fi
  
  OUTFILE="$(meeting_output_file)"
  
  log_info "Starting recording (Variant A - Speed Corrected): $OUTFILE"
  
  # Use -async 1 and explicit sample rate to prevent speed issues
  # Also use -use_wallclock_as_timestamps 1 for better timing
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
  
  echo "Start: Variante A (Systemaudio)"
  echo "Ausgabe: $OUTFILE"
  echo "Stoppen mit: STRG+C oder im Menue 'Stop'"
  echo ""
  
  save_pid
  exec "${cmd[@]}"
}

start_recording_variant_b() {
  require_command "$FFMPEG_BIN"
  require_audio_device "$BLACKHOLE_DEVICE"
  require_audio_device "$MIC_DEVICE"
  
  if is_recording; then
    show_message "Fehler" "Eine Aufnahme laeuft bereits! (PID: $(get_pid))"
    return 1
  fi
  
  OUTFILE="$(meeting_output_file)"
  
  log_info "Starting recording (Variant B - Speed Corrected): $OUTFILE"
  
  # Use -async 1 on both inputs and amix with normalize=0 to prevent clipping
  # -use_wallclock_as_timestamps 1 for both inputs
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
  
  echo "Start: Variante B (Systemaudio + Mikrofon)"
  echo "BlackHole: $BLACKHOLE_DEVICE"
  echo "Mikrofon: $MIC_DEVICE"
  echo "Ausgabe: $OUTFILE"
  echo "Stoppen mit: STRG+C oder im Menue 'Stop'"
  echo ""
  
  save_pid
  exec "${cmd[@]}"
}

stop_recording_tui() {
  if is_recording; then
    local pid
    pid="$(get_pid)"
    echo "Stoppe Aufnahme (PID: $pid)..."
    if stop_recording; then
      show_message "Erfolg" "Aufnahme gestoppt."
    else
      show_message "Fehler" "Konnte Aufnahme nicht stoppen."
    fi
  else
    show_message "Info" "Keine aktive Aufnahme."
  fi
}

# ============================================================================
# SPEED CALIBRATION FUNCTIONS
# ============================================================================

show_speed_test_menu() {
  while true; do
    clear
    draw_header
    draw_menu "GESCHWINDIGKEITS-TEST UND KALIBRIERUNG"
    echo ""
    echo "  Waehlen Sie einen Test:"
    draw_menu_item 1 "Testaufnahme starten (5 Sekunden)"
    draw_menu_item 2 "Geschwindigkeit analysieren"
    draw_menu_item 3 "Sample-Rate anpassen"
    draw_menu_item 4 " Zurueck"
    draw_separator
    draw_status_indicator
    draw_footer
    
    read -r -s -n 1 choice
    echo ""
    
    case "$choice" in
      1) speed_test_record;;
      2) speed_analyze;;
      3) adjust_sample_rate;;
      4) return;;
      q) return;;
      h) show_help "speed";;
      x) exit 0;;
      *) show_message "Fehler" "Ungueltige Auswahl";;
    esac
    
    read -r -p "Druecken Sie ENTER zum Fortfahren..." _
  done
}

speed_test_record() {
  local test_file="$OUTPUT_DIR/speed_test_$$_$(date +%Y%m%d_%H%M%S).wav"
  
  echo "Starte Testaufnahme (5 Sekunden)..."
  echo "Warten Sie, bis die Aufnahme automatisch stoppt..."
  echo ""
  
  # Record for exactly 5 seconds using ffmpeg with timeout
  timeout 5 "$FFMPEG_BIN" -hide_banner -nostdin -loglevel error \
    -f avfoundation -use_wallclock_as_timestamps 1 -i ":$BLACKHOLE_DEVICE" \
    -vn -ar 48000 -ac 2 -c:a pcm_s16le \
    -y "$test_file" 2>/dev/null || true
  
  if [[ -f "$test_file" ]]; then
    local actual_duration
    actual_duration="$($FFMPEG_BIN -i "$test_file" 2>&1 | grep Duration | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    local expected_duration="5.00"
    local file_size
    file_size="$(stat -f %z "$test_file" 2>/dev/null || stat -c %s "$test_file" 2>/dev/null)"
    
    echo "Testaufnahme erstellt: $test_file"
    echo "Erwartete Daeur: 5.00 Sekunden"
    echo "Tatsaechliche Daeur: ${actual_duration:-N/A} Sekunden"
    echo "Dateigroesse: $(echo "scale=2; $file_size/1024/1024" | bc) MB"
    echo ""
    
    # Calculate speed factor
    if [[ -n "$actual_duration" ]]; then
      local speed_factor
      speed_factor="$(echo "scale=4; $expected_duration / $actual_duration" | bc)"
      echo "Geschwindigkeitsfaktor: $speed_factor"
      
      if [[ $(echo "$speed_factor > 1.02" | bc) -eq 1 ]]; then
        echo "WARNUNG: Aufnahme ist zu SCHNELL (Faktor > 1.00)"
      elif [[ $(echo "$speed_factor < 0.98" | bc) -eq 1 ]]; then
        echo "WARNUNG: Aufnahme ist zu LANGSAM (Faktor < 1.00)"
      else
        echo "OK: Geschwindigkeit ist normal (Faktor ~1.00)"
      fi
    fi
    
    # Offer to keep or delete the test file
    read -r -p "Testdatei behalten? [j/N] " keep
    if [[ ! "$keep" =~ ^[jJ][aA]?$ ]]; then
      rm -f "$test_file"
      echo "Testdatei geloescht."
    fi
  else
    show_message "Fehler" "Testaufnahme fehlgeschlagen. Pruefen Sie die Geräte."
  fi
}

speed_analyze() {
  echo "Analysiere Aufnahme-Geschwindigkeit..."
  echo ""
  
  # Check if there are recordings
  local recordings
  recordings="$(list_recordings)"
  
  if [[ -z "$recordings" || "$recordings" == *"Keine Aufnahmen gefunden"* ]]; then
    show_message "Info" "Keine Aufnahmen zum Analysieren gefunden."
    return
  fi
  
  echo "Verfuegbare Aufnahmen:"
  local count=1
  local files=()
  while IFS= read -r file; do
    if [[ -f "$file" ]]; then
      files["$count"]="$file"
      printf "  %2d) %s\n" "$count" "$(basename "$file")"
      count=$((count + 1))
    fi
  done <<< "$recordings"
  
  echo ""
  read -r -p "Waehlen Sie eine Aufnahme (Nummer): " choice
  
  if [[ -n "$choice" && "$choice" =~ ^[0-9]+$ && "$choice" -ge 1 && "$choice" -le ${#files[@]} ]]; then
    local selected_file="${files[$choice]}"
    local expected_duration
    local actual_duration
    
    # Extract expected duration from filename if possible
    # meeting_20260621_1200.m4a doesn't have duration, so we estimate
    actual_duration="$($FFMPEG_BIN -i "$selected_file" 2>&1 | grep Duration | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)"
    
    if [[ -n "$actual_duration" ]]; then
      echo ""
      echo "Analyse von: $(basename "$selected_file")"
      echo "Tatsaechliche Daeur: $actual_duration"
      
      # Parse HH:MM:SS to seconds
      local hours="${actual_duration:0:2}"
      local minutes="${actual_duration:3:2}"
      local seconds="${actual_duration:6:2}"
      local total_seconds=$((hours * 3600 + minutes * 60 + seconds))
      
      echo "In Sekunden: $total_seconds"
      
      # Get file modification time
      local mtime
      mtime="$(stat -f %Sm -t "%Y-%m-%d %H:%M:%S" "$selected_file" 2>/dev/null || date -r "$selected_file" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)"
      echo "Erstellt: $mtime"
      
      # Calculate expected duration based on creation time
      local now
      now="$(date +%s)"
      local create_time
      create_time="$(date -j -f "%Y-%m-%d %H:%M:%S" "$mtime" +%s 2>/dev/null || date -d "$mtime" +%s 2>/dev/null)"
      
      if [[ -n "$create_time" ]]; then
        local elapsed=$((now - create_time))
        local speed_ratio
        speed_ratio="$(echo "scale=4; $elapsed / $total_seconds" | bc)"
        
        echo ""
        echo "Verstrichene Zeit seit Erstellung: $elapsed Sekunden"
        echo "Geschwindigkeitsverhaeltnis: $speed_ratio"
        
        if [[ $(echo "$speed_ratio > 1.05" | bc) -eq 1 ]]; then
          echo ""
          echo "DIAGNOSE: Aufnahme ist zu SCHNELL"
          echo "Moegliche Ursachen:"
          echo "  - Falsche Clock Source in Audio-MIDI-Setup"
          echo "  - Drift Correction nicht aktiviert"
          echo "  - Sample Rate Mismatch"
          echo ""
          echo "Empfohlene Loesung:"
          echo "  1. Setzen Sie Clock Source auf das physische Geraet"
          echo "  2. Aktivieren Sie Drift Correction auf BlackHole 2ch"
          echo "  3. Deaktivieren Sie Drift Correction auf dem Clock Source"
          echo "  4. Verwenden Sie -use_wallclock_as_timestamps 1 in ffmpeg"
        elif [[ $(echo "$speed_ratio < 0.95" | bc) -eq 1 ]]; then
          echo ""
          echo "DIAGNOSE: Aufnahme ist zu LANGSAM"
        else
          echo ""
          echo "DIAGNOSE: Geschwindigkeit ist NORMAL"
        fi
      fi
    fi
  fi
}

adjust_sample_rate() {
  echo "Sample-Rate Anpassung"
  echo ""
  echo "Aktuelle Sample-Rate: $SAMPLE_RATE Hz"
  echo ""
  echo "Verfuegbare Optionen:"
  echo "  1) 44100 Hz (CD-Qualitaet)"
  echo "  2) 48000 Hz (Standard, empfohlen)"
  echo "  3) 96000 Hz (Hochaufloesend)"
  echo "  4) Benutzerdefiniert"
  echo ""
  
  read -r -p "Waehlen Sie eine Sample-Rate (1-4): " choice
  
  case "$choice" in
    1) SAMPLE_RATE="44100";;
    2) SAMPLE_RATE="48000";;
    3) SAMPLE_RATE="96000";;
    4)
      read -r -p "Geben Sie Sample-Rate ein (z.B. 48000): " SAMPLE_RATE
      ;;
    *)
      show_message "Info" "Keine Aenderung."
      return
      ;;
  esac
  
  # Save to config
  sed -i '' "s/SAMPLE_RATE=.*/SAMPLE_RATE=\"$SAMPLE_RATE\"/" "$CONFIG_FILE" 2>/dev/null || \
  sed -i "s/SAMPLE_RATE=.*/SAMPLE_RATE=\"$SAMPLE_RATE\"/" "$CONFIG_FILE" 2>/dev/null || \
  echo "SAMPLE_RATE=\"$SAMPLE_RATE\"" >> "$CONFIG_FILE"
  
  show_message "Erfolg" "Sample-Rate auf $SAMPLE_RATE Hz gesetzt."
}

# ============================================================================
# MANAGEMENT FUNCTIONS
# ============================================================================

show_recordings_list() {
  echo "Aufnahmen-Verwaltung"
  echo ""
  
  local recordings
  recordings="$(list_recordings)"
  
  if [[ -z "$recordings" || "$recordings" == *"Keine Aufnahmen gefunden"* ]]; then
    show_message "Info" "Keine Aufnahmen gefunden."
    return
  fi
  
  echo "Verfuegbare Aufnahmen:"
  draw_separator
  local count=1
  local files=()
  
  while IFS= read -r file; do
    if [[ -f "$file" ]]; then
      files["$count"]="$file"
      local size
      size="$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)"
      local size_mb
      size_mb="$(echo "scale=2; $size/1024/1024" | bc)"
      local mtime
      mtime="$(stat -f %Sm -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null)"
      printf "  %2d) %-35s %7s MB   %s\n" "$count" "$(basename "$file")" "$size_mb" "$mtime"
      count=$((count + 1))
    fi
  done <<< "$recordings"
  
  echo ""
  draw_separator
  echo "  A) Alle loeschen"
  echo "  D) Alte loeschen (Standard: 30 Tage)"
  echo "  O) Ordner oeffnen"
  draw_separator
  
  read -r -p "Waehlen Sie eine Aktion (Nummer/A/D/O): " choice
  
  case "$choice" in
    [0-9]*)
      if [[ "$choice" -ge 1 && "$choice" -le ${#files[@]} ]]; then
        show_recording_actions "${files[$choice]}"
      fi
      ;;
    A|a)
      read -r -p "Alle Aufnahmen wirklich loeschen? [j/N] " confirm
      if [[ "$confirm" =~ ^[jJ][aA]?$ ]]; then
        rm -f "$OUTPUT_DIR"/*.m4a "$OUTPUT_DIR"/*.mp3 "$OUTPUT_DIR"/*.wav "$OUTPUT_DIR"/*.aac 2>/dev/null || true
        show_message "Erfolg" "Alle Aufnahmen geloescht."
      fi
      ;;
    D|d)
      read -r -p "Tage (Standard: 30): " days
      days="${days:-30}"
      cleanup_old_recordings "$days"
      show_message "Erfolg" "Aufnahmen aelter als $days Tage geloescht."
      ;;
    O|o)
      open "$OUTPUT_DIR" 2>/dev/null || xdg-open "$OUTPUT_DIR" 2>/dev/null || \
        show_message "Fehler" "Kann Ordner nicht oeffnen."
      ;;
    *) ;;
  esac
}

show_recording_actions() {
  local file="$1"
  
  while true; do
    clear
    draw_header
    draw_menu "AUFNAHME: $(basename "$file")"
    echo ""
    
    local size
    size="$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null)"
    local size_mb
    size_mb="$(echo "scale=2; $size/1024/1024" | bc)"
    local mtime
    mtime="$(stat -f %Sm -t "%Y-%m-%d %H:%M" "$file" 2>/dev/null || date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null)"
    local duration
    duration="$($FFMPEG_BIN -i "$file" 2>&1 | grep Duration | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)"
    
    echo "  Groesse: $size_mb MB"
    echo "  Erstellt: $mtime"
    echo "  Dauer: $duration"
    echo ""
    
    echo "  Aktionen:"
    draw_menu_item 1 "Abspielen"
    draw_menu_item 2 "Informationen anzeigen"
    draw_menu_item 3 "Umbenennen"
    draw_menu_item 4 "Loeschen"
    draw_menu_item 5 " Zurueck"
    draw_separator
    draw_footer
    
    read -r -s -n 1 choice
    echo ""
    
    case "$choice" in
      1) 
        echo "Spiele ab: $(basename "$file")"
        afplay "$file" 2>/dev/null || \
          show_message "Fehler" "afplay nicht veruegbar. Verwenden Sie: afplay $file"
        ;;
      2)
        echo "Informationen:"
        echo ""
        "$FFMPEG_BIN" -i "$file" 2>&1 | grep -E "Duration|Stream|Audio|Video|Bitrate|Sample"
        read -r -p "Druecken Sie ENTER..." _
        ;;
      3)
        read -r -p "Neuer Name (ohne Endung): " new_name
        if [[ -n "$new_name" ]]; then
          local dir
          dir="$(dirname "$file")"
          local ext
          ext="$(echo "$file" | rev | cut -d'.' -f1 | rev)"
          local new_file="$dir/$new_name.$ext"
          mv "$file" "$new_file"
          show_message "Erfolg" "Datei umbenannt zu: $(basename "$new_file")"
        fi
        ;;
      4)
        read -r -p "Wirklich loeschen? [j/N] " confirm
        if [[ "$confirm" =~ ^[jJ][aA]?$ ]]; then
          rm -f "$file"
          show_message "Erfolg" "Aufnahme geloescht."
          return
        fi
        ;;
      5) return ;;
      x) exit 0 ;;
      *) show_message "Fehler" "Ungueltige Auswahl" ;;
    esac
    
    read -r -p "Druecken Sie ENTER zum Fortfahren..." _
  done
}

show_config_menu() {
  while true; do
    clear
    draw_header
    draw_menu "KONFIGURATION"
    echo ""
    echo "  Aktuelle Einstellungen:"
    echo "  --------------------"
    printf "    %-20s: %s\n" "BlackHole" "$BLACKHOLE_DEVICE"
    printf "    %-20s: %s\n" "Mikrofon" "$MIC_DEVICE"
    printf "    %-20s: %s\n" "Ausgabe-Ordner" "$OUTPUT_DIR"
    printf "    %-20s: %s Hz\n" "Sample-Rate" "$SAMPLE_RATE"
    printf "    %-20s: %s\n" "Bitrate" "$BITRATE"
    printf "    %-20s: %s\n" "Codec" "$AUDIO_CODEC"
    printf "    %-20s: %s\n" "Format" "$CONTAINER_FORMAT"
    echo ""
    
    echo "  Aendern:"
    draw_menu_item 1 "BlackHole-Geraet"
    draw_menu_item 2 "Mikrofon-Geraet"
    draw_menu_item 3 "Ausgabe-Ordner"
    draw_menu_item 4 "Sample-Rate"
    draw_menu_item 5 "Bitrate"
    draw_menu_item 6 "Codec und Format"
    draw_menu_item 7 "Zurueck"
    draw_separator
    
    read -r -p "Waehlen Sie (1-7): " choice
    echo ""
    
    case "$choice" in
      1)
        echo "Verfuegbare Audio-Geraete:"
        local devices
        devices="$(extract_audio_device_names)"
        local count=1
        local dev_array=()
        echo ""
        while IFS= read -r device; do
          dev_array["$count"]="$device"
          printf "  %2d) %s\n" "$count" "$device"
          count=$((count + 1))
        done <<< "$devices"
        echo ""
        read -r -p "Waehlen Sie BlackHole-Geraet (Nummer): " dev_choice
        if [[ -n "$dev_choice" && "$dev_choice" =~ ^[0-9]+$ && "$dev_choice" -ge 1 && "$dev_choice" -le ${#dev_array[@]} ]]; then
          BLACKHOLE_DEVICE="${dev_array[$dev_choice]}"
          sed -i '' "s/BLACKHOLE_DEVICE=.*/BLACKHOLE_DEVICE=\"$BLACKHOLE_DEVICE\"/" "$CONFIG_FILE" 2>/dev/null || \
          sed -i "s/BLACKHOLE_DEVICE=.*/BLACKHOLE_DEVICE=\"$BLACKHOLE_DEVICE\"/" "$CONFIG_FILE" 2>/dev/null
          show_message "Erfolg" "BlackHole-Geraet auf $BLACKHOLE_DEVICE gesetzt."
        fi
        ;;
      2)
        echo "Verfuegbare Audio-Geraete:"
        local devices
        devices="$(extract_audio_device_names)"
        local count=1
        local dev_array=()
        echo ""
        while IFS= read -r device; do
          dev_array["$count"]="$device"
          printf "  %2d) %s\n" "$count" "$device"
          count=$((count + 1))
        done <<< "$devices"
        echo ""
        read -r -p "Waehlen Sie Mikrofon (Nummer): " dev_choice
        if [[ -n "$dev_choice" && "$dev_choice" =~ ^[0-9]+$ && "$dev_choice" -ge 1 && "$dev_choice" -le ${#dev_array[@]} ]]; then
          MIC_DEVICE="${dev_array[$dev_choice]}"
          sed -i '' "s/MIC_DEVICE=.*/MIC_DEVICE=\"$MIC_DEVICE\"/" "$CONFIG_FILE" 2>/dev/null || \
          sed -i "s/MIC_DEVICE=.*/MIC_DEVICE=\"$MIC_DEVICE\"/" "$CONFIG_FILE" 2>/dev/null
          show_message "Erfolg" "Mikrofon auf $MIC_DEVICE gesetzt."
        fi
        ;;
      3)
        read -r -p "Neuer Ausgabe-Ordner: " new_dir
        if [[ -n "$new_dir" ]]; then
          OUTPUT_DIR="$new_dir"
          mkdir -p "$OUTPUT_DIR"
          sed -i '' "s|OUTPUT_DIR=.*|OUTPUT_DIR=\"$OUTPUT_DIR\"|" "$CONFIG_FILE" 2>/dev/null || \
          sed -i "s|OUTPUT_DIR=.*|OUTPUT_DIR=\"$OUTPUT_DIR\"|" "$CONFIG_FILE" 2>/dev/null
          show_message "Erfolg" "Ausgabe-Ordner auf $OUTPUT_DIR gesetzt."
        fi
        ;;
      4) adjust_sample_rate ;;
      5)
        read -r -p "Neue Bitrate (z.B. 192k, 256k, 320k): " new_bitrate
        if [[ -n "$new_bitrate" ]]; then
          BITRATE="$new_bitrate"
          sed -i '' "s/BITRATE=.*/BITRATE=\"$BITRATE\"/" "$CONFIG_FILE" 2>/dev/null || \
          sed -i "s/BITRATE=.*/BITRATE=\"$BITRATE\"/" "$CONFIG_FILE" 2>/dev/null
          show_message "Erfolg" "Bitrate auf $BITRATE gesetzt."
        fi
        ;;
      6)
        echo "Codec und Format:"
        echo ""
        echo "Verfuegbare Codecs:"
        echo "  aac    - AAC (empfohlen, Standard)"
        echo "  libmp3lame - MP3"
        echo "  libopus - Opus"
        echo "  pcm_s16le - WAV (uncompressed)"
        echo ""
        read -r -p "Codec: " new_codec
        
        echo ""
        echo "Verfuegbare Formate:"
        echo "  m4a  - M4A Container (Standard)"
        echo "  mp3  - MP3"
        echo "  ogg  - OGG"
        echo "  wav  - WAV"
        echo ""
        read -r -p "Format: " new_format
        
        if [[ -n "$new_codec" && -n "$new_format" ]]; then
          AUDIO_CODEC="$new_codec"
          CONTAINER_FORMAT="$new_format"
          sed -i '' "s/AUDIO_CODEC=.*/AUDIO_CODEC=\"$AUDIO_CODEC\"/" "$CONFIG_FILE" 2>/dev/null || \
          sed -i "s/AUDIO_CODEC=.*/AUDIO_CODEC=\"$AUDIO_CODEC\"/" "$CONFIG_FILE" 2>/dev/null
          sed -i '' "s/CONTAINER_FORMAT=.*/CONTAINER_FORMAT=\"$CONTAINER_FORMAT\"/" "$CONFIG_FILE" 2>/dev/null || \
          sed -i "s/CONTAINER_FORMAT=.*/CONTAINER_FORMAT=\"$CONTAINER_FORMAT\"/" "$CONFIG_FILE" 2>/dev/null
          show_message "Erfolg" "Codec: $AUDIO_CODEC, Format: $CONTAINER_FORMAT"
        fi
        ;;
      7) return ;;
      x) exit 0 ;;
      *) show_message "Fehler" "Ungueltige Auswahl" ;;
    esac
    
    read -r -p "Druecken Sie ENTER zum Fortfahren..." _
  done
}

show_devices_menu() {
  while true; do
    clear
    draw_header
    draw_menu "AUDIO-GERAETE"
    echo ""
    
    echo "Verfuegbare Audio-Geraete:"
    draw_separator
    
    list_audio_devices_clean
    
    echo ""
    echo "Geräte-Namen (für Konfiguration):"
    draw_separator
    
    extract_audio_device_names
    
    draw_separator
    echo ""
    echo "  Aktuelle Auswahl:"
    echo "    BlackHole: $BLACKHOLE_DEVICE"
    echo "    Mikrofon: $MIC_DEVICE"
    echo ""
    
    read -r -p "Druecken Sie ENTER zum Zurueckkehren..." _
    return
  done
}

show_system_info() {
  clear
  draw_header
  draw_menu "SYSTEM-INFORMATIONEN"
  echo ""
  
  echo "  ffmpeg Version:"
  "$FFMPEG_BIN" -version 2>&1 | head -1
  echo ""
  
  echo "  Audio-Geraete:"
  draw_separator
  extract_audio_device_names
  echo ""
  
  echo "  System-Info:"
  draw_separator
  echo "    Benutzer: $(whoami)"
  echo "    Hostname: $(hostname)"
  echo "    OS: $(uname -srm)"
  echo ""
  
  echo "  Projekt-Info:"
  draw_separator
  echo "    Pfad: $PROJECT_ROOT"
  echo "    Konfig: $CONFIG_FILE"
  echo "    Log: $LOG_FILE"
  echo "    PID-Datei: $PID_FILE"
  echo ""
  
  read -r -p "Druecken Sie ENTER zum Fortfahren..." _
}

show_help() {
  local section="${1:-main}"
  
  clear
  draw_header
  draw_menu "HILFE"
  echo ""
  
  case "$section" in
    main)
      echo "  HAUPTMENUE:"
      echo ""
      echo "  1 - Aufnahme starten (Variante A)"
      echo "     Nur Systemaudio ueber BlackHole"
      echo ""
      echo "  2 - Aufnahme starten (Variante B)"
      echo "     Systemaudio + Mikrofon gemischt"
      echo ""
      echo "  3 - Aufnahme stoppen"
      echo "     Stoppt die aktuell laufende Aufnahme"
      echo ""
      echo "  4 - Aufnahmen verwalten"
      echo "     Liste, loesche oder benenne Aufnahmen"
      echo ""
      echo "  5 - Geschwindigkeit testen"
      echo "     Test und Kalibrierung fuer Geschwindigkeitsprobleme"
      echo ""
      echo "  6 - Konfiguration"
      echo "     Aendern Sie alle Einstellungen"
      echo ""
      echo "  7 - Geraete anzeigen"
      echo "     Zeigt alle verfuegbaren Audio-Geraete"
      echo ""
      echo "  8 - System-Info"
      echo "     Zeigt System- und Projektinformationen"
      echo ""
      ;;
    speed)
      echo "  GESCHWINDIGKEITS-TEST:"
      echo ""
      echo "  Problem: Aufnahmen laufen zu schnell oder zu langsam"
      echo ""
      echo "  Ursachen:"
      echo "    1. Falsche Clock Source in Audio-MIDI-Setup"
      echo "    2. Drift Correction nicht aktiviert"
      echo "    3. Sample Rate Mismatch zwischen Geraeten"
      echo ""
      echo "  Loesungen:"
      echo "    1. Clock Source auf physische Hardware setzen"
      echo "    2. Drift Correction auf Slaves aktivieren"
      echo "    3. -use_wallclock_as_timestamps 1 in ffmpeg"
      echo "    4. -async 1 Filter in ffmpeg"
      echo ""
      echo "  TUI integriert diese Fixes automatisch!"
      ;;
  esac
  
  echo ""
  read -r -p "Druecken Sie ENTER zum Fortfahren..." _
}

show_message() {
  local title="$1"
  local message="$2"
  
  clear
  draw_header
  echo ""
  echo "  [$title]"
  echo "  $(draw_separator)"
  echo "  $message"
  echo ""
  draw_separator
  echo ""
}

# ============================================================================
# MAIN MENU
# ============================================================================

main_menu() {
  while true; do
    clear
    draw_header
    draw_menu "HAUPTMENUE"
    
    echo ""
    echo "  Aufnahme-Status:"
    if is_recording; then
      echo "    [LAEUFT - PID: $(get_pid)]"
    else
      echo "    [STOPPED]"
    fi
    echo ""
    
    echo "  Waehlen Sie eine Aktion:"
    draw_menu_item 1 "Aufnahme starten (Variante A - Systemaudio)"
    draw_menu_item 2 "Aufnahme starten (Variante B - Systemaudio + Mikrofon)"
    draw_menu_item 3 "Aufnahme stoppen"
    draw_menu_item 4 "Aufnahmen verwalten"
    draw_menu_item 5 "Geschwindigkeit testen & kalibrieren"
    draw_menu_item 6 "Konfiguration"
    draw_menu_item 7 "Audio-Geraete anzeigen"
    draw_menu_item 8 "System-Informationen"
    
    draw_separator
    
    read -r -s -n 1 choice
    echo ""
    
    case "$choice" in
      1)
        clear
        draw_header
        draw_menu "VARIANTE A - NUR SYSTEMAUDIO"
        echo ""
        echo "  Geraet: $BLACKHOLE_DEVICE"
        echo "  Ausgabe: $OUTPUT_DIR"
        echo "  Sample-Rate: $SAMPLE_RATE Hz"
        echo "  Bitrate: $BITRATE"
        echo ""
        read -r -p "Starten? [j/N] " confirm
        if [[ "$confirm" =~ ^[jJ][aA]?$ ]]; then
          start_recording_variant_a
        fi
        ;;
      2)
        clear
        draw_header
        draw_menu "VARIANTE B - SYSTEMAUDIO + MIKROFON"
        echo ""
        echo "  BlackHole: $BLACKHOLE_DEVICE"
        echo "  Mikrofon: $MIC_DEVICE"
        echo "  Ausgabe: $OUTPUT_DIR"
        echo "  Sample-Rate: $SAMPLE_RATE Hz"
        echo "  Bitrate: $BITRATE"
        echo ""
        read -r -p "Starten? [j/N] " confirm
        if [[ "$confirm" =~ ^[jJ][aA]?$ ]]; then
          start_recording_variant_b
        fi
        ;;
      3)
        stop_recording_tui
        ;;
      4)
        show_recordings_list
        ;;
      5)
        show_speed_test_menu
        ;;
      6)
        show_config_menu
        ;;
      7)
        show_devices_menu
        ;;
      8)
        show_system_info
        ;;
      h)
        show_help "main"
        ;;
      x)
        clear
        echo "Auf Wiedersehen!"
        exit 0
        ;;
      q)
        # Continue to next iteration (back)
        ;;
      *)
        show_message "Fehler" "Ungueltige Auswahl. Versuchen Sie es erneut."
        ;;
    esac
    
    read -r -p "Druecken Sie ENTER zum Fortfahren..." _
  done
}

# ============================================================================
# START
# ============================================================================

# Check if setup is valid
if ! validate_setup >/dev/null 2>&1; then
  echo "WARNUNG: Systempruefung fehlgeschlagen!"
  echo "Fuehren Sie zuerst ./scripts/check.sh aus."
  read -r -p "Trotzdem fortfahren? [j/N] " continue_anyway
  if [[ ! "$continue_anyway" =~ ^[jJ][aA]?$ ]]; then
    exit 1
  fi
fi

# Start TUI
main_menu
