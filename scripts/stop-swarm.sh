#!/bin/bash

# Stop the swarm - kills the host daemon

INFO_FILE="/tmp/swarm-info.txt"

if [ -f "$INFO_FILE" ]; then
    source "$INFO_FILE"

    echo "Stopping swarm..."
    echo "  Room identity: $ROOM_IDENTITY"
    echo "  Daemon PID: $DAEMON_PID"

    if kill -0 "$DAEMON_PID" 2>/dev/null; then
        kill "$DAEMON_PID"
        echo "  Daemon stopped."
    else
        echo "  Daemon already stopped."
    fi

    rm -f "$INFO_FILE"
else
    echo "No swarm info found at $INFO_FILE"
    echo ""
    echo "Trying to kill any real-a2a daemons..."
    pkill -f "real-a2a daemon" && echo "Killed." || echo "None found."
fi

echo ""
echo "Note: Agent terminal windows are still open."
echo "Close them manually or they will stop on their own."
