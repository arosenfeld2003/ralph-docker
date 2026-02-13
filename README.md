# Ralph Docker

Containerized autonomous development loop using the [Ralph Wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) methodology. Point it at any git repo, run `setup`, and Ralph takes over — planning, implementing, testing, and committing in a loop.

## Quick Start

### 1. Authenticate

```bash
# Option A: API key (simplest)
export ANTHROPIC_API_KEY=sk-ant-...

# Option B: Interactive login (one-time, credentials persist in ~/.claude volume)
docker compose run --rm ralph login
```

### 2. Clarify your intent

Before running `setup`, have a short conversation with Claude (or any LLM) to sharpen your project goal into a clear, one-sentence statement. The `setup` interview asks "What is the goal of this project?" — and the quality of Ralph's specs, plans, and prompts depends directly on how precise your answer is.

Good: *"Build a REST API that ingests CSV uploads, validates them against a JSON schema, and stores the results in PostgreSQL"*

Vague: *"Make a data processing app"*

A five-minute chat to nail down scope, tech stack preferences, and success criteria saves hours of Ralph iterating in the wrong direction.

### 3. Set up your project

```bash
WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup
```

This runs a short interview (project goal, tech stack, build/test commands), then uses Claude to analyze your codebase and generate all the files Ralph needs — including `ralph.sh`.

### 4. Run Ralph

```bash
cd your-project/

# Recommended: enable session observability (see "Reviewing What Ralph Did" below)
RALPH_ENTIRE_ENABLED=true ./ralph.sh

# Or without observability
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

## Reviewing What Ralph Did

Ralph works autonomously, so understanding what it accomplished is important. There are two complementary ways to follow along.

### Git history (always available)

Ralph creates a dedicated branch for each session and commits after every task. This is your primary audit trail:

```bash
# See what branch Ralph created
git branch --list 'ralph/*'

# Review the commit log for a session
git log ralph/myproject-20260212-143022 --oneline

# See exactly what changed in each commit
git log ralph/myproject-20260212-143022 -p

# Diff the entire session against where it started
git diff main...ralph/myproject-20260212-143022

# Check Ralph's progress tracker
cat IMPLEMENTATION_PLAN.md
```

When you're happy with the changes, merge via PR:

```bash
gh pr create --base main --head ralph/myproject-20260212-143022
```

### Session observability with Entire (recommended)

[Entire CLI](https://github.com/entireio/cli) captures detailed session metadata — prompts sent, responses received, files modified, and token usage — on a shadow git branch (`entire/checkpoints/v1`). This gives you deeper insight than commit diffs alone, especially for understanding *why* Ralph made certain decisions.

**Enable it:**

```bash
# For a single run
RALPH_ENTIRE_ENABLED=true ./ralph.sh

# Or set it permanently in .env
echo "RALPH_ENTIRE_ENABLED=true" >> .env
```

**Review session data:**

```bash
# Quick status check (inside the container or after a run)
docker compose run --rm ralph entire-status

# View the checkpoints branch directly
git log entire/checkpoints/v1 --oneline

# See session details
git show entire/checkpoints/v1
```

When `RALPH_PUSH_AFTER_COMMIT=true` (the default), Entire checkpoints are pushed alongside code, so your remote has the full audit trail too.

**How it works under the hood:**
- On startup, Ralph runs `entire enable` in the workspace git repo
- Each iteration's Claude session is captured as a checkpoint on the shadow branch
- Checkpoints are pushed via Entire's pre-push hook when Ralph pushes code
- If the Entire binary is missing or setup fails, Ralph continues normally — it never blocks the loop

## How It Works

```
setup                          loop
━━━━━━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
1. Interviews you (shell)      1. Reads specs & plan from disk
2. Passes answers to Claude    2. Picks highest-priority task
3. Claude analyzes codebase    3. Implements, tests, commits
4. Generates project files:    4. Updates IMPLEMENTATION_PLAN.md
   - AGENTS.md                 5. Pushes to branch
   - PROMPT_*.md               6. Repeats with fresh context
   - specs/
   - IMPLEMENTATION_PLAN.md
   - ralph.sh
```

### Branch safety

Ralph **always creates a new branch** for each session:
- Branch name: `ralph/<workspace>-<YYYYMMDD-HHMMSS>`
- Your main/master branch is never modified directly
- Review Ralph's changes via `git log` or create a PR to merge

### Prompt resolution

The container's `loop.sh` checks for prompt files in this order:
1. `PROMPT_build.md` / `PROMPT_plan.md` in the mounted workspace (your project)
2. Built-in prompts at `/home/ralph/prompts/` (fallback)

The `setup` command generates customized prompts in your project, so those are used automatically.

## Workspace Requirements

Your project directory just needs to be a **git repository**. Everything else is created by `setup`:

```
your-project/           <- Mount as /home/ralph/workspace
├── .git/               <- Required: must be a git repo
├── specs/              <- Created by setup
│   └── feature.md
├── AGENTS.md           <- Created by setup
├── IMPLEMENTATION_PLAN.md  <- Created by setup
├── PROMPT_plan.md      <- Created by setup
├── PROMPT_build.md     <- Created by setup
├── ralph.sh            <- Created by setup
└── src/                <- Your source code (any structure)
```

## Commands

| Command | Description |
|---------|-------------|
| `loop` | Run the Ralph loop (default) |
| `setup` | Set up a project for Ralph (interactive interview + file generation) |
| `login` | Authenticate with Claude interactively (persists in `~/.claude` volume) |
| `shell` | Start an interactive bash shell |
| `version` | Show Claude CLI version |
| `test` | Run connectivity tests |
| `entire-status` | Show Entire session observability status |
| `help` | Show help message |

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
| `RALPH_ENTIRE_ENABLED` | `false` | Enable Entire session tracking (recommended) |
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
│   ├── entrypoint.sh       # Container startup & command routing
│   ├── loop.sh             # Main Ralph loop
│   ├── setup-workspace.sh  # Interactive project setup
│   └── format-output.sh    # JSON → human readable
├── skills/
│   └── ralph.md            # Setup template (used by setup command)
├── lib/
│   └── output-formatter.js # Rich output formatter (Node.js)
└── prompts/
    ├── PROMPT_build.md     # Build mode instructions (fallback)
    └── PROMPT_plan.md      # Plan mode instructions (fallback)
```

## Tips

1. **Run setup first**: `WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup` to generate all project files
2. **Enable Entire**: `RALPH_ENTIRE_ENABLED=true` gives you full session history — see exactly what Claude did and why
3. **Start with plan mode**: Run `./ralph.sh plan 1` to see Ralph's analysis before implementing
4. **Limit iterations**: Use `./ralph.sh 3` to test with a few iterations first
5. **Review commits**: `git log ralph/<branch> -p` shows every change Ralph made
6. **Write clear specs**: The better your `specs/*.md` files, the better Ralph performs

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
