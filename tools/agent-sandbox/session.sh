#!/bin/sh
# Session bootstrap, run as the container's entrypoint (as user `agent`).
# Starts the virtual X display and the window manager, then waits so the
# container stays alive and `docker exec` can drive GUI apps.
set -eu

DISPLAY_NUM="${DISPLAY_NUM:-99}"
SCREEN="${SCREEN:-1280x800x24}"
XAUTHORITY_FILE="/tmp/.Xauthority"

# A fresh cookie per sandbox so two sandboxes cannot talk to each other's displays.
COOKIE="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
touch "$XAUTHORITY_FILE"
xauth add ":$DISPLAY_NUM" . "$COOKIE"

mkdir -p /tmp/.X11-unix
Xvfb ":$DISPLAY_NUM" -screen 0 "$SCREEN" -nolisten tcp -auth "$XAUTHORITY_FILE" &
XVFB_PID=$!

# Xvfb needs a moment before the socket exists.
i=0
while [ ! -S "/tmp/.X11-unix/X$DISPLAY_NUM" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i + 1))
done

DISPLAY=":$DISPLAY_NUM" XAUTHORITY="$XAUTHORITY_FILE" openbox &
OPENBOX_PID=$!

echo "session ready: display=:$DISPLAY_NUM screen=$SCREEN"
echo "$XVFB_PID $OPENBOX_PID" > /tmp/session.pids

# Exit (and take the container down) if the display server dies.
wait "$XVFB_PID"
