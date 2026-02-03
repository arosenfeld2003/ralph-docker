# Ralph Docker Features

## Core Features

### 1. Dual Authentication Modes

**OAuth Mode (Cloud)**
- Uses Claude Code credentials from ~/.claude/
- Requires Max subscription
- Full model access (opus, sonnet, haiku)
- macOS Keychain integration for secure credential extraction

**Ollama Mode (Local)**
- Uses LiteLLM proxy for API translation
- No subscription required
- Privacy-preserving (all local)
- Pre-configured models: qwen2.5-coder, deepseek, codellama, llama, mistral

### 2. Operational Modes

**Build Mode** (RALPH_MODE=build)
- Implementation-focused workflow
- Reads PROMPT_build.md
- Executes code changes
- Runs tests
- Creates commits

**Plan Mode** (RALPH_MODE=plan)
- Analysis-focused workflow
- Reads PROMPT_plan.md
- No code execution
- Creates implementation plans

### 3. Output Formatting

**Pretty Format** (RALPH_OUTPUT_FORMAT=pretty)
- Human-readable colored output
- Tool name highlighting (yellow)
- Assistant text in cyan
- Error highlighting (red)
- Success messages (green)

**JSON Format** (RALPH_OUTPUT_FORMAT=json)
- Raw stream-json output
- Useful for debugging
- Machine parseable

### 4. Iteration Control

- RALPH_MAX_ITERATIONS=0: Unlimited iterations
- RALPH_MAX_ITERATIONS=N: Stop after N iterations
- Graceful stopping between iterations

### 5. Git Integration

- Automatic branch detection
- Optional auto-push after commits (RALPH_PUSH_AFTER_COMMIT)
- Graceful push failure handling for new branches
- Works with any git remote

### 6. Prompt System

**Default Prompts**
- Built into container at /home/ralph/prompts/
- PROMPT_build.md for build mode
- PROMPT_plan.md for plan mode

**Project Prompts**
- Place PROMPT_build.md or PROMPT_plan.md in project root
- Overrides default prompts
- Project-specific customization

### 7. Error Handling

- Model not found detection (LiteLLM)
- Connection error detection (Ollama)
- Authentication error detection (OAuth)
- Critical error stopping (prevents infinite loops)
- Raw output display for debugging

### 8. CLI Commands

| Command | Description |
|---------|-------------|
| loop | Run the main loop (default) |
| shell | Interactive bash for debugging |
| version | Show Claude CLI version |
| test | Run connectivity tests |
| help | Show help information |

## Supported Models

### Cloud Models
- opus (claude-opus-4)
- sonnet (claude-sonnet-4)
- haiku (claude-haiku)

### Ollama Models (via LiteLLM)
- ollama/qwen2.5-coder:32b (recommended)
- ollama/qwen2.5-coder:14b
- ollama/qwen2.5-coder:7b
- ollama/deepseek-coder-v2
- ollama/deepseek-coder-v2:16b
- ollama/codellama:34b
- ollama/codellama:13b
- ollama/codellama:7b
- ollama/llama3.1:70b
- ollama/llama3.1:8b
- ollama/llama3.2:3b
- ollama/mistral:7b
- ollama/mixtral:8x7b
- ollama/devstral:latest

## Security Features

1. **Non-root Execution**: Container runs as `ralph` user
2. **Credential Isolation**: OAuth credentials mounted read-only
3. **Workspace Boundaries**: Project at /home/ralph/workspace only
4. **Cleanup on Exit**: Temporary credentials automatically removed
5. **macOS Keychain**: No plaintext credential storage on macOS
