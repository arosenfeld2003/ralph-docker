# Ralph Docker

Containerized autonomous development loop using the Ralph Wiggum methodology. Ralph runs Claude Code inside Docker with your Claude subscription credentials, providing security isolation while iterating on your project.

## How It Works

```
/ralph skill          ralph.sh             ralph-docker
━━━━━━━━━━━━━        ━━━━━━━━━━━━━        ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Interviews you     1. Sets workspace    1. Authenticates (API key or login)
2. Creates project       path              2. Starts Docker container
   files:             2. Calls ralph-      3. Mounts your project
   - AGENTS.md           docker            4. Runs Claude in a loop
   - PROMPT_*.md                           5. Reads specs, implements,
   - specs/                                   tests, commits
   - ralph.sh
```

## Quick Start

### 1. Set up your project

Run the `/ralph` skill inside Claude Code in your project directory. It interviews you about your project goal, tech stack, and build commands, then generates all the files Ralph needs — including `ralph.sh`, which calls this repo.

### 2. Run Ralph

```bash
cd your-project/

# Build mode (implement tasks)
./ralph.sh

# Plan mode (analyze only, don't implement)
./ralph.sh plan

# Limit iterations
./ralph.sh 5
./ralph.sh plan 3
```

That's it. `ralph.sh` handles everything: setting the workspace path, starting the Docker container, and running the loop.

## Prerequisites

- **Docker Desktop** (macOS/Windows) or Docker Engine (Linux)
- **Anthropic API key** or **Claude Max subscription**
- **`/ralph` skill** installed in Claude Code (generates project files)

### Authentication

Choose one:

1. **API key** (simplest): Set `ANTHROPIC_API_KEY` environment variable
2. **Interactive login**: Run `docker compose run --rm ralph login` — credentials persist in the mounted `~/.claude` volume

## Branch Safety

Ralph **always creates a new branch** for each session:
- Branch name: `ralph/<workspace>-<YYYYMMDD-HHMMSS>`
- Your main/master branch is never modified directly
- Review Ralph's changes via `git log` or create a PR to merge

## Workspace Requirements

Ralph mounts your project directory into the container at `/home/ralph/workspace`. This directory should be:

1. **A git repository** - Ralph commits changes after each task
2. **Self-contained** - Ralph only sees files inside the mounted directory
3. **Have a specs/ folder** - Tells Ralph what to build
4. **Have IMPLEMENTATION_PLAN.md** - Tells Ralph what to work on

```
your-project/           <- This gets mounted as /home/ralph/workspace
├── .git/               <- REQUIRED: Must be a git repo
├── specs/              <- REQUIRED: Your requirements
│   └── feature.md
├── IMPLEMENTATION_PLAN.md  <- REQUIRED: Task list for Ralph
├── AGENTS.md           <- OPTIONAL: Build/test commands
└── src/                <- Your source code (any structure)
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE_PATH` | `.` | Project directory to mount |
| `RALPH_MODE` | `build` | `build` (implement) or `plan` (analyze only) |
| `RALPH_MAX_ITERATIONS` | `0` | Max loops, 0 = unlimited |
| `RALPH_MODEL` | `opus` | Model: `opus`, `sonnet`, `haiku` |
| `RALPH_OUTPUT_FORMAT` | `pretty` | `pretty` or `json` (raw) |
| `RALPH_PUSH_AFTER_COMMIT` | `true` | Git push after commits |
| `RALPH_DOCKER` | `~/repos/claude/claudecode/ralph-docker` | Path to this repo (set in ralph.sh) |
| `RALPH_ENTIRE_ENABLED` | `false` | Enable Entire session tracking |
| `RALPH_ENTIRE_STRATEGY` | `manual-commit` | `manual-commit` or `auto-commit` |
| `RALPH_ENTIRE_PUSH_SESSIONS` | `true` | Push checkpoints branch on git push |
| `RALPH_ENTIRE_LOG_LEVEL` | `warn` | Entire log verbosity |

### Using a .env File

```bash
cp .env.example .env
# Edit .env with your settings
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Authentication                                         │
│  Option A: ANTHROPIC_API_KEY env var                    │
│  Option B: docker compose run --rm ralph login          │
│            (credentials persist in ~/.claude volume)    │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│  ralph container                                        │
│  ┌─────────────────────────────────────────────────────┐│
│  │ entrypoint.sh → loop.sh → format-output.sh         ││
│  │      │                                              ││
│  │      ▼                                              ││
│  │ Claude CLI (API key or ~/.claude credentials)       ││
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

### Prompt Resolution

The container's `loop.sh` checks for prompt files in this order:
1. `PROMPT_build.md` / `PROMPT_plan.md` in the mounted workspace (your project)
2. Built-in prompts at `/home/ralph/prompts/` (fallback)

Since `/ralph` generates customized prompts in your project, those are used automatically.

### Commands

| Command | Description |
|---------|-------------|
| `loop` | Run the Ralph loop (default) |
| `login` | Authenticate with Claude interactively (persists in `~/.claude` volume) |
| `shell` | Start an interactive bash shell |
| `version` | Show Claude CLI version |
| `test` | Run connectivity tests |
| `entire-status` | Show Entire session observability status |
| `help` | Show help message |

## Session Observability (Entire CLI)

Ralph can optionally capture session metadata (prompts, responses, files modified, token usage) using [Entire CLI](https://github.com/entireio/cli). Data is stored on a shadow git branch (`entire/checkpoints/v1`), keeping your code history clean while providing a durable audit trail.

### Enable

```bash
RALPH_ENTIRE_ENABLED=true ./ralph.sh
```

### How It Works

- On startup, Ralph runs `entire enable` in the workspace git repo
- Each iteration's Claude session is captured as a checkpoint
- Checkpoints are pushed alongside code via Entire's pre-push hook (when `RALPH_PUSH_AFTER_COMMIT=true`)
- If the Entire binary is missing or setup fails, Ralph continues normally with a warning

### Check Status

```bash
docker compose run --rm ralph entire-status
```

## Troubleshooting

**"No authentication found"**
```bash
# Option 1: Set API key
ANTHROPIC_API_KEY=sk-ant-... docker compose up ralph

# Option 2: Login interactively (one-time, credentials persist)
docker compose run --rm ralph login
```

**"ralph-docker not found"**
- `ralph.sh` looks for this repo at `$HOME/repos/claude/claudecode/ralph-docker` by default
- Override with: `export RALPH_DOCKER=/path/to/ralph-docker`

**Git push fails**
- Set `RALPH_PUSH_AFTER_COMMIT=false` if there's no remote or you don't want auto-push

**Loop runs forever**
- Set `RALPH_MAX_ITERATIONS=N` to limit iterations
- Use Ctrl+C to stop manually

**"Prompt file not found"**
- Ralph looks for `PROMPT_build.md` or `PROMPT_plan.md` in the workspace first
- Falls back to built-in prompts at `/home/ralph/prompts/`

## Security

1. **Container Isolation**: Ralph runs with `--dangerously-skip-permissions` which auto-approves all tool calls. The container limits blast radius to the mounted workspace.

2. **Credential Handling**:
   - API keys are passed via environment variable (never written to disk by Ralph)
   - Interactive login credentials persist in the mounted `~/.claude` volume
   - No temporary credential files are created or cleaned up

3. **Workspace Access**: Ralph has full read/write access to your mounted workspace. Don't mount sensitive directories you don't want modified.

4. **Git Operations**: Ralph automatically creates a new branch (`ralph/<workspace>-<timestamp>`) for each session. Changes are committed to this branch, never to main/master directly. Review and merge via PR when satisfied.

## Files Reference

```
ralph-docker/
├── Dockerfile              # Main container image
├── docker-compose.yml      # Service definitions
├── .env.example            # Configuration template
├── scripts/
│   ├── entrypoint.sh       # Container startup
│   ├── loop.sh             # Main Ralph loop
│   └── format-output.sh    # JSON → human readable
├── lib/
│   └── output-formatter.js # Rich output formatter (Node.js)
└── prompts/
    ├── PROMPT_build.md     # Build mode instructions (fallback)
    └── PROMPT_plan.md      # Plan mode instructions (fallback)
```

## Tips

1. **Start with plan mode**: Run `./ralph.sh plan 1` to see Ralph's analysis before implementing
2. **Limit iterations**: Use `./ralph.sh 3` to test with a few iterations first
3. **Review commits**: Check git history to see what Ralph changed
4. **Write clear specs**: The better your `specs/*.md` files, the better Ralph performs
5. **Keep IMPLEMENTATION_PLAN.md updated**: Ralph reads and writes this file to track progress

<details>
<summary><strong>Advanced: Local Models (Ollama)</strong></summary>

Ralph-docker also supports running with local models via Ollama and LiteLLM, though this is experimental and not recommended for production use.

### Prerequisites

- [Ollama](https://ollama.com) installed and running
- At least one model pulled (e.g., `ollama pull qwen2.5-coder:7b`)

### Usage

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

### Available Models

| Model | VRAM Required | Quality |
|-------|---------------|---------|
| qwen2.5-coder:7b | ~5GB | Good for simple tasks |
| qwen2.5-coder:14b | ~10GB | Better reasoning |
| qwen2.5-coder:32b | ~20GB | Best local option |
| devstral | ~14GB | Strong coding model |

### Known Limitations

- Local models cannot reliably drive Claude Code's tool-use protocol
- Models output JSON text but don't actually call tools (Read, Edit, Write, etc.)
- This path exists for future improvement as local models get better at tool use

### Ollama Architecture

```
ralph-ollama container → litellm container → Ollama (host)
```

LiteLLM translates the Anthropic API format to Ollama's API format. Configuration is in `litellm-config.yaml`.

### Ollama Troubleshooting

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

</details>

## License

MIT
