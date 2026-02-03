# Ralph Docker

Containerized autonomous development loop using the Ralph Wiggum methodology.

## What is Ralph?

Ralph is an **autonomous coding agent** that iteratively works on your project:

1. Reads your specifications (`specs/*.md`)
2. Picks a task from `IMPLEMENTATION_PLAN.md`
3. Implements, tests, and commits
4. Updates the plan
5. Repeats until done

This Docker setup provides:
- **Security isolation** - Ralph runs with `--dangerously-skip-permissions`, so containerization limits blast radius
- **Two backends** - Use Claude API (cloud) or Ollama (local models)
- **Human-readable output** - Formatted console output instead of raw JSON
- **macOS Keychain integration** - Seamlessly use your Max subscription

---

## Two Operating Modes

| Mode | Backend | Cost | Model Quality | Setup |
|------|---------|------|---------------|-------|
| **OAuth (Max)** | Claude API (cloud) | Included in Max subscription | Best (Opus) | Easy |
| **Ollama** | Local models | Free | Good (depends on model) | Requires Ollama |

### When to use each:

**Use OAuth/Max when:**
- You have a Claude Max subscription ($100/mo or $200/mo Pro)
- You want the best model quality (Opus)
- You're working on complex tasks requiring strong reasoning
- Cost is not a concern (included in subscription)

**Use Ollama when:**
- You want completely free operation
- Privacy is critical (code never leaves your machine)
- You're okay with potentially lower quality output
- You want unlimited iterations without any rate limits

---

## Prerequisites

### For Both Modes
- Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- Git

### For OAuth/Max Mode (macOS only currently)
- Claude Max subscription
- Logged in via `claude auth login`
- Credentials stored in macOS Keychain

### For Ollama Mode
- [Ollama](https://ollama.com) installed and running
- At least one model pulled (e.g., `ollama pull qwen2.5-coder:7b`)

---

## Quick Start

### OAuth/Max Mode (Recommended)

```bash
cd ~/repos/claude/claudecode/ralph-docker

# Run on current directory
./scripts/run-with-keychain.sh up ralph

# Run on a specific project
WORKSPACE_PATH=/path/to/project ./scripts/run-with-keychain.sh up ralph

# Limit iterations (recommended for testing)
WORKSPACE_PATH=/path/to/project RALPH_MAX_ITERATIONS=3 \
  ./scripts/run-with-keychain.sh up ralph

# Plan mode (analyze only, don't implement)
RALPH_MODE=plan WORKSPACE_PATH=/path/to/project \
  ./scripts/run-with-keychain.sh up ralph
```

### Ollama Mode (Local/Free)

```bash
# 1. Make sure Ollama is running
ollama serve

# 2. Pull a model if you haven't
ollama pull qwen2.5-coder:7b

# 3. Run Ralph
cd ~/repos/claude/claudecode/ralph-docker
WORKSPACE_PATH=/path/to/project RALPH_MAX_ITERATIONS=3 \
  docker compose --profile ollama up ralph-ollama
```

---

## Setting Up Your Project

Ralph expects a specific project structure:

```
your-project/
├── specs/                    # Requirements (what to build)
│   └── feature.md
├── IMPLEMENTATION_PLAN.md    # Task list (what Ralph works through)
├── AGENTS.md                 # Build/test commands (optional)
└── src/                      # Your source code
```

### Example: Creating a New Project

```bash
mkdir -p ~/projects/my-app/specs
cd ~/projects/my-app
git init

# 1. Write your spec
cat > specs/app.md << 'EOF'
# My App Specification

## Overview
A CLI tool that does X, Y, Z.

## Requirements
- Feature A: description
- Feature B: description

## Technical Constraints
- Use Node.js
- No external dependencies
EOF

# 2. Create initial implementation plan
cat > IMPLEMENTATION_PLAN.md << 'EOF'
# Implementation Plan

## Priority Tasks
- [ ] Set up project structure (package.json, etc.)
- [ ] Implement Feature A
- [ ] Implement Feature B
- [ ] Add tests
- [ ] Add error handling

## Completed
(Ralph will move items here as they're done)
EOF

# 3. Create AGENTS.md (tells Ralph how to build/test)
cat > AGENTS.md << 'EOF'
# Build & Test Commands

## Install
```bash
npm install
```

## Test
```bash
npm test
```

## Run
```bash
node index.js
```
EOF

# 4. Initial commit
git add . && git commit -m "Initial project setup"

# 5. Run Ralph
cd ~/repos/claude/claudecode/ralph-docker
WORKSPACE_PATH=~/projects/my-app RALPH_MAX_ITERATIONS=5 \
  ./scripts/run-with-keychain.sh up ralph
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE_PATH` | `.` | Project directory to mount |
| `RALPH_MODE` | `build` | `build` (implement) or `plan` (analyze only) |
| `RALPH_MAX_ITERATIONS` | `0` | Max loops, 0 = unlimited |
| `RALPH_MODEL` | `opus` | Model: `opus`, `sonnet`, `haiku`, or `ollama/model` |
| `RALPH_OUTPUT_FORMAT` | `pretty` | `pretty` or `json` (raw) |
| `RALPH_PUSH_AFTER_COMMIT` | `true` | Git push after commits |
| `DOCKER_HOST_IP` | (auto) | Linux users: set to `172.17.0.1` |

### Using a .env File

```bash
cp .env.example .env
# Edit .env with your settings
```

---

## Cost Considerations

### OAuth/Max Mode

| Subscription | Monthly Cost | What You Get |
|--------------|--------------|--------------|
| Claude Max | $100/month | ~45x more usage than Pro |
| Claude Max Pro | $200/month | ~90x more usage than Pro |

**Within your subscription**, Ralph usage is included. However:
- Extended thinking and large contexts consume more of your quota
- Running many iterations can use significant quota
- Monitor usage at https://claude.ai/settings

**Recommendation:** Start with `RALPH_MAX_ITERATIONS=3` to test, then increase.

### Ollama Mode

**Completely free** - models run locally on your hardware.

| Model | VRAM Required | Quality |
|-------|---------------|---------|
| qwen2.5-coder:7b | ~5GB | Good for simple tasks |
| qwen2.5-coder:14b | ~10GB | Better reasoning |
| qwen2.5-coder:32b | ~20GB | Best local option |
| devstral | ~14GB | Strong coding model |

**Trade-offs:**
- Free but slower than cloud
- Quality varies by model
- Requires GPU for reasonable speed
- No rate limits

---

## Architecture

### OAuth Mode Flow

```
┌─────────────────────────────────────────────────────────┐
│  run-with-keychain.sh                                   │
│  1. Extract OAuth token from macOS Keychain             │
│  2. Write to ~/.claude/.credentials.json                │
│  3. Start Docker container                              │
│  4. Clean up credentials on exit                        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  ralph container                                        │
│  ┌─────────────────────────────────────────────────────┐│
│  │ entrypoint.sh → loop.sh → format-output.sh         ││
│  │      │                                              ││
│  │      ▼                                              ││
│  │ Claude CLI (reads ~/.claude/.credentials.json)      ││
│  └─────────────────────────────────────────────────────┘│
│                          │                              │
│            Mounted: /home/ralph/workspace               │
│            Mounted: /home/ralph/.claude                 │
└──────────────────────────┼──────────────────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  Claude API     │
                  │  (Anthropic)    │
                  └─────────────────┘
```

### Ollama Mode Flow

```
┌─────────────────────────────────────────────────────────┐
│  ralph-ollama container                                 │
│  ┌─────────────────────────────────────────────────────┐│
│  │ entrypoint.sh → loop.sh → format-output.sh         ││
│  │      │                                              ││
│  │      ▼                                              ││
│  │ Claude CLI                                          ││
│  │ ANTHROPIC_BASE_URL=http://litellm:4000              ││
│  └─────────────────────────────────────────────────────┘│
└──────────────────────────┼──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│  litellm container                                      │
│  Translates Anthropic API format → Ollama API format    │
└──────────────────────────┼──────────────────────────────┘
                           │
                           ▼
                  ┌─────────────────┐
                  │  Ollama         │
                  │  (host machine) │
                  └─────────────────┘
```

---

## Troubleshooting

### OAuth Mode Issues

**"Could not find Claude credentials in Keychain"**
```bash
# Log in first
claude auth login
```

**"No authentication found"**
- Make sure you're using `./scripts/run-with-keychain.sh`, not plain `docker compose`
- The script extracts credentials from Keychain and makes them available to Docker

**Container can't write to ~/.claude**
- The volume mount needs write access for Claude CLI to store session data
- Check Docker has permission to access your home directory

### Ollama Mode Issues

**"Model not found"**
```bash
# Check what models you have
ollama list

# Pull the model you need
ollama pull qwen2.5-coder:7b

# Make sure model name matches litellm-config.yaml
# Use format: ollama/model-name:tag
```

**"Connection refused" / "Cannot connect to Ollama"**
```bash
# Make sure Ollama is running
ollama serve

# On Linux, you may need to set DOCKER_HOST_IP
DOCKER_HOST_IP=172.17.0.1 docker compose --profile ollama up ralph-ollama
```

**LiteLLM healthcheck fails**
```bash
# Check LiteLLM logs
docker compose --profile ollama logs litellm

# Verify Ollama is reachable from container
docker compose --profile ollama run --rm litellm curl http://host.docker.internal:11434/api/tags
```

### General Issues

**"Prompt file not found"**
- Ralph looks for `PROMPT_build.md` or `PROMPT_plan.md` in the workspace first
- Falls back to built-in prompts at `/home/ralph/prompts/`

**Git push fails**
- Ralph tries to push after commits
- If there's no remote or you don't want this: `RALPH_PUSH_AFTER_COMMIT=false`

**Loop runs forever**
- Set `RALPH_MAX_ITERATIONS=N` to limit iterations
- Use Ctrl+C to stop manually

---

## Files Reference

```
ralph-docker/
├── Dockerfile              # Main container image
├── docker-compose.yml      # Service definitions
├── litellm.Dockerfile      # LiteLLM proxy image
├── litellm-config.yaml     # Ollama model mappings
├── .env.example            # Configuration template
├── scripts/
│   ├── entrypoint.sh       # Container startup
│   ├── loop.sh             # Main Ralph loop
│   ├── format-output.sh    # JSON → human readable
│   ├── run-with-keychain.sh    # macOS credential helper
│   └── extract-credentials.sh  # Keychain extraction
├── lib/
│   └── output-formatter.js # Rich output formatter (Node.js)
└── prompts/
    ├── PROMPT_build.md     # Build mode instructions
    └── PROMPT_plan.md      # Plan mode instructions
```

---

## Security Notes

1. **Container Isolation**: Ralph runs with `--dangerously-skip-permissions` which auto-approves all tool calls. The container provides isolation so Ralph can only affect the mounted workspace.

2. **Credential Handling**:
   - OAuth tokens are extracted from Keychain temporarily
   - Written to `~/.claude/.credentials.json` only during container run
   - Automatically cleaned up when container stops
   - File has 600 permissions (owner read/write only)

3. **Workspace Access**: Ralph has full read/write access to your mounted workspace. Don't mount sensitive directories you don't want modified.

4. **Git Operations**: Ralph will commit and push to the current branch. Use a feature branch if you want to review changes before merging.

---

## Tips for Best Results

1. **Write clear specs**: The better your `specs/*.md` files, the better Ralph performs

2. **Start small**: Begin with `RALPH_MAX_ITERATIONS=1` to see what Ralph does

3. **Review commits**: Check git history to see what Ralph changed

4. **Use plan mode first**: Run with `RALPH_MODE=plan` to see Ralph's analysis before implementing

5. **Provide AGENTS.md**: Tell Ralph how to build and test your project

6. **Keep IMPLEMENTATION_PLAN.md updated**: Ralph reads and writes this file to track progress

---

## License

MIT
