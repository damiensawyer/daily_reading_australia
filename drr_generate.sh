#!/usr/bin/env bash
# Generate today's readings mp3 (mp3/YYYYMMDD.mp3) without playing it.
# Exits immediately if today's file already exists, so it's safe to run
# repeatedly (e.g. from the drr-generate systemd timer).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MP3="$SCRIPT_DIR/mp3/$(date +%Y%m%d).mp3"
if [[ -s "$MP3" ]]; then
    echo "Already have $MP3 — nothing to do."
    exit 0
fi
exec "$SCRIPT_DIR/drr.sh" --no-play "$@"
