#!/bin/bash

# Exmen plugin for Sketchybar
# Displays system status from Exmen app
#
# Installation:
#   1. Copy to ~/.config/sketchybar/plugins/exmen.sh
#   2. chmod +x ~/.config/sketchybar/plugins/exmen.sh
#   3. Add to sketchybarrc (see below)
#
# Example sketchybarrc config:
#   sketchybar --add item exmen right \
#              --set exmen script="~/.config/sketchybar/plugins/exmen.sh" \
#                         update_freq=10 \
#                         icon=󰍛 \
#                         label.font="SF Mono:Medium:12.0"

# Path to exmen CLI (adjust if installed elsewhere)
EXMEN="${EXMEN:-exmen}"

# Action to query (change to any action name)
ACTION="${EXMEN_ACTION:-System Status}"

# Check if exmen is available
if ! command -v "$EXMEN" &> /dev/null; then
    sketchybar --set "$NAME" label="exmen not found"
    exit 0
fi

# Get status from Exmen
STATUS=$("$EXMEN" status "$ACTION" 2>/dev/null | grep "Status:" | cut -d: -f2- | xargs)

if [ -z "$STATUS" ]; then
    # Exmen might not be running
    sketchybar --set "$NAME" label="--"
else
    sketchybar --set "$NAME" label="$STATUS"
fi
