# Advanced Configuration

## Environment Variables

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

## Using a .env File

```bash
cp .env.example .env
# Edit .env with your settings
```

## Session Observability with Entire

[Entire CLI](https://github.com/entireio/cli) captures detailed session metadata — prompts sent, responses received, files modified, and token usage — on a shadow git branch (`entire/checkpoints/v1`). This gives you deeper insight than commit diffs alone, especially for understanding *why* Ralph made certain decisions.

### Enable it

```bash
# For a single run
RALPH_ENTIRE_ENABLED=true ./ralph.sh

# Or set it permanently in .env
echo "RALPH_ENTIRE_ENABLED=true" >> .env
```

### Review session data

```bash
# Quick status check (inside the container or after a run)
docker compose run --rm ralph entire-status

# View the checkpoints branch directly
git log entire/checkpoints/v1 --oneline

# See session details
git show entire/checkpoints/v1
```

When `RALPH_PUSH_AFTER_COMMIT=true` (the default), Entire checkpoints are pushed alongside code, so your remote has the full audit trail too.

### How it works

- On startup, Ralph runs `entire enable` in the workspace git repo
- Each iteration's Claude session is captured as a checkpoint on the shadow branch
- Checkpoints are pushed via Entire's pre-push hook when Ralph pushes code
- If the Entire binary is missing or setup fails, Ralph continues normally — it never blocks the loop

## Workspace Structure

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

## Prompt Resolution

The container's `loop.sh` checks for prompt files in this order:
1. `PROMPT_build.md` / `PROMPT_plan.md` in the mounted workspace (your project)
2. Built-in prompts at `/home/ralph/prompts/` (fallback)

The `setup` command generates customized prompts in your project, so those are used automatically.

## Files Reference

```
ralph-docker/
├── Dockerfile              # Main container image
├── docker-compose.yml      # Service definitions
├── .env.example            # Configuration template
├── scripts/
│   ├── entrypoint.sh       # Container startup & command routing
│   ├── loop.sh             # Main Ralph loop
│   ├── setup-workspace.sh  # Project setup (interactive or prompt-driven)
│   └── format-output.sh    # JSON → human readable
├── skills/
│   └── ralph.md            # Setup template (used by setup command)
├── lib/
│   └── output-formatter.js # Rich output formatter (Node.js)
└── prompts/
    ├── PROMPT_build.md     # Build mode instructions (fallback)
    └── PROMPT_plan.md      # Plan mode instructions (fallback)
```

## Security

1. **Container Isolation**: Ralph runs with `--dangerously-skip-permissions` which auto-approves all tool calls. The container limits blast radius to the mounted workspace.

2. **Credential Handling**:
   - API keys are passed via environment variable (never written to disk by Ralph)
   - Interactive login credentials persist in the mounted `~/.claude` volume
   - No temporary credential files are created or cleaned up

3. **Workspace Access**: Ralph has full read/write access to your mounted workspace. Don't mount sensitive directories you don't want modified.

4. **Git Operations**: Ralph automatically creates a new branch (`ralph/<workspace>-<timestamp>`) for each session. Changes are committed to this branch, never to main/master directly. Review and merge via PR when satisfied.