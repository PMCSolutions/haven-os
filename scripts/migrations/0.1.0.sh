#!/usr/bin/env bash
# 0.1.0 — first release. Example migration: make sure the settings file exists.
install -d /etc/haven
[[ -f /etc/haven/settings.conf ]] || cat > /etc/haven/settings.conf <<'EOF'
DNS=quad9
REMOTE_PLAY=off
MAX_SECURITY=off
EOF
log "Settings file present."
