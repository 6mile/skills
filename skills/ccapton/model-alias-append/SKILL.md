---
name: model-alias-append
version: "1.0.0"
displayName: "Model Alias Append"
description: "Automatically appends the model alias to the end of every response with integrated hook functionality and configuration change notifications. Use when transparency about which model generated each response is needed."
author: "OpenClaw Community"
contributors:
  - "ccapton"
category: "utility"
tags:
  - "model"
  - "alias"
  - "transparency"
  - "configuration"
  - "monitoring"
license: "MIT"
repository: **Coming soon**
  - "model-alias"
  - "response-enhancement"
  - "transparency"
  - "configuration-monitoring"
requirements:
  - "configured-model-aliases"
capabilities:
  - "response-interception"
  - "configuration-monitoring"
  - "dynamic-updates"
hooks:
  - name: "response-alias-injector"
    type: "response:pre-send"
    description: "Automatically injects model alias at the end of every response with configuration change detection"
---

# Model Alias Append Skill with Integrated Hook

## Overview
This skill automatically appends the model alias to the end of every response to provide transparency about which model generated each response. It integrates both a response interceptor hook and skill functionality for seamless operation, with added configuration change detection and notifications.

## Features
- **Automatic Model Detection**: Automatically detects the model used for each response
- **Configuration Reading**: Reads model aliases from the openclaw.json configuration
- **Alias Appending**: Appends model alias in the format **{model_alias}** to every response
- **Formatting Preservation**: Preserves existing formatting and reply tags
- **Integrated Hook**: Includes response interceptor hook for automatic response processing
- **Configuration Change Detection**: Monitors configuration changes in real-time
- **Update Notifications**: Shows visual notifications when configuration changes occur
- **Dynamic Updates**: Applies configuration changes without requiring restart

## What It Does
Every time a response is sent to the user:

1. **Intercepts the response** - Captures the response text before sending
2. **Determines the model** - Identifies which model was used to generate the response
3. **Retrieves the alias** - Looks up the configured alias for that model from the configuration
4. **Checks for updates** - Detects if configuration has changed since last response
5. **Appends the alias** - Adds the model alias in the format **{model_alias}** to the end of the response
6. **Adds update notice** - If configuration was recently updated, adds a notification *[Model alias configuration updated]*
7. **Preserves formatting** - Maintains any existing formatting, including reply tags

## Requirements
- Models must be properly configured with aliases in the openclaw.json configuration file

## Configuration
The skill reads model aliases from your existing configuration automatically. No additional configuration needed. The skill automatically:
- Reads model aliases from your existing configuration
- Appends aliases in the format **{model_alias}**
- Preserves reply tags like [[reply_to_current]] if present
- Monitors configuration changes every 30 seconds
- Shows update notifications when configuration changes are detected

## Integration
This skill includes both:
1. A response interceptor hook that automatically appends model aliases
2. Manual controls to enable/disable the feature via the manage-hook script
3. Configuration change detection with visual notifications

## Output Format
Responses are modified to include the model alias at the end:

```
Original response text...

*[Model alias config has updated]*

**gemma3:12b-local**
```

The update notification appears only when the configuration has been changed since the last response.
