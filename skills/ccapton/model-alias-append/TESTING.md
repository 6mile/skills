# Testing the Model Alias Append Skill

This guide explains how to test the model-alias-append skill in an isolated Docker environment.

## Prerequisites

- Docker installed on your system
- Docker Compose installed

## Setup Instructions

1. **Build and start the test environment:**
   ```bash
   ./start-test-env.sh
   ```

2. **Wait for the containers to start** (may take a minute)

## Testing the Skill

1. **Connect to the OpenClaw instance** running on `http://localhost:18789`

2. **Send a test message** to trigger a response

3. **Verify the response** ends with `**{model_alias}**` (e.g., `**gemma3:12b-local**`)

## Testing Dynamic Configuration Updates

1. **Modify the `test-config.json` file** to change model aliases:
   ```json
   {
     "ollama-local/gemma3:12b": {
       "alias": "my-custom-alias"  // Change this to a different alias
     }
   }
   ```

2. **Save the file** and wait up to 30 seconds

3. **Send another message** and verify that the response now uses the new alias

## Stopping the Test Environment

To stop the test environment:
```bash
docker-compose down
```

To view logs in real-time:
```bash
docker-compose logs -f
```

## Troubleshooting

- If the skill doesn't appear to be working, check the logs with `docker-compose logs`
- Make sure the configuration file is valid JSON
- The skill should automatically detect configuration changes within 30 seconds