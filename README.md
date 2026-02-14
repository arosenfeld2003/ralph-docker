# Ralph Docker

Containerized autonomous development loop using the [Ralph Wiggum](https://github.com/ghuntley/how-to-ralph-wiggum) methodology. Point Ralph at any git repo and watch it plan, implement, test, and commit in a loop.

## Quick Start

### Prerequisites
- Docker Desktop (macOS/Windows) or Docker Engine (Linux)
- Anthropic API key or Claude Max subscription

### 1. Authenticate
```bash
# Option A: API key (simplest)
export ANTHROPIC_API_KEY=sk-ant-...

# Option B: Interactive login (one-time)
docker compose run --rm ralph login
```

### 2. Setup your project
```bash
# Interactive setup (asks 4 questions)
WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup

# Or fully automated with a prompt
WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup \
  --prompt "Build a REST API that validates CSV uploads against JSON schema"
```

Setup generates all the files Ralph needs including `ralph.sh`.

### 3. Run Ralph
```bash
cd your-project/
./ralph.sh       # Run the loop
./ralph.sh 5     # Limit to 5 iterations
./ralph.sh plan  # Plan mode (analyze only, don't implement)
```

Ralph creates a new branch for each session (`ralph/project-20260214-123456`), never touching main directly.

## Reviewing Ralph's Work

```bash
# See what Ralph did
git log ralph/project-* --oneline

# Review all changes
git diff main...ralph/project-20260214-123456

# Create a PR when ready
gh pr create --base main --head ralph/project-20260214-123456
```

For detailed session tracking, enable [Entire observability](docs/ADVANCED.md#session-observability-with-entire):
```bash
RALPH_ENTIRE_ENABLED=true ./ralph.sh
```

## How It Works

```
Setup                         Loop
━━━━━━━━━━━━━━━━━━━          ━━━━━━━━━━━━━━━━━━━━━━━
1. Analyze your codebase     1. Read specs & plan
2. Generate project files:    2. Pick highest-priority task
   - specs/                   3. Implement, test, commit
   - AGENTS.md                4. Update plan
   - PROMPT_*.md              5. Push to branch
   - IMPLEMENTATION_PLAN.md   6. Repeat with fresh context
   - ralph.sh
```

## Commands

| Command | Description |
|---------|-------------|
| `loop` | Run the Ralph loop (default) |
| `setup` | Set up a project for Ralph |
| `login` | Authenticate with Claude interactively |
| `shell` | Start an interactive bash shell |
| `test` | Run connectivity tests |

### Setup Flags

| Flag | Description |
|------|-------------|
| `--prompt "text"` | Skip interview with inline prompt |
| `--prompt-file path` | Skip interview with prompt from file |

## Configuration

Basic environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE_PATH` | `.` | Project directory |
| `RALPH_MODE` | `build` | `build` or `plan` |
| `RALPH_MAX_ITERATIONS` | `0` | Max loops, 0 = unlimited |
| `RALPH_MODEL` | `opus` | Model: `opus`, `sonnet`, `haiku` |
| `RALPH_PUSH_AFTER_COMMIT` | `true` | Auto-push after commits |

See [Advanced Configuration](docs/ADVANCED.md) for all options.

## Tips

1. **Clarify your intent first**: The better your project description, the better Ralph performs
2. **Start with plan mode**: Run `./ralph.sh plan 1` to see Ralph's analysis before implementing
3. **Enable observability**: `RALPH_ENTIRE_ENABLED=true` tracks detailed session history
4. **Limit iterations**: Use `./ralph.sh 3` to test with a few iterations first
5. **Rebuild the container**: If you run into login or other issues, add `--build` to force a fresh image rebuild (e.g. `docker compose run --build --rm ralph login`)

## Additional Documentation

- [Advanced Configuration](docs/ADVANCED.md) - Environment variables, observability, security
- [Local Models with Ollama](docs/OLLAMA.md) - Experimental local model support

## License

MIT