Prepare a repository for the Ralph Wiggum autonomous development workflow.

## Overview

The Ralph Wiggum methodology uses a bash loop to repeatedly run Claude on a codebase, with each iteration starting fresh, reading current state from disk, completing one task, committing, and exiting. The plan file persists between iterations as shared state.

## 1. Initial Assessment

First, check the current directory:
- Run `pwd` and `ls -la` to understand the current location
- Check if this is a git repository with `git status`
- Look for any existing Ralph files (AGENTS.md, IMPLEMENTATION_PLAN.md, specs/, PROMPT_*.md, ralph.sh)

If Ralph files already exist, ask the user if they want to:
- Overwrite existing files
- Update/extend existing configuration
- Cancel the setup

## 2. Interview for AGENTS.md

The core interview focuses on the project goal. Use AskUserQuestion:

### Primary Question: Project Goal

"In one sentence, what is the ultimate goal of this project?"

This becomes:
- The ULTIMATE GOAL in PROMPT_plan.md
- The guiding context in AGENTS.md

Examples:
- "Build a CLI tool that helps developers manage their dotfiles"
- "Create a web app for tracking personal fitness goals"
- "Develop an API service for processing image uploads"

### Tech Stack Selection (New Projects)

For new projects or projects without existing code, propose an appropriate tech stack based on the project goal:

1. Analyze the project goal and determine the best-fit technologies
2. Present your recommendation with reasoning:
   - Why this stack fits the project goal
   - Key advantages for this use case
   - Any trade-offs considered

3. Use AskUserQuestion to confirm:
   "Based on your goal, I recommend this tech stack:

   [Your recommended stack with brief reasoning]

   Does this work for you, or would you prefer something different?"

   Options:
   - **Use recommended stack** - Proceed with the suggestion
   - **Different preference** - Let user specify their preferred technologies

**Stack Selection Guidelines:**
- CLI tools: Consider Go, Rust, or Node.js based on complexity
- Web apps: React/Next.js, Vue/Nuxt, or simpler alternatives based on scope
- APIs: Node.js/Express, Python/FastAPI, Go, based on performance needs
- Data processing: Python with appropriate libraries
- System tools: Rust or Go for performance-critical work

Record the chosen tech stack in AGENTS.md under a "Tech Stack" section.

### Follow-up: Build/Test Commands

After tech stack is confirmed, either:
- For existing projects: Ask for build/test commands
- For new projects with chosen stack: Use standard commands for that stack

If the user doesn't know yet, use sensible defaults that Ralph can discover and update.

## 3. Create Directory Structure

Create these directories if they don't exist:
- `specs/` - For specification files (one per topic)

## 4. Create AGENTS.md

Create AGENTS.md focused on the project goal:

```markdown
## Project Goal

[Project goal from interview]

## Tech Stack

[Chosen tech stack with brief rationale]

## Build & Run

[Build command, or "TBD - Ralph will discover"]

## Validation

- Tests: `[test command, or "TBD"]`
- Typecheck: `[if applicable]`
- Lint: `[if applicable]`

## Operational Notes

_Ralph will update this section as it learns about the codebase._

### Codebase Patterns

_Document patterns as they emerge._
```

## 5. Create IMPLEMENTATION_PLAN.md

```markdown
# Implementation Plan

## Current Focus

_No tasks yet. Run the planning loop to analyze specs and generate tasks._

## Completed

_None yet._
```

## 6. Create PROMPT_plan.md

Use the source directory from interview (default: `src/`):

```markdown
0a. Study `specs/*` with up to 250 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.
0c. Study `[source_dir]/*` with up to 250 parallel Sonnet subagents to understand shared utilities & components.
0d. For reference, the application source code is in `[source_dir]/*`.

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and use up to 500 Sonnet subagents to study existing source code in `[source_dir]/*` and compare it against `specs/*`. Use an Opus subagent to analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a bullet point list sorted in priority of items yet to be implemented. Ultrathink. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns. Study @IMPLEMENTATION_PLAN.md to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents.

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first.

ULTIMATE GOAL: [Project goal from interview]. Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at specs/FILENAME.md. If you create a new element then document the plan to implement it in @IMPLEMENTATION_PLAN.md using a subagent.
```

## 7. Create PROMPT_build.md

```markdown
0a. Study `specs/*` with up to 500 parallel Sonnet subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md.
0c. For reference, the application source code is in `[source_dir]/*`.

1. Your task is to implement functionality per the specifications using parallel subagents. Follow @IMPLEMENTATION_PLAN.md and choose the most important item to address. Before making changes, search the codebase (don't assume not implemented) using Sonnet subagents. You may use up to 500 parallel Sonnet subagents for searches/reads and only 1 Sonnet subagent for build/tests. Use Opus subagents when complex reasoning is needed (debugging, architectural decisions).
2. After implementing functionality or resolving problems, run the tests for that unit of code that was improved. If functionality is missing then it's your job to add it as per the application specifications. Ultrathink.
3. When you discover issues, immediately update @IMPLEMENTATION_PLAN.md with your findings using a subagent. When resolved, update and remove the item.
4. When the tests pass, update @IMPLEMENTATION_PLAN.md, then `git add -A` then `git commit` with a message describing the changes. After the commit, `git push`.

99999. Important: When authoring documentation, capture the why — tests and implementation importance.
999999. Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
9999999. As soon as there are no build or test errors create a git tag. If there are no git tags start at 0.0.0 and increment patch by 1 for example 0.0.1 if 0.0.0 does not exist.
99999999. You may add extra logging if required to debug issues.
999999999. Keep @IMPLEMENTATION_PLAN.md current with learnings using a subagent — future work depends on this to avoid duplicating efforts. Update especially after finishing your turn.
9999999999. When you learn something new about how to run the application, update @AGENTS.md using a subagent but keep it brief.
99999999999. For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.md using a subagent even if it is unrelated to the current piece of work.
999999999999. Implement functionality completely. Placeholders and stubs waste efforts and time redoing the same work.
9999999999999. When @IMPLEMENTATION_PLAN.md becomes large periodically clean out the items that are completed from the file using a subagent.
99999999999999. If you find inconsistencies in the specs/* then use an Opus 4.5 subagent with 'ultrathink' requested to update the specs.
999999999999999. IMPORTANT: Keep @AGENTS.md operational only — status updates and progress notes belong in `IMPLEMENTATION_PLAN.md`. A bloated AGENTS.md pollutes every future loop's context.
```

## 8. Create ralph.sh

Create a thin wrapper script that delegates to ralph-docker for containerized execution:

```bash
#!/bin/bash
# Ralph - Autonomous development loop via Docker
# Usage: ./ralph.sh [plan] [max_iterations]
# Auth:  Set ANTHROPIC_API_KEY, or run: docker compose -f "$RALPH_DOCKER/docker-compose.yml" run --rm ralph login

RALPH_DOCKER="${RALPH_DOCKER:-$HOME/repos/claude/claudecode/ralph-docker}"

if [ ! -d "$RALPH_DOCKER" ]; then
    echo "Error: ralph-docker not found at $RALPH_DOCKER"
    echo "Clone it: git clone <repo-url> $RALPH_DOCKER"
    echo "Or set RALPH_DOCKER=/path/to/ralph-docker"
    exit 1
fi

export WORKSPACE_PATH="$(cd "$(dirname "$0")" && pwd)"

if [ "$1" = "plan" ]; then
    export RALPH_MODE=plan
    [ -n "$2" ] && export RALPH_MAX_ITERATIONS="$2"
elif [[ "$1" =~ ^[0-9]+$ ]]; then
    export RALPH_MODE=build
    export RALPH_MAX_ITERATIONS="$1"
else
    export RALPH_MODE=build
fi

cd "$RALPH_DOCKER" && exec docker compose up ralph
```

Make the script executable: `chmod +x ralph.sh`

## 9. Create Initial Spec (Optional)

Use AskUserQuestion to ask:
"Would you like to create an initial spec file now? If so, what topic should it cover?"

If yes:
- Ask for the topic name (will become filename)
- Create `specs/[topic-name].md` with basic structure:

```markdown
# [Topic Name]

## Overview

[One-sentence description from user]

## Requirements

_Define requirements here_

## Acceptance Criteria

_Define how to verify this is complete_
```

## 10. Summary

After setup, provide a summary:

```
Ralph Wiggum Setup Complete!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Project Goal: [goal]

Created files:
- AGENTS.md
- IMPLEMENTATION_PLAN.md
- PROMPT_plan.md
- PROMPT_build.md
- ralph.sh
- specs/

Requires: Docker Desktop + ANTHROPIC_API_KEY or `docker compose run --rm ralph login`

Next steps:
1. Create spec files in specs/ for each topic
2. Run: ./ralph.sh plan
3. Review IMPLEMENTATION_PLAN.md
4. Run: ./ralph.sh

Commands:
- ./ralph.sh              # Build, unlimited
- ./ralph.sh 20           # Build, max 20
- ./ralph.sh plan         # Plan, unlimited
- ./ralph.sh plan 5       # Plan, max 5
```
