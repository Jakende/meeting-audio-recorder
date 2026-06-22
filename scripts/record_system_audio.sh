#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

require_command "$FFMPEG_BIN"
require_audio_device "$BLACKHOLE_DEVICE"

if is_recording; then
  log_error "Eine Aufnahme läuft bereits! (PID: $(get_pid))"
  echo "Stoppen mit: ./scripts/record.sh stop"
  exit 1
fi

OUTFILE="$(meeting_output_file)"
print_run_header "Starte Variante A: nur Systemaudio über '$BLACKHOLE_DEVICE'" "$OUTFILE"

log_info "Starting Variant A recording: $OUTFILE"

echo "Stoppen mit Ctrl+C oder: ./scripts/record.sh stop"

save_pid

exec "$FFMPEG_BIN" -hide_banner -nostdin -loglevel warning \
  -f avfoundation -thread_queue_size 512 -i ":$BLACKHOLE_DEVICE" \
  -vn \
  -ar "$SAMPLE_RATE" -ac 2 \
  -c:a "$AUDIO_CODEC" -b:a "$BITRATE" \
  -y "$OUTFILE"
