# Ralph Docker Template Usage Guide

## What is Ralph Docker?

Ralph Docker is a **containerized autonomous development loop framework** - not a standalone application. It provides infrastructure for running Claude AI in a secure Docker environment to perform automated development tasks on YOUR application code.

## How to Use This Template

### 1. Project Structure Setup

This framework expects your application code to be organized in a specific structure:

```
your-project/
├── src/                    # Your application source code
│   ├── lib/               # Libraries and utilities
│   ├── services/          # Service layer code
│   └── ...                # Your project structure
├── specs/                 # Your application specifications
│   ├── ARCHITECTURE.md    # Architecture documentation
│   └── FEATURES.md        # Feature specifications
├── tests/                 # Your test suites (optional)
├── IMPLEMENTATION_PLAN.md # Development roadmap
├── AGENTS.md             # Agent operation notes
├── prompts/              # Agent prompts (from this template)
├── scripts/              # Ralph Docker scripts
├── lib/                  # Ralph Docker formatter
└── docker-compose.yml    # Docker configuration
```

### 2. Customizing Agent Prompts

The prompts in `prompts/PROMPT_build.md` and `prompts/PROMPT_plan.md` contain references to `src/*` which should match YOUR project structure:

1. **If your code is in `src/`**: No changes needed
2. **If your code is elsewhere** (e.g., `app/`, `lib/`, etc.): Update the path references in both prompt files
3. **For monorepos**: Specify the exact package path (e.g., `packages/api/src/*`)

### 3. Writing Application Specifications

Create comprehensive specifications in the `specs/` directory:

- **ARCHITECTURE.md**: Technical architecture, design patterns, technology stack
- **FEATURES.md**: Business requirements, user stories, acceptance criteria

The AI agent uses these specifications to understand what to build and how.

### 4. Starting Your Development Loop

#### For Cloud Mode (Claude API):
```bash
# Ensure you have Claude OAuth credentials
docker compose run --rm ralph
```

#### For Local Mode (Ollama):
```bash
# Start Ollama and LiteLLM proxy
docker compose up -d litellm
docker compose run --rm ralph-ollama
```

### 5. Environment Configuration

Configure the framework behavior via `.env`:

```bash
# Core settings
RALPH_MODE=build              # or "plan" for planning mode
RALPH_MAX_ITERATIONS=5        # 0 for unlimited
RALPH_MODEL=opus              # or sonnet, haiku, local models

# Output settings
RALPH_OUTPUT_FORMAT=pretty    # or "json" for raw output
RALPH_PUSH_AFTER_COMMIT=true  # Auto-push git commits

# For Linux users
DOCKER_HOST_IP=172.17.0.1    # Docker host IP for Linux
```

## Example: Setting Up a Node.js Project

1. **Create your source structure**:
```bash
mkdir -p src/lib src/services
echo "export function hello() { return 'world'; }" > src/lib/utils.js
```

2. **Write specifications**:
```bash
cat > specs/FEATURES.md << EOF
# Features

## Core Functionality
- REST API with Express
- PostgreSQL database integration
- JWT authentication
EOF
```

3. **Create implementation plan**:
```bash
cat > IMPLEMENTATION_PLAN.md << EOF
# Implementation Plan

## Priority Items
- [ ] Set up Express server with basic routes
- [ ] Add PostgreSQL connection with migrations
- [ ] Implement JWT authentication middleware
EOF
```

4. **Run Ralph**:
```bash
docker compose run --rm ralph
```

## Common Patterns

### For Existing Projects
1. Copy Ralph Docker files into your project root
2. Adjust prompt paths to match your structure
3. Write specs describing your desired changes
4. Run Ralph in build mode

### For New Projects
1. Start with Ralph Docker template
2. Create empty `src/` directory structure
3. Write comprehensive specs
4. Let Ralph build from scratch

### For Refactoring
1. Document current architecture in specs
2. Describe desired architecture
3. Use plan mode first to strategize
4. Switch to build mode for execution

## Troubleshooting

### "No src/ directory found"
- Create your source directory structure before running Ralph
- Or update prompts to point to your actual code location

### "Agent seems confused about the project"
- Ensure specs/ contains clear, comprehensive documentation
- Check that IMPLEMENTATION_PLAN.md accurately reflects project state
- Verify prompt paths match your directory structure

### "Agent not making expected changes"
- Review the prompt customization section in PROMPT_build.md
- Add project-specific constraints using the "9s pattern"
- Update specs with more detailed requirements

## Best Practices

1. **Start with Clear Specs**: The better your specifications, the better the results
2. **Use Plan Mode First**: For complex changes, plan before building
3. **Incremental Development**: Set iteration limits to review progress
4. **Keep IMPLEMENTATION_PLAN.md Current**: This guides the agent's priorities
5. **Review Commits**: Disable auto-push initially to review changes

## Support

- Report issues: https://github.com/anthropics/claude-code/issues
- Documentation: https://docs.claude.com/en/docs/claude-code/