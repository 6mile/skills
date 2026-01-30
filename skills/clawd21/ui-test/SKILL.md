---
name: ui-test
description: Describe your UI tests in plain English. The agent runs them in a real browser, screenshots every step, and sends you a walkthrough video with a pass/fail report — no selectors or code needed.
metadata: {"clawdbot":{"emoji":"🧪"}}
---

# UI Test — Plain English E2E Testing (🧪)

Describe your UI tests in plain English. The agent runs them in a real browser, screenshots every step, and sends you a walkthrough video with a pass/fail report — no selectors or code needed.

*Made in 🤠 Texas ❤️ [PlebLab](https://pleblab.dev)*

![UI Test — Describe it. I'll test it.](https://files.catbox.moe/3yezuk.png)

## Workflow

1. **Create** — User names a test and describes steps in plain English
2. **Run** — Agent opens the clawd browser, executes each step, screenshots each action
3. **Export** — Agent generates a Playwright `.spec.ts` from the verified steps
4. **CI/CD** — User drops the script into their test suite, runs with `npx playwright test`

## Agent Execution Flow

When running a test:

1. Load test definition: `node scripts/ui-test.js get "<name>"`
2. Start clawd browser: `browser action=start profile=clawd`
3. Navigate to the test URL
4. For each plain English step:
   a. Interpret what the user means (click, type, assert, wait, etc.)
   b. Use `browser action=snapshot` to see the page
   c. Use `browser action=act` with the appropriate request (click/type/press/etc.)
   d. Take a screenshot after each step
   e. Record what selector/ref was used and whether it passed
5. Save run results: `node scripts/ui-test.js save-run "<name>" passed=true/false`
6. Report results to user with pass/fail per step

When exporting to Playwright:

1. Load the test definition and most recent successful run
2. Map each plain English step to Playwright API calls based on what worked during execution
3. Generate a `.spec.ts` file with proper imports, test structure, and assertions
4. Save to the user's project or a specified output path

## Step Interpretation Guide

The agent should interpret plain English steps like:

| User says | Browser action | Playwright equivalent |
|-----------|---------------|----------------------|
| "click the Sign In button" | `act: click ref="Sign In button"` | `page.getByRole('button', {name: 'Sign In'}).click()` |
| "type hello@test.com in the email field" | `act: type ref="email" text="hello@test.com"` | `page.getByLabel('Email').fill('hello@test.com')` |
| "verify the dashboard shows Welcome" | `snapshot` + check text | `expect(page.getByText('Welcome')).toBeVisible()` |
| "wait for the page to load" | `act: wait` | `page.waitForLoadState('networkidle')` |
| "click the hamburger menu" | `act: click` (find menu icon) | `page.getByRole('button', {name: 'menu'}).click()` |
| "scroll down" | `act: evaluate fn="window.scrollBy(0,500)"` | `page.evaluate(() => window.scrollBy(0, 500))` |
| "check the Remember Me checkbox" | `act: click ref="Remember Me"` | `page.getByLabel('Remember Me').check()` |
| "select 'USD' from the currency dropdown" | `act: select values=["USD"]` | `page.getByLabel('Currency').selectOption('USD')` |
| "take a screenshot" | `browser action=screenshot` | `page.screenshot({path: 'step-N.png'})` |
| "verify URL contains /dashboard" | check current URL | `expect(page).toHaveURL(/dashboard/)` |

## Commands

Run via: `node ~/workspace/skills/ui-test/scripts/ui-test.js <command>`

| Command | Description |
|---------|-------------|
| `create <name> [url]` | Create a new test |
| `add-step <name> <step>` | Add a plain English step |
| `set-steps <name> <json>` | Replace all steps |
| `set-url <name> <url>` | Set the test URL |
| `get <name>` | Show test definition |
| `list` | List all tests |
| `remove <name>` | Delete a test |
| `save-run <name> ...` | Save execution results |
| `runs [name]` | Show run history |
| `export <name> [outfile]` | Export as Playwright script |

## Export Format

Generated Playwright files include:
- Proper TypeScript imports
- `test.describe` block with test name
- `test.beforeEach` with navigation to base URL
- Each step as a sequential action with comments showing the original English
- Assertions where the user said "verify", "check", "should", "expect"
- Screenshots on failure

## Screenshots & Video

During test execution, the agent should:

1. **Before each step**: take a screenshot → save as `step-NN-before.jpg`
2. **After each step**: take a screenshot → save as `step-NN-after.jpg`
3. **On failure**: take a screenshot → save as `step-NN-FAIL.jpg`
4. **Save the URL**: after each screenshot, save the current page URL to a `.url` sidecar file

Screenshots are saved to: `~/.ui-tests/runs/<slug>-<timestamp>/`

### Saving URLs for the Video

After taking each screenshot, **always save the current page URL** to a sidecar file so the walkthrough video can display a URL bar:

```bash
# After saving step-03-payment-page.jpg, save the URL:
echo "https://example.com/checkout/payment" > ~/.ui-tests/runs/<folder>/step-03-payment-page.url
```

The URL can be captured from:
- `browser action=act` response → `url` field
- `browser action=snapshot` response → `url` field  
- `browser action=screenshot` response → check the current tab URL
- JavaScript evaluate: `window.location.href`

**The sidecar file must match the screenshot filename** (same name, `.url` extension instead of `.jpg`/`.png`).

After the run completes, generate a scrolling walkthrough video:
```bash
bash ~/workspace/skills/ui-test/scripts/make-walkthrough.sh ~/.ui-tests/runs/<folder>
```

### Video Features

- **URL bar** — dark grey bar at the top of every frame showing the page URL (read from `.url` sidecar files), with 🔒 prefix for HTTPS. Looks like a real browser chrome.
- **1280×720 viewport** — proper widescreen; URL bar takes 40px, page content gets 680px
- **Smooth scrolling** — tall screenshots pan top-to-bottom at 300px/s with 1s hold at each end
- **Short screenshots** — centered on black canvas, held for 2s
- **Step annotations** — each segment shows a text overlay (e.g. "Step 1: Click the Sign In button") pulled from the test definition, with a fade-in effect
- **Fallback labels** — if no test definition is found, derives labels from screenshot filenames

Then send the video to the chat.

## Storage

- Test definitions: `~/.ui-tests/<slug>.json`
- Run history: `~/.ui-tests/runs/<slug>-<timestamp>/run.json`
- Screenshots: `~/.ui-tests/runs/<slug>-<timestamp>/step-*.jpg`
- Video: `~/.ui-tests/runs/<slug>-<timestamp>/walkthrough.mp4`
- Exported scripts: user-specified path or `./tests/<slug>.spec.ts`
