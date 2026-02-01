#!/bin/bash
# Preprocess transcript into clean signals for hippocampus
# Extracts user text content, strips tool noise
#
# Usage:
#   preprocess.sh          # Process messages after watermark
#   preprocess.sh --full   # Process ALL messages (ignore watermark)
#
# Environment:
#   WORKSPACE - OpenClaw workspace directory (default: ~/.openclaw/workspace)
#   AGENT_ID - Agent ID for transcript lookup (default: main)

set -e

WORKSPACE="${WORKSPACE:-$HOME/.openclaw/workspace}"
AGENT_ID="${AGENT_ID:-main}"
TRANSCRIPT_DIR="$HOME/.openclaw/agents/$AGENT_ID/sessions"
OUTPUT="$WORKSPACE/memory/signals.jsonl"
INDEX="$WORKSPACE/memory/index.json"

# Parse arguments
FULL_MODE=false
if [ "$1" = "--full" ]; then
    FULL_MODE=true
fi

# Get the current watermark (unless --full)
WATERMARK=""
if [ "$FULL_MODE" = false ]; then
    WATERMARK=$(cat "$INDEX" 2>/dev/null | grep -o '"lastProcessedMessageId": "[^"]*"' | cut -d'"' -f4)
fi

# Find the active session (most recently modified .jsonl)
SESSION_FILE=$(ls -t "$TRANSCRIPT_DIR"/*.jsonl 2>/dev/null | head -1)

if [ -z "$SESSION_FILE" ]; then
    echo "No session transcript found in $TRANSCRIPT_DIR"
    exit 1
fi

echo "Processing: $SESSION_FILE"
echo "Mode: $([ "$FULL_MODE" = true ] && echo 'FULL (all messages)' || echo 'incremental')"
echo "Watermark: ${WATERMARK:-'(none)'}"

# Use Python for robust JSON parsing (handles control characters)
python3 -c "
import sys
import json
import re

session_file = '$SESSION_FILE'
output_file = '$OUTPUT'
watermark = '$WATERMARK' if '$WATERMARK' else None
full_mode = '$FULL_MODE' == 'true'

signals = []
found_watermark = False if watermark else True  # If no watermark, process everything

with open(session_file, 'r', encoding='utf-8', errors='replace') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue
        
        # Check if this is the watermark line
        if watermark and data.get('id') == watermark:
            found_watermark = True
            continue  # Skip the watermark line itself
        
        # Skip until we find watermark (unless full mode)
        if not full_mode and not found_watermark:
            continue
        
        # Only process user messages
        if data.get('type') != 'message':
            continue
        
        msg = data.get('message', {})
        if msg.get('role') != 'user':
            continue
        
        # Extract text content
        content = msg.get('content', [])
        text = ''
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict) and item.get('type') == 'text':
                    text = item.get('text', '')
                    break
        elif isinstance(content, str):
            text = content
        
        # Clean up text
        text = text[:500]  # Limit length
        text = re.sub(r'[\x00-\x1f]', ' ', text)  # Remove control chars
        text = ' '.join(text.split())  # Normalize whitespace
        
        # Skip empty, short, or JSON-looking messages
        if len(text) < 10 or text.startswith('{'):
            continue
        
        # Skip system messages that look like cron triggers
        if text.startswith('System:') and 'Cron:' in text:
            continue
        
        signal = {
            'id': data.get('id', ''),
            'timestamp': data.get('timestamp', ''),
            'text': text
        }
        
        if signal['id']:
            signals.append(signal)

# Write output
with open(output_file, 'w', encoding='utf-8') as f:
    for sig in signals:
        f.write(json.dumps(sig, ensure_ascii=False) + '\n')

print(f'Wrote {len(signals)} signals to {output_file}')
"
