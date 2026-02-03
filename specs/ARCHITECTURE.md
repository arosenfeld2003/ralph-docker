# Ralph Docker Architecture

## Overview

Ralph Docker is a containerized autonomous development loop that executes Claude AI in a secure, headless environment. It supports both cloud (Anthropic API) and local (Ollama) model backends.

## Design Principles

1. **Security First**: Non-root execution, credential isolation, containerized environment
2. **Dual Backend**: Seamless switching between cloud and local models
3. **Human Readable**: Stream-json transformed to colored, readable output
4. **Git Integration**: Automatic push capability after commits
5. **Configurable**: Environment variables control all behaviors

## System Architecture

### OAuth Mode (Cloud)

```
┌─────────────────────────────────────────────────┐
│              ralph container                     │
│                                                  │
│  entrypoint.sh                                   │
│       │                                          │
│       ▼                                          │
│  loop.sh                                         │
│       │                                          │
│       ▼                                          │
│  Claude CLI (claude -p)                          │
│       │                                          │
│       ├──▶ format-output.sh (bash formatter)    │
│       │    OR                                   │
│       └──▶ output-formatter.js (node formatter) │
│                                                  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
           ┌──────────────┐
           │ Claude API   │
           │ (Anthropic)  │
           └──────────────┘
```

### Ollama Mode (Local)

```
┌─────────────────────────────────────────────────┐
│           ralph-ollama container                 │
│                                                  │
│  entrypoint.sh                                   │
│       │                                          │
│       ▼                                          │
│  loop.sh                                         │
│       │                                          │
│       ▼                                          │
│  Claude CLI                                      │
│       │                                          │
│  ANTHROPIC_BASE_URL=http://litellm:4000         │
│                                                  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────┐
│            litellm container                     │
│                                                  │
│  Translates Anthropic API → Ollama format        │
│  Port 4000                                       │
│  Health check: /health                           │
│                                                  │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
           ┌──────────────┐
           │   Ollama     │
           │ (host:11434) │
           └──────────────┘
```

## Component Responsibilities

### entrypoint.sh
- Authentication mode detection (OAuth, API key, Ollama)
- Environment validation
- LiteLLM proxy health check (Ollama mode)
- Configuration display
- Command routing (loop, shell, version, test, help)

### loop.sh
- Main iteration loop
- Prompt file selection (build vs plan mode)
- Claude CLI invocation with proper flags
- Output formatting pipeline
- Error detection and handling
- Git push automation
- Iteration counter management

### format-output.sh
- Lightweight bash-based stream-json parser
- ANSI color output
- Tool invocation highlighting
- Error message highlighting

### output-formatter.js
- Rich Node.js-based formatter
- Spinner animations
- Timing metrics
- Tool tracking
- Content truncation

## Docker Services

| Service | Profile | Purpose |
|---------|---------|---------|
| ralph | (default) | OAuth/cloud mode |
| litellm | ollama | API translation proxy |
| ralph-ollama | ollama | Local model execution |

## Volume Mounts

| Mount | Container Path | Mode | Purpose |
|-------|---------------|------|---------|
| WORKSPACE_PATH | /home/ralph/workspace | rw | Project files |
| CLAUDE_CONFIG | /home/ralph/.claude | ro | OAuth credentials |
| litellm-config.yaml | /app/config.yaml | ro | Model definitions |

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| RALPH_MODE | build | build or plan mode |
| RALPH_MAX_ITERATIONS | 0 | Iteration limit (0=unlimited) |
| RALPH_MODEL | opus | Model selection |
| RALPH_OUTPUT_FORMAT | pretty | Output format |
| RALPH_PUSH_AFTER_COMMIT | true | Auto git push |

## Security Model

1. **Container Isolation**: All execution in Docker container
2. **Non-root User**: Runs as `ralph` user
3. **Read-only Credentials**: OAuth credentials mounted read-only
4. **Workspace Isolation**: Project files at /home/ralph/workspace
5. **Credential Cleanup**: Temp credentials removed on exit
6. **No Unnecessary Network**: Only Claude API or Ollama access
