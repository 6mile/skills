# Node Scaling Skill

Enable parallel task execution using lightweight LLM worker nodes. This dramatically speeds up research, batch processing, and multi-step tasks.

## ⚡ Critical: Immediate Acknowledgment Pattern

When using Swarm, **ALWAYS output an acknowledgment message BEFORE calling exec**:

```
🐝 **Swarm initializing...** researching 6 companies in parallel
```

Then call exec. This ensures the user sees feedback instantly and knows Swarm is accelerating your work, not causing delays.

**DO:**
```
Me: "🐝 Swarm initializing... researching 6 AI startups in parallel"
[exec call]
Me: "Here are the results..."
```

**DON'T:**
```
[exec call with no prior message]  ← User sees nothing, thinks you froze
Me: "Here are the results..."
```

## When to Use

Activate node scaling when:

1. **Multiple independent subjects** - "Research the top 5 AI companies"
2. **Batch processing** - "Analyze these 10 URLs"
3. **Multi-step pipelines** - Tasks requiring search → fetch → analyze
4. **User requests speed** - "quickly", "in parallel", "fast"
5. **3+ independent subtasks** detected

Do NOT use for:
- Single, atomic questions
- Tasks requiring sequential dependencies
- Very short tasks (<1 second)

## How to Use

### Check if Configured

```bash
cat ~/.config/clawdbot/node-scaling.yaml
```

If not configured, guide user:
```
Node scaling isn't set up yet. Would you like me to help you configure it?

You'll need an API key from one of these providers:
• Google Gemini (cheapest): https://aistudio.google.com/apikey
• Groq (free tier): https://console.groq.com/keys
• OpenAI: https://platform.openai.com/api-keys
```

### Run Setup

```bash
cd ~/clawd/skills/node-scaling && node bin/setup.js
```

### Execute Parallel Tasks

For a research task like "Research top 5 AI companies":

```javascript
// 1. Load the dispatcher
const { Dispatcher } = require('~/clawd/skills/node-scaling/lib/dispatcher');
const dispatcher = new Dispatcher();

// 2. Define parallel tasks
const subjects = ['OpenAI', 'Anthropic', 'Google', 'Meta', 'Microsoft'];

// 3. Phase 1: Search (parallel)
const searchTasks = subjects.map(s => ({
  nodeType: 'search',
  tool: 'web_search',
  input: `${s} AI products 2024`,
}));
const searchResults = await dispatcher.executeParallel(searchTasks);

// 4. Phase 2: Fetch (parallel)
const fetchTasks = searchResults.results
  .filter(r => r.success)
  .map(r => ({
    nodeType: 'fetch',
    tool: 'web_fetch',
    input: r.result.results[0].url,
  }));
const fetchResults = await dispatcher.executeParallel(fetchTasks);

// 5. Phase 3: Analyze (parallel)
const analyzeTasks = fetchResults.results
  .filter(r => r.success)
  .map((r, i) => ({
    nodeType: 'analyze',
    instruction: `Summarize ${subjects[i]}'s AI strategy`,
    input: r.result.content,
  }));
const analyses = await dispatcher.executeParallel(analyzeTasks);

// 6. Synthesize (you do this part)
// Combine the parallel results into a coherent response
```

## Configuration

Config file: `~/.config/clawdbot/node-scaling.yaml`

Key settings:
```yaml
node_scaling:
  limits:
    max_nodes: 10        # Adjust based on system resources
  provider:
    name: gemini         # gemini, openai, anthropic, groq
    api_key_env: GEMINI_API_KEY
```

### Adjust Settings

```bash
# View current config
cat ~/.config/clawdbot/node-scaling.yaml

# Edit max nodes (example)
sed -i 's/max_nodes: .*/max_nodes: 20/' ~/.config/clawdbot/node-scaling.yaml
```

## Performance Expectations

| Task Type | Single Node | With Scaling | Speedup |
|-----------|-------------|--------------|---------|
| 5 searches | 6s | 1.6s | 3.8x |
| 10 summaries | 7s | 1s | 7x |
| 5 company research | 18s | 6s | 3x |
| 10 deep analyses | 166s | 9s | 18x |

## Cost Tracking

The dispatcher tracks token usage. Report to user:

```javascript
const stats = dispatcher.getNodeStats();
// Returns cost estimates per provider
```

## Diagnostics & Troubleshooting

### Run Diagnostics

When Swarm isn't working, run diagnostics first:

```bash
cd ~/clawd/skills/node-scaling && npm run diagnose
```

For JSON output (easier to parse):
```bash
cd ~/clawd/skills/node-scaling && npm run diagnose:json
```

### Understanding Diagnostic Output

The JSON report includes:
```json
{
  "status": "ok|warning|error",
  "machine": { /* CPU, memory, OS info */ },
  "tests": { /* unit, integration, e2e results */ },
  "issues": [ /* problems found */ ],
  "recommendations": [ /* suggested fixes */ ]
}
```

### Auto-Fix Common Issues

#### Issue: `no_config_dir`
```bash
mkdir -p ~/.config/clawdbot
```

#### Issue: `no_api_key`
Option 1 - Set environment variable:
```bash
export GEMINI_API_KEY="your-key-here"
```

Option 2 - Create key file:
```bash
echo "your-key-here" > ~/.config/clawdbot/gemini-key.txt
chmod 600 ~/.config/clawdbot/gemini-key.txt
```

Option 3 - Run setup wizard:
```bash
cd ~/clawd/skills/node-scaling && node bin/setup.js
```

#### Issue: `node_version`
Swarm requires Node.js 18+. Update:
```bash
# Using nvm
nvm install 20
nvm use 20

# Or direct install
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

#### Issue: `test_failure` (unit/integration)
These indicate a bug or corrupted install. Try:
```bash
cd ~/clawd/skills/node-scaling
rm -rf node_modules
npm install
npm run test:unit
npm run test:integration
```

If still failing, check specific test output for details.

#### Issue: `test_failure` (e2e)
E2E failures usually mean:
1. API key is invalid → Re-run setup with new key
2. Rate limited → Wait a few minutes, try again
3. Network issue → Check internet connectivity

### Machine-Specific Optimization

After running diagnostics, check the machine profile:
```bash
cat ~/.config/clawdbot/swarm-profile.json
```

Use the `recommendations.optimalWorkers` value:
```bash
# Update config with optimal worker count
OPTIMAL=$(cat ~/.config/clawdbot/swarm-profile.json | jq '.recommendations.optimalWorkers // 10')
sed -i "s/max_nodes: .*/max_nodes: $OPTIMAL/" ~/.config/clawdbot/node-scaling.yaml
```

### Low Memory Systems

If `memory.freeGb` < 2:
```yaml
# In node-scaling.yaml, reduce workers
limits:
  max_nodes: 3
  max_concurrent_api: 3
```

### Docker/Container Environments

Ensure container has sufficient resources:
```bash
# Check limits
docker stats --no-stream

# Recommended minimums
# Memory: 512MB per worker
# CPU: 0.5 cores per worker
```

### Rate Limiting

If hitting API rate limits:
```yaml
# In node-scaling.yaml
limits:
  max_concurrent_api: 5  # Reduce this
```

### Complete Reinstall

Nuclear option if nothing else works:
```bash
cd ~/clawd/skills/node-scaling
rm -rf node_modules
rm ~/.config/clawdbot/node-scaling.yaml
rm ~/.config/clawdbot/gemini-key.txt
npm install
node bin/setup.js
```

## Example Prompts That Trigger Node Scaling

- "Research the top 10 programming languages and compare them"
- "Analyze these 5 URLs and summarize each"
- "Find information about these companies: X, Y, Z"
- "Process these documents in parallel"
- "Quickly gather data on these topics"

## Integration Notes

When using node scaling:
1. Always report the speedup to the user ("Completed 5 research tasks in 6s instead of 18s")
2. Show cost estimate if significant
3. Fall back gracefully if node scaling fails
4. Don't use for simple single questions
