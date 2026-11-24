#!/usr/bin/env bash
# Disable and remove the drr-generate systemd user timer and service.
set -euo pipefail
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

systemctl --user disable --now drr-generate.timer 2>/dev/null || true
systemctl --user stop drr-generate.service 2>/dev/null || true
rm -f "$DEST/drr-generate.timer" "$DEST/drr-generate.service"
systemctl --user daemon-reload
systemctl --user reset-failed drr-generate.service drr-generate.timer 2>/dev/null || true
echo "✓ Uninstalled drr-generate timer and service."
