# Local Models with Ollama

Ralph-docker supports running with local models via Ollama and LiteLLM, though this is experimental and not recommended for production use.

## Prerequisites

- [Ollama](https://ollama.com) installed and running
- At least one model pulled (e.g., `ollama pull qwen2.5-coder:7b`)

## Usage

```bash
# 1. Make sure Ollama is running
ollama serve

# 2. Pull a model
ollama pull qwen2.5-coder:7b

# 3. Run with the ollama profile
cd ~/repos/claude/claudecode/ralph-docker
WORKSPACE_PATH=/path/to/project RALPH_MAX_ITERATIONS=3 \
  docker compose --profile ollama up ralph-ollama
```

## Available Models

| Model | VRAM Required | Quality |
|-------|---------------|---------|
| qwen2.5-coder:7b | ~5GB | Good for simple tasks |
| qwen2.5-coder:14b | ~10GB | Better reasoning |
| qwen2.5-coder:32b | ~20GB | Best local option |
| devstral | ~14GB | Strong coding model |

## Known Limitations

- Local models cannot reliably drive Claude Code's tool-use protocol
- Models output JSON text but don't actually call tools (Read, Edit, Write, etc.)
- This path exists for future improvement as local models get better at tool use

## Architecture

```
ralph-ollama container → litellm container → Ollama (host)
```

LiteLLM translates the Anthropic API format to Ollama's API format. Configuration is in `litellm-config.yaml`.

## Troubleshooting

**"Model not found"**
```bash
ollama list                    # Check available models
ollama pull qwen2.5-coder:7b  # Pull what you need
```

**"Connection refused"**
```bash
ollama serve                   # Make sure Ollama is running

# On Linux, set the Docker host IP
DOCKER_HOST_IP=172.17.0.1 docker compose --profile ollama up ralph-ollama
```

**LiteLLM healthcheck fails**
```bash
docker compose --profile ollama logs litellm
```