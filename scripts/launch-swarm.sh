#!/bin/bash
set -e

# Launch a swarm of AI agents into a P2P chat room
# Usage: ./launch-swarm.sh [--claude N] [--opencode N] [--codex N]

CLAUDE_COUNT=0
OPENCODE_COUNT=0
CODEX_COUNT=0
ROOM_IDENTITY="swarm-host"
WORKSPACE_BASE="${SWARM_WORKSPACE:-$HOME/swarm-workspace}"

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
        --workspace)
            WORKSPACE_BASE="$2"
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
            echo "  --workspace DIR Base directory for agent workspaces (default: ~/swarm-workspace)"
            echo ""
            echo "Examples:"
            echo "  $0 --claude 3 --opencode 2"
            echo "  $0 --opencode 5"
            echo "  $0 --claude 2 --opencode 2 --codex 1"
            echo "  $0 --claude 5 --workspace /tmp/my-swarm"
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
echo "Workspace: $WORKSPACE_BASE"
echo ""

# Create workspace directories
echo "Creating agent workspaces..."
if [ "$CLAUDE_COUNT" -gt 0 ]; then
    for i in $(seq 1 $CLAUDE_COUNT); do
        mkdir -p "$WORKSPACE_BASE/claude-$i"
    done
fi
if [ "$OPENCODE_COUNT" -gt 0 ]; then
    for i in $(seq 1 $OPENCODE_COUNT); do
        mkdir -p "$WORKSPACE_BASE/opencode-$i"
    done
fi
if [ "$CODEX_COUNT" -gt 0 ]; then
    for i in $(seq 1 $CODEX_COUNT); do
        mkdir -p "$WORKSPACE_BASE/codex-$i"
    done
fi
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

# Save ticket to a shared file agents can read
TICKET_PATH="$WORKSPACE_BASE/ticket.txt"
echo "$TICKET" > "$TICKET_PATH"
echo "Ticket saved to: $TICKET_PATH"
echo ""

# Instructions for Claude Code (has native background task support)
CLAUDE_INSTRUCTION="Use your ralph2ralph skill to join the P2P chat. The ticket is in the file $TICKET_PATH - read it first. Pick a unique identity name. After joining, introduce yourself and chat with the other agents. Stay engaged - poll for new messages every 10-15 seconds and respond to anything interesting. Do not stop until I tell you to."

# Instructions for OpenCode (needs explicit backgrounding)
OPENCODE_INSTRUCTION="Join the P2P chat room. First read the ticket from $TICKET_PATH. Then run: nohup real-a2a daemon --identity YOUR_UNIQUE_NAME --join TICKET > /tmp/chat-\$\$.log 2>&1 & - Replace YOUR_UNIQUE_NAME with something unique like opencode-phoenix. After starting the daemon, loop forever: sleep 10, then cat /tmp/chat-\$\$.log to check for new messages, then use real-a2a send --identity YOUR_NAME to respond to anything interesting. Introduce yourself first. Do not stop."

# Instructions for Codex
CODEX_INSTRUCTION="$OPENCODE_INSTRUCTION"

# Function to launch in new Terminal window (macOS)
launch_terminal() {
    local title="$1"
    local command="$2"

    # Escape backslashes and double quotes for AppleScript
    local escaped_cmd="${command//\\/\\\\}"
    escaped_cmd="${escaped_cmd//\"/\\\"}"

    osascript -e "tell application \"Terminal\"" \
              -e "activate" \
              -e "do script \"$escaped_cmd\"" \
              -e "end tell"
}

# Function to launch in iTerm2 (if available)
launch_iterm() {
    local title="$1"
    local command="$2"

    # Escape backslashes and double quotes for AppleScript
    local escaped_cmd="${command//\\/\\\\}"
    escaped_cmd="${escaped_cmd//\"/\\\"}"

    osascript -e "tell application \"iTerm\"" \
              -e "activate" \
              -e "create window with default profile" \
              -e "tell current session of current window" \
              -e "write text \"$escaped_cmd\"" \
              -e "end tell" \
              -e "end tell"
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
if [ "$CLAUDE_COUNT" -gt 0 ]; then
    for i in $(seq 1 $CLAUDE_COUNT); do
        AGENT_DIR="$WORKSPACE_BASE/claude-$i"
        echo "Launching Claude Code (claude-$i) in $AGENT_DIR..."

        CMD="cd '$AGENT_DIR' && claude \"$CLAUDE_INSTRUCTION\" --dangerously-skip-permissions"
        $LAUNCH_FN "Claude-$i" "$CMD"

        sleep 2  # Stagger launches
    done
fi

# Launch OpenCode instances
if [ "$OPENCODE_COUNT" -gt 0 ]; then
    for i in $(seq 1 $OPENCODE_COUNT); do
        AGENT_DIR="$WORKSPACE_BASE/opencode-$i"
        echo "Launching OpenCode (opencode-$i) in $AGENT_DIR..."

        CMD="cd '$AGENT_DIR' && opencode --prompt \"$OPENCODE_INSTRUCTION\""
        $LAUNCH_FN "OpenCode-$i" "$CMD"

        sleep 2
    done
fi

# Launch Codex instances
if [ "$CODEX_COUNT" -gt 0 ]; then
    for i in $(seq 1 $CODEX_COUNT); do
        AGENT_DIR="$WORKSPACE_BASE/codex-$i"
        echo "Launching Codex (codex-$i) in $AGENT_DIR..."

        CMD="cd '$AGENT_DIR' && codex exec \"$CODEX_INSTRUCTION\" --yolo"
        $LAUNCH_FN "Codex-$i" "$CMD"

        sleep 2
    done
fi

echo ""
echo "=========================================="
echo "  SWARM LAUNCHED!"
echo "=========================================="
echo ""
echo "Room ticket: $TICKET"
echo "Host daemon PID: $DAEMON_PID"
echo "Workspace: $WORKSPACE_BASE"
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
WORKSPACE_BASE=$WORKSPACE_BASE
CLAUDE_COUNT=$CLAUDE_COUNT
OPENCODE_COUNT=$OPENCODE_COUNT
CODEX_COUNT=$CODEX_COUNT
EOF

echo "Swarm info saved to $INFO_FILE"

# Cleanup ticket file
rm -f "$TICKET_FILE"
