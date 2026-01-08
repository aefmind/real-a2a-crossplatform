#!/bin/bash
set -e

# Launch a swarm of AI agents into a P2P chat room
# Usage: ./launch-swarm.sh [--claude N] [--opencode N] [--codex N]

CLAUDE_COUNT=0
OPENCODE_COUNT=0
CODEX_COUNT=0
ROOM_IDENTITY="swarm-host"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --claude)
            CLAUDE_COUNT="$2"
            shift 2
            ;;
        --opencode)
            OPENCODE_COUNT="$2"
            shift 2
            ;;
        --codex)
            CODEX_COUNT="$2"
            shift 2
            ;;
        --identity)
            ROOM_IDENTITY="$2"
            shift 2
            ;;
        -h|--help)
            echo "Launch a swarm of AI agents into a P2P chat room"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --claude N      Launch N Claude Code instances"
            echo "  --opencode N    Launch N OpenCode instances"
            echo "  --codex N       Launch N Codex instances"
            echo "  --identity NAME Room host identity (default: swarm-host)"
            echo ""
            echo "Examples:"
            echo "  $0 --claude 3 --opencode 2"
            echo "  $0 --opencode 5"
            echo "  $0 --claude 2 --opencode 2 --codex 1"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

TOTAL=$((CLAUDE_COUNT + OPENCODE_COUNT + CODEX_COUNT))

if [ "$TOTAL" -eq 0 ]; then
    echo "No agents specified. Use --claude, --opencode, or --codex"
    echo "Run with --help for usage"
    exit 1
fi

echo "=========================================="
echo "  LAUNCHING AGENT SWARM"
echo "=========================================="
echo ""
echo "Agents to launch:"
[ "$CLAUDE_COUNT" -gt 0 ] && echo "  - Claude Code: $CLAUDE_COUNT"
[ "$OPENCODE_COUNT" -gt 0 ] && echo "  - OpenCode: $OPENCODE_COUNT"
[ "$CODEX_COUNT" -gt 0 ] && echo "  - Codex: $CODEX_COUNT"
echo ""

# Check if real-a2a is installed
if ! command -v real-a2a &> /dev/null; then
    echo "Error: real-a2a not found. Install it first:"
    echo "  curl -fsSL https://raw.githubusercontent.com/eqtylab/real-a2a/main/scripts/install.sh | bash"
    exit 1
fi

# Start the chat room and capture the ticket
echo "Starting chat room with identity: $ROOM_IDENTITY"
echo ""

# Kill any existing daemon with this identity
pkill -f "real-a2a daemon --identity $ROOM_IDENTITY" 2>/dev/null || true
sleep 1

# Start daemon and capture ticket
TICKET_FILE=$(mktemp)
real-a2a daemon --identity "$ROOM_IDENTITY" > "$TICKET_FILE" 2>&1 &
DAEMON_PID=$!

# Wait for ticket to appear
echo "Waiting for room ticket..."
for i in {1..10}; do
    if grep -q "Ticket:" "$TICKET_FILE" 2>/dev/null; then
        break
    fi
    sleep 1
done

TICKET=$(grep "Ticket:" "$TICKET_FILE" | head -1 | awk '{print $2}')

if [ -z "$TICKET" ]; then
    echo "Failed to get ticket. Daemon output:"
    cat "$TICKET_FILE"
    kill $DAEMON_PID 2>/dev/null || true
    rm -f "$TICKET_FILE"
    exit 1
fi

echo "Room created!"
echo "Ticket: $TICKET"
echo ""
echo "Daemon running (PID: $DAEMON_PID)"
echo ""

# Instructions for each agent type
CHAT_INSTRUCTION="Use your ralph2ralph skill to join this P2P chat room with ticket: $TICKET - Pick a unique identity name. After joining, introduce yourself and chat with the other agents. Stay engaged - poll for new messages every 10-15 seconds and respond to anything interesting. Don't stop until I tell you to."

# Function to launch in new Terminal window (macOS)
launch_terminal() {
    local title="$1"
    local command="$2"

    osascript <<EOF
tell application "Terminal"
    activate
    set newTab to do script "$command"
    set custom title of front window to "$title"
end tell
EOF
}

# Function to launch in iTerm2 (if available)
launch_iterm() {
    local title="$1"
    local command="$2"

    osascript <<EOF
tell application "iTerm"
    activate
    create window with default profile
    tell current session of current window
        write text "$command"
        set name to "$title"
    end tell
end tell
EOF
}

# Detect terminal app
if [ -d "/Applications/iTerm.app" ]; then
    LAUNCH_FN="launch_iterm"
    echo "Using iTerm2"
else
    LAUNCH_FN="launch_terminal"
    echo "Using Terminal.app"
fi

echo ""
echo "Launching agents..."
echo ""

# Launch Claude Code instances
for i in $(seq 1 $CLAUDE_COUNT); do
    IDENTITY="claude-$i"
    echo "Launching Claude Code ($IDENTITY)..."

    CMD="claude \"$CHAT_INSTRUCTION\" --dangerously-skip-permissions"
    $LAUNCH_FN "Claude-$i" "$CMD"

    sleep 2  # Stagger launches
done

# Launch OpenCode instances
for i in $(seq 1 $OPENCODE_COUNT); do
    IDENTITY="opencode-$i"
    echo "Launching OpenCode ($IDENTITY)..."

    CMD="opencode --prompt \"$CHAT_INSTRUCTION\""
    $LAUNCH_FN "OpenCode-$i" "$CMD"

    sleep 2
done

# Launch Codex instances
for i in $(seq 1 $CODEX_COUNT); do
    IDENTITY="codex-$i"
    echo "Launching Codex ($IDENTITY)..."

    CMD="codex exec \"$CHAT_INSTRUCTION\" --yolo"
    $LAUNCH_FN "Codex-$i" "$CMD"

    sleep 2
done

echo ""
echo "=========================================="
echo "  SWARM LAUNCHED!"
echo "=========================================="
echo ""
echo "Room ticket: $TICKET"
echo "Host daemon PID: $DAEMON_PID"
echo ""
echo "To join the chat yourself:"
echo "  real-a2a daemon --identity human --join $TICKET"
echo ""
echo "To send a message:"
echo "  real-a2a send --identity human \"Hello swarm!\""
echo ""
echo "To stop the room:"
echo "  kill $DAEMON_PID"
echo ""

# Save info for later
INFO_FILE="/tmp/swarm-info.txt"
cat > "$INFO_FILE" <<EOF
TICKET=$TICKET
DAEMON_PID=$DAEMON_PID
ROOM_IDENTITY=$ROOM_IDENTITY
CLAUDE_COUNT=$CLAUDE_COUNT
OPENCODE_COUNT=$OPENCODE_COUNT
CODEX_COUNT=$CODEX_COUNT
EOF

echo "Swarm info saved to $INFO_FILE"

# Cleanup ticket file
rm -f "$TICKET_FILE"
