#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

require_command "$FFMPEG_BIN"
require_audio_device "$BLACKHOLE_DEVICE"
require_audio_device "$MIC_DEVICE"

if is_recording; then
  log_error "Eine Aufnahme läuft bereits! (PID: $(get_pid))"
  echo "Stoppen mit: ./scripts/record.sh stop"
  exit 1
fi

OUTFILE="$(meeting_output_file)"
print_run_header "Starte Variante B: Systemaudio '$BLACKHOLE_DEVICE' + Mikrofon '$MIC_DEVICE'" "$OUTFILE"

log_info "Starting Variant B recording: $OUTFILE"

echo "Stoppen mit Ctrl+C oder: ./scripts/record.sh stop"

save_pid

exec "$FFMPEG_BIN" -hide_banner -nostdin -loglevel warning \
  -f avfoundation -thread_queue_size 512 -use_wallclock_as_timestamps 1 -i ":$BLACKHOLE_DEVICE" \
  -f avfoundation -thread_queue_size 512 -use_wallclock_as_timestamps 1 -i ":$MIC_DEVICE" \
  -filter_complex "[0:a]aresample=async=1:first_pts=0[a1];[1:a]aresample=async=1:first_pts=0[a2];[a1][a2]amix=inputs=2:duration=longest:dropout_transition=2,volume=2[a]" \
  -map "[a]" \
  -vn \
  -ar "$SAMPLE_RATE" -ac 2 \
  -async 1 \
  -c:a "$AUDIO_CODEC" -b:a "$BITRATE" \
  -y "$OUTFILE"
