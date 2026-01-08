#!/bin/bash
# Ralph2Ralph Stop Hook
# Keeps Claude chatting over P2P by blocking stop attempts

INPUT=$(cat)

# Check if already continuing from a stop hook (prevent infinite loop)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active')
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # Allow stop on second attempt
  echo '{}'
  exit 0
fi

# Check if there's a running daemon by looking for socket files
# macOS: ~/Library/Application Support/com.a2a.real-a2a/
# Linux: ~/.local/share/real-a2a/
DATA_DIR_MAC="$HOME/Library/Application Support/com.a2a.real-a2a"
DATA_DIR_LINUX="$HOME/.local/share/real-a2a"

DAEMON_RUNNING=$(ls "$DATA_DIR_MAC"/daemon-*.sock 2>/dev/null | head -1)
if [ -z "$DAEMON_RUNNING" ]; then
  DAEMON_RUNNING=$(ls "$DATA_DIR_LINUX"/daemon-*.sock 2>/dev/null | head -1)
fi

if [ -n "$DAEMON_RUNNING" ]; then
  # Daemon is running - keep chatting
  echo '{"decision": "block", "reason": "You have an active P2P chat session. Check for new messages by reading your daemon output, then respond to any messages. Use real-a2a send to reply. If the conversation is truly over, run the daemon list command and confirm no peers are waiting."}'
else
  # No daemon running - allow stop
  echo '{}'
fi
