---
name: bitcoin-daily
description: Daily digest of the Bitcoin Development mailing list and Bitcoin Core commits. Use when asked about recent bitcoin-dev discussions, mailing list activity, Bitcoin Core code changes, or to set up daily summaries. Fetches threads from groups.google.com/g/bitcoindev and commits from github.com/bitcoin/bitcoin.
metadata: {"clawdbot":{"emoji":"📰"}}
---

# Bitcoin Dev Digest (📰)

![Bitcoin Daily](https://files.catbox.moe/v0zvnj.png)

Daily summary of bitcoindev mailing list + Bitcoin Core commits.

*Made in 🤠 Texas ❤️ [PlebLab](https://pleblab.dev)*

## Commands

### Digest

Run via: `node ~/workspace/skills/bitcoin-daily/scripts/digest.js <command>`

| Command | Description |
|---------|-------------|
| `digest [YYYY-MM-DD]` | Fetch & summarize (default: yesterday) |
| `archive` | List all archived digests |
| `read <YYYY-MM-DD>` | Read a past summary |

### Podcast

Run via: `node ~/workspace/skills/bitcoin-daily/scripts/podcast.js <command>`

| Command | Description |
|---------|-------------|
| `[YYYY-MM-DD]` | Generate podcast from archived digest |
| `--summary <file>` | Generate from a summary file |
| `--text "..."` | Generate from inline text |

Generates a ~10-20 min AI podcast with two hosts (Alex & Maya) discussing the daily digest. Uses OpenAI TTS (`onyx` + `nova` voices) with a pop-punk intro. Output: `bitcoin-dev-archive/YYYY-MM-DD/bitcoin-daily-YYYY-MM-DD.mp3`

## Output

### Text Digest
The digest script fetches raw data. The agent then summarizes it for the user in this format:

**Mailing list:** Numbered list, each item with:
- **Bold title** — 1-2 sentence ELI10 explanation with a touch of dry humor
- Thread link

**Commits:** Bullet list of notable merges with PR links.

Keep summaries accessible — explain like the reader is smart but not a Bitcoin Core contributor. Dry humor welcome, not forced.

### Podcast Episode
After generating the text digest, **always generate the podcast too**:

1. Run `node ~/workspace/skills/bitcoin-daily/scripts/podcast.js YYYY-MM-DD`
2. Send the text digest to the user
3. Send the MP3 podcast as a follow-up

The podcast features two hosts:
- **Alex** (onyx voice): The grizzled bitcoiner. Deep technical knowledge, deadpan humor, ridiculous analogies.
- **Maya** (nova voice): Wickedly smart, faster wit. Teases Alex, connects dots, makes it accessible.

Their dynamic: lifelong friends, dry humor, flirty banter. Think Han Solo and Princess Leia discussing BIPs. **Never say "crypto" — bitcoin only.**

## Archive

Raw data archived to `~/workspace/bitcoin-dev-archive/YYYY-MM-DD/`:
- `mailing-list/*.json` — full thread content per topic
- `mailing-list/_index.json` — thread index
- `commits.json` — raw commit data
- `summary.md` — generated summary
- `podcast-script.md` — podcast dialogue script
- `podcast-clips/` — individual TTS audio clips
- `bitcoin-daily-YYYY-MM-DD.mp3` — final podcast episode

## Daily Cron

Set up via Clawdbot cron to run every morning. The workflow:
1. Digest script fetches, archives, and outputs a summary
2. Agent summarizes and sends text digest to user
3. Podcast script generates an AI podcast episode from the digest
4. Agent sends the MP3 podcast to user

## Sources

- Mailing list: https://groups.google.com/g/bitcoindev
- Bitcoin Core: https://github.com/bitcoin/bitcoin/commits/master/
