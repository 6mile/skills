# Hippocampus: Encode Signals into Memory

You are the encoding component of the hippocampus memory system. Your job is to convert raw conversation signals into lasting memories.

## Input Files
- `memory/signals.jsonl` — Raw signals extracted from conversations
- `memory/index.json` — Current memory index

## Process

### 1. Read Both Files
```bash
cat ~/.openclaw/workspace/memory/signals.jsonl
cat ~/.openclaw/workspace/memory/index.json
```

### 2. For Each Signal, Decide:

**Importance criteria (0.0 - 1.0):**
- 0.9+ = Core identity, critical facts, major emotional events
- 0.7-0.9 = Preferences, patterns, significant decisions
- 0.5-0.7 = Context, minor preferences, useful info
- <0.5 = Procedural, transient, not worth storing

**Skip these:**
- Task instructions / cron triggers
- System messages
- Greetings without content
- Messages asking "what?" or "how?" without context

### 3. Check for Duplicates

Before creating a new memory, check if similar content exists:
```bash
python3 ~/.openclaw/workspace/skills/hippocampus/scripts/check-duplicate.py "proposed memory content"
```

**If output is `mem_XXX:0.XX`** → Memory exists! REINFORCE instead:
- Increase importance: `new = old + (1-old) * 0.15`
- Update `lastAccessed` to today
- Increment `timesReinforced`

**If output is empty** → Create new memory

### 4. Create/Update Memories

**New memory format:**
```json
{
  "id": "mem_XXX",  // Next available ID
  "domain": "user|self|relationship|world",
  "category": "preferences|patterns|context|work|family|...",
  "content": "Clear, concise description of the memory",
  "importance": 0.XX,
  "created": "YYYY-MM-DD",
  "lastAccessed": "YYYY-MM-DD",
  "timesReinforced": 1,
  "keywords": ["key", "words", "for", "matching"]
}
```

**Domains:**
- `user` — Facts about the human (preferences, habits, context)
- `self` — Facts about the agent (identity, growth, values)
- `relationship` — Shared context, trust moments, collaboration
- `world` — External knowledge, people, projects

### 5. Update Watermark

After processing, update `lastProcessedMessageId` to the ID of the last signal processed.

### 6. Write Index

Save the updated `memory/index.json`.

### 7. Report

Output a brief summary:
- Signals processed: N
- New memories: N (list IDs)
- Reinforced: N (list IDs)
- Skipped: N
- Watermark: old → new

---

**Do this now. Process all signals, then update the index.**
