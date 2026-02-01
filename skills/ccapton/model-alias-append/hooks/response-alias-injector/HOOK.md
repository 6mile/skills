---
name: response-alias-injector
displayName: "Response Alias Injector"
description: "Intercepts responses before they are sent and appends the appropriate model alias to provide transparency about which model generated the response, with configuration change detection and notifications"
type: "response:pre-send"
version: "1.1.0"
author: "OpenClaw Community"
license: "MIT"
category: "response-processing"
tags:
  - "model-alias"
  - "response-enhancement"
  - "transparency"
  - "configuration-monitoring"
homepage: https://docs.openclaw.ai/hooks#response-alias-injector
repository: "https://github.com/ccapton/openclaw-skills/tree/main/hooks/response-alias-injector"
bugs: "https://github.com/ccapton/openclaw-skills/issues"
capabilities:
  - "response-interception"
  - "configuration-monitoring"
  - "dynamic-updates"
metadata:
  {
    "openclaw":
      {
        "emoji": "🏷️",
        "events": ["response:pre-send"],
        "requires": { "config": ["models"] },
        "install": [{ "id": "skill-component", "kind": "skill", "label": "Part of model-alias-append skill" }],
      },
  }
---

# Response Alias Injector Hook

This hook intercepts responses before they are sent and appends the appropriate model alias to provide transparency about which model generated the response, with configuration change detection and notifications.

## Event Type
- `response:pre-send`: Triggered before a response is sent to the user

## Features
- **Response Interception**: Captures the outgoing response before delivery
- **Model Detection**: Determines which model was used to generate the response
- **Alias Lookup**: Looks up the configured alias for that model from configuration
- **Alias Appending**: Appends the alias in the format **{model_alias}** to the response
- **Formatting Preservation**: Preserves any existing formatting or reply tags
- **Configuration Monitoring**: Monitors configuration changes in real-time
- **Update Notifications**: Shows visual notifications when configuration changes occur
- **Dynamic Updates**: Applies configuration changes without requiring restart

## What It Does
When a response is about to be sent:

1. **Intercepts the response** - Captures the response text before sending
2. **Determines the model** - Identifies which model was used to generate the response
3. **Retrieves the alias** - Looks up the configured alias for that model from the configuration
4. **Checks for updates** - Detects if configuration has changed since last response
5. **Appends the alias** - Adds the model alias in the format **{model_alias}** to the response
6. **Adds update notice** - If configuration was recently updated, adds a notification *[Model alias configuration updated]*
7. **Preserves formatting** - Maintains any existing formatting, including reply tags

## Configuration
The hook reads model aliases from your existing configuration automatically. No additional configuration needed. The hook automatically:
- Reads model aliases from your existing configuration
- Appends aliases in the format **{model_alias}**
- Preserves reply tags like [[reply_to_current]] if present
- Monitors configuration changes every 30 seconds
- Shows update notifications when configuration changes are detected

## Output Format
Responses are modified to include the model alias at the end:

```
Original response text...

*[Model alias configuration updated]*

**gemma3:12b-local**
```

The update notification appears only when the configuration has been changed since the last response.

## Requirements
- **Config**: Models must be properly configured with aliases in the openclaw.json configuration file