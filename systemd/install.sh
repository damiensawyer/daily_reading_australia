#!/usr/bin/env bash
# Install and enable the drr-generate systemd user timer
# (generates today's readings mp3 every 30 min, 03:00-12:00).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$HERE")"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$DEST"

sed "s|@REPO_DIR@|$REPO_DIR|g" "$HERE/drr-generate.service" > "$DEST/drr-generate.service"
cp "$HERE/drr-generate.timer" "$DEST/drr-generate.timer"

systemctl --user daemon-reload
systemctl --user enable --now drr-generate.timer

# Run even when not logged in.
if [[ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != yes ]]; then
    echo "Enabling linger for $USER (may prompt for password)…"
    loginctl enable-linger "$USER" || echo "warning: could not enable linger; timer only runs while logged in" >&2
fi

echo "✓ Installed. Next run:"
systemctl --user list-timers drr-generate.timer --no-pager
