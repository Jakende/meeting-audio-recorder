#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$PROJECT_ROOT/.venv/bin/activate" ]]; then
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.venv/bin/activate"
fi

# Configuration with defaults
FFMPEG_BIN="${FFMPEG_BIN:-ffmpeg}"
OUTPUT_DIR="${OUTPUT_DIR:-$PROJECT_ROOT/recordings}"
BLACKHOLE_DEVICE="${BLACKHOLE_DEVICE:-BlackHole 2ch}"
MIC_DEVICE="${MIC_DEVICE:-MacBook Pro Microphone}"
SAMPLE_RATE="${SAMPLE_RATE:-48000}"
BITRATE="${BITRATE:-192k}"
AUDIO_CODEC="${AUDIO_CODEC:-aac}"
CONTAINER_FORMAT="${CONTAINER_FORMAT:-m4a}"
MAX_DURATION="${MAX_DURATION:-}"  # Optional: maximum recording duration in seconds
AUTO_SPLIT="${AUTO_SPLIT:-false}"  # Enable auto-split for long recordings

# PID file for tracking running recordings
PID_FILE="$PROJECT_ROOT/recording.pid"
LOG_FILE="$PROJECT_ROOT/recording.log"

mkdir -p "$OUTPUT_DIR"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Fehler: Kommando '$1' nicht gefunden." >&2
    exit 1
  }
}

list_audio_devices_raw() {
  "$FFMPEG_BIN" -f avfoundation -list_devices true -i "" 2>&1 || true
}

list_audio_devices_clean() {
  list_audio_devices_raw | awk '/AVFoundation audio devices:/, /Error opening input/' | grep '^\[AVFoundation indev' || true
}

extract_audio_device_names() {
  list_audio_devices_raw | awk '
    /AVFoundation audio devices:/ { in_audio=1; next }
    /Error opening input/ { in_audio=0 }
    in_audio && match($0, /\[[0-9]+\] /) {
      sub(/^.*\[[0-9]+\] /, "", $0)
      if (!seen[$0]++) {
        print $0
      }
    }
  '
}

require_audio_device() {
  local wanted="$1"
  extract_audio_device_names | grep -Fx "$wanted" >/dev/null 2>&1 || {
    echo "Fehler: Audio-Device '$wanted' nicht gefunden." >&2
    echo "Verfügbare Audio-Devices:" >&2
    extract_audio_device_names >&2
    exit 1
  }
}

meeting_output_file() {
  local stamp
  stamp="$(date +%Y%m%d_%H%M)"
  printf '%s/meeting_%s.m4a\n' "$OUTPUT_DIR" "$stamp"
}

print_run_header() {
  local label="$1"
  local outfile="$2"
  echo "$label"
  echo "Ausgabe: $outfile"
}

# Logging functions
log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
  echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
  log "INFO" "$@"
}

log_warn() {
  log "WARN" "$@" >&2
}

log_error() {
  log "ERROR" "$@" >&2
}

# PID management
save_pid() {
  echo "$$" > "$PID_FILE"
  log_info "Recording started with PID $$"
}

get_pid() {
  if [[ -f "$PID_FILE" ]]; then
    cat "$PID_FILE"
  else
    echo ""
  fi
}

is_recording() {
  local pid
  pid="$(get_pid)"
  if [[ -n "$pid" && -d "/proc/$pid" ]]; then
    return 0
  else
    return 1
  fi
}

stop_recording() {
  local pid
  pid="$(get_pid)"
  if [[ -n "$pid" ]]; then
    if kill -0 "$pid" 2>/dev/null; then
      log_info "Stopping recording (PID: $pid)"
      kill "$pid" 2>/dev/null || true
      rm -f "$PID_FILE"
      return 0
    else
      log_warn "PID file exists but process $pid is not running"
      rm -f "$PID_FILE"
      return 1
    fi
  else
    log_warn "No active recording found"
    return 1
  fi
}

# Configuration file support
CONFIG_FILE="$PROJECT_ROOT/config.env"

load_config() {
  if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck disable=SC1091
    source "$CONFIG_FILE"
    log_info "Configuration loaded from $CONFIG_FILE"
  fi
}

save_config() {
  cat > "$CONFIG_FILE" <<EOF
# Meeting Audio Recorder Configuration
# Generated: $(date)
BLACKHOLE_DEVICE="$BLACKHOLE_DEVICE"
MIC_DEVICE="$MIC_DEVICE"
OUTPUT_DIR="$OUTPUT_DIR"
SAMPLE_RATE="$SAMPLE_RATE"
BITRATE="$BITRATE"
AUDIO_CODEC="$AUDIO_CODEC"
CONTAINER_FORMAT="$CONTAINER_FORMAT"
EOF
  log_info "Configuration saved to $CONFIG_FILE"
}

# Recording management
list_recordings() {
  local count
  count=0
  if [[ -d "$OUTPUT_DIR" ]]; then
    for file in "$OUTPUT_DIR"/*.m4a "$OUTPUT_DIR"/*.mp3 "$OUTPUT_DIR"/*.wav "$OUTPUT_DIR"/*.aac; do
      if [[ -f "$file" ]]; then
        echo "$file"
        count=$((count + 1))
      fi
    done
  fi
  if [[ $count -eq 0 ]]; then
    echo "Keine Aufnahmen gefunden in $OUTPUT_DIR"
  fi
  return $count
}

cleanup_old_recordings() {
  local days="${1:-30}"
  local cutoff
  cutoff="$(date -d "$days days ago" +%s 2>/dev/null || date -v-${days}d +%s)"
  local count=0
  
  if [[ -d "$OUTPUT_DIR" ]]; then
    for file in "$OUTPUT_DIR"/*.m4a "$OUTPUT_DIR"/*.mp3 "$OUTPUT_DIR"/*.wav "$OUTPUT_DIR"/*.aac; do
      if [[ -f "$file" ]]; then
        local mtime
        mtime="$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null)"
        if [[ "$mtime" -lt "$cutoff" ]]; then
          log_info "Deleting old recording: $file"
          rm -f "$file"
          count=$((count + 1))
        fi
      fi
    done
  fi
  
  log_info "Deleted $count old recordings (older than $days days)"
  return $count
}

# Audio device utilities
get_device_index() {
  local device_name="$1"
  list_audio_devices_raw | grep -E "\[[0-9]+\] $device_name$" | head -1 | grep -oE '\[[0-9]+\]' | tr -d '[]'
}

# Validation
validate_setup() {
  local errors=0
  
  # Check ffmpeg
  if ! command -v "$FFMPEG_BIN" >/dev/null 2>&1; then
    log_error "ffmpeg not found at: $FFMPEG_BIN"
    errors=$((errors + 1))
  fi
  
  # Check BlackHole device
  if ! extract_audio_device_names | grep -Fx "$BLACKHOLE_DEVICE" >/dev/null 2>&1; then
    log_error "BlackHole device not found: $BLACKHOLE_DEVICE"
    errors=$((errors + 1))
  fi
  
  # Check output directory
  if [[ ! -d "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
  fi
  
  if [[ $errors -gt 0 ]]; then
    return 1
  else
    return 0
  fi
}

# Display utilities
show_banner() {
  echo "================================================"
  echo "  Meeting Audio Recorder"
  echo "  Robuste CLI-Aufzeichnung auf macOS"
  echo "  mit ffmpeg und BlackHole 2ch"
  echo "================================================"
  echo ""
}

# Format duration (seconds to HH:MM:SS)
format_duration() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(( (seconds % 3600) / 60 ))
  local secs=$((seconds % 60))
  printf "%02d:%02d:%02d" "$hours" "$minutes" "$secs"
}
