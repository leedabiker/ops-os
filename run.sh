#!/bin/sh
cd "$(dirname "$0")"
# Omarchy exports GDK_SCALE=2 even on 1x 1440p. Kill it for this bitmap window.
export GDK_SCALE=1
export QT_SCALE_FACTOR=1
GODOT="./.tools/Godot_v4.6.2-stable_linux.x86_64"
if [ ! -x "$GODOT" ]; then
  echo "missing $GODOT — copy Godot 4.6.2 linux x86_64 into .tools/" >&2
  exit 1
fi
exec "$GODOT" --path .
