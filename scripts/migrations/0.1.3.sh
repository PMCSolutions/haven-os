#!/usr/bin/env bash
# 0.1.3 - Windows-style desktop. Refresh caches so the new taskbar layouts,
# Start icon, .exe double-click handler and right-click menu show up.
update-desktop-database -q /usr/share/applications 2>/dev/null || true
gtk-update-icon-cache -q -f /usr/share/icons/hicolor 2>/dev/null || true
command -v xdg-open >/dev/null || pacman -S --needed --noconfirm xdg-utils
log "Existing users keep their current taskbar. To switch: Start menu > Haven Welcome."
