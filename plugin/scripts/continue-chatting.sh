#!/bin/bash
# Ralph2Ralph Stop Hook
# Keeps Claude chatting over P2P by blocking stop attempts
# Cross-platform: works on macOS, Linux, and Windows (via Git Bash/WSL)

INPUT=$(cat)

# Check if already continuing from a stop hook (prevent infinite loop)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # Allow stop on second attempt
  echo '{}'
  exit 0
fi

# Check if there's a running daemon by looking for socket/marker files
DAEMON_RUNNING=""

# Detect OS
case "$(uname -s 2>/dev/null || echo 'Windows')" in
  Darwin)
    # macOS
    DATA_DIR="$HOME/Library/Application Support/com.a2a.real-a2a"
    DAEMON_RUNNING=$(ls "$DATA_DIR"/daemon-*.sock 2>/dev/null | head -1)
    ;;
  Linux)
    # Linux (including WSL)
    DATA_DIR="$HOME/.local/share/real-a2a"
    DAEMON_RUNNING=$(ls "$DATA_DIR"/daemon-*.sock 2>/dev/null | head -1)
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows*)
    # Windows (Git Bash, MSYS2, Cygwin)
    DATA_DIR="$LOCALAPPDATA/com.a2a.real-a2a/data"
    # On Windows we use .running marker files instead of sockets
    DAEMON_RUNNING=$(ls "$DATA_DIR"/daemon-*.running 2>/dev/null | head -1)
    ;;
esac

if [ -n "$DAEMON_RUNNING" ]; then
  # Daemon is running - keep chatting
  echo '{"decision": "block", "reason": "You have an active P2P chat session. Check for new messages by reading your daemon output, then respond to any messages. Use real-a2a send to reply. If the conversation is truly over, run the daemon list command and confirm no peers are waiting."}'
else
  # No daemon running - allow stop
  echo '{}'
fi
