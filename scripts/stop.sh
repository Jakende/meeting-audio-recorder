#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

load_config

echo "Stoppe laufende Aufnahme..."

if stop_recording; then
  echo "Aufnahme erfolgreich gestoppt."
  exit 0
else
  echo "Keine laufende Aufnahme gefunden."
  exit 1
fi
