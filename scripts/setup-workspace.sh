#!/bin/bash
# Ralph Setup - Interactive workspace setup with Claude generation
# Runs inside the Docker container to prepare any repo for the Ralph loop

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[ralph]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ralph]${NC} $1"; }
log_error() { echo -e "${RED}[ralph]${NC} $1"; }
log_success() { echo -e "${GREEN}[ralph]${NC} $1"; }

MODEL="${RALPH_MODEL:-opus}"

# ─── Parse arguments ─────────────────────────────────────────────────

PROMPT_TEXT=""
PROMPT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --prompt)
            PROMPT_TEXT="$2"
            shift 2
            ;;
        --prompt-file)
            PROMPT_FILE="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

# Resolve prompt from file if specified
if [ -n "$PROMPT_FILE" ]; then
    if [ ! -f "$PROMPT_FILE" ]; then
        log_error "Prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    PROMPT_TEXT=$(cat "$PROMPT_FILE")
fi

# ─── Verify workspace ────────────────────────────────────────────────

if [ ! -d "/home/ralph/workspace" ] || [ -z "$(ls -A /home/ralph/workspace 2>/dev/null)" ]; then
    log_error "Workspace is empty. Mount your project:"
    log_error "  WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup"
    exit 1
fi

cd /home/ralph/workspace

if ! git rev-parse --git-dir &>/dev/null; then
    log_error "Not a git repository. Initialize first:"
    log_error "  cd your-project && git init && git add . && git commit -m 'Initial commit'"
    exit 1
fi

# ─── Check for existing Ralph files ─────────────────────────────────

EXISTING_FILES=()
for f in AGENTS.md IMPLEMENTATION_PLAN.md PROMPT_plan.md PROMPT_build.md ralph.sh; do
    [ -f "$f" ] && EXISTING_FILES+=("$f")
done
[ -d "specs" ] && EXISTING_FILES+=("specs/")

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
    if [ -n "$PROMPT_TEXT" ]; then
        # When a prompt is provided, auto-overwrite without confirmation
        log_info "Overwriting existing Ralph files: ${EXISTING_FILES[*]}"
    else
        echo ""
        log_warn "Found existing Ralph files: ${EXISTING_FILES[*]}"
        echo ""
        read -p "Overwrite them? [y/N] " -r overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            log_info "Setup cancelled. Existing files preserved."
            exit 0
        fi
        echo ""
    fi
fi

# ─── Interview ───────────────────────────────────────────────────────

if [ -n "$PROMPT_TEXT" ]; then
    # Prompt provided via --prompt or --prompt-file — skip interactive interview
    log_info "Using provided prompt (${#PROMPT_TEXT} chars)"
    PROJECT_GOAL="(see detailed prompt below)"
    TECH_STACK=""
    BUILD_CMD=""
    TEST_CMD=""
else
    echo ""
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Ralph Setup${NC}"
    echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # 1. Project goal (required)
    PROJECT_GOAL=""
    while [ -z "$PROJECT_GOAL" ]; do
        read -p "In one sentence, what is the goal of this project? " -r PROJECT_GOAL
        if [ -z "$PROJECT_GOAL" ]; then
            log_warn "Project goal is required."
        fi
    done

    # 2. Tech stack (optional)
    echo ""
    read -p "What tech stack? (press Enter to auto-detect from codebase) " -r TECH_STACK

    # 3. Build command (optional)
    echo ""
    read -p "Build command? (press Enter to auto-detect) " -r BUILD_CMD

    # 4. Test command (optional)
    echo ""
    read -p "Test command? (press Enter to auto-detect) " -r TEST_CMD

    echo ""
fi

# ─── Assemble prompt ─────────────────────────────────────────────────

SKILLS_FILE="/home/ralph/skills/ralph.md"
if [ ! -f "$SKILLS_FILE" ]; then
    log_error "Skills template not found at $SKILLS_FILE"
    exit 1
fi

# Read the ralph.md skill template
SKILL_TEMPLATE=$(cat "$SKILLS_FILE")

# Build the context block
if [ -n "$PROMPT_TEXT" ]; then
    # Detailed prompt mode — pass the full prompt as project context
    CONTEXT="The user has provided a detailed project prompt. Do NOT use AskUserQuestion — use the prompt below as the project description and goals.

DETAILED PROJECT PROMPT:
${PROMPT_TEXT}

TECH STACK: Auto-detect from the codebase. Examine existing files (package.json, requirements.txt, go.mod, Cargo.toml, etc.) to determine the stack.
BUILD COMMAND: Auto-detect from the codebase.
TEST COMMAND: Auto-detect from the codebase."
else
    # Interactive mode — use interview answers
    CONTEXT="The user has already answered the interview questions. Do NOT use AskUserQuestion — use these answers directly:

PROJECT GOAL: ${PROJECT_GOAL}
"

    if [ -n "$TECH_STACK" ]; then
        CONTEXT+="TECH STACK: ${TECH_STACK}
"
    else
        CONTEXT+="TECH STACK: Auto-detect from the codebase. Examine existing files (package.json, requirements.txt, go.mod, Cargo.toml, etc.) to determine the stack.
"
    fi

    if [ -n "$BUILD_CMD" ]; then
        CONTEXT+="BUILD COMMAND: ${BUILD_CMD}
"
    else
        CONTEXT+="BUILD COMMAND: Auto-detect from the codebase.
"
    fi

    if [ -n "$TEST_CMD" ]; then
        CONTEXT+="TEST COMMAND: ${TEST_CMD}
"
    else
        CONTEXT+="TEST COMMAND: Auto-detect from the codebase.
"
    fi
fi

CONTEXT+="
IMPORTANT OVERRIDES:
- Skip the Initial Assessment step (step 1) — the user has confirmed they want to set up.
- Skip ALL AskUserQuestion calls — all answers are provided above.
- Do NOT ask about creating an initial spec — skip step 9.
- Proceed directly through steps 2-8 using the answers above.
- For ralph.sh, use this exact RALPH_DOCKER line: RALPH_DOCKER=\"\${RALPH_DOCKER:-\$HOME/repos/claude/claudecode/ralph-docker}\"
- Make ralph.sh executable after creating it."

ASSEMBLED_PROMPT="${CONTEXT}

--- SKILL TEMPLATE (follow steps 2-8) ---

${SKILL_TEMPLATE}"

# ─── Generate files with Claude ──────────────────────────────────────

log_info "Generating project files with Claude ($MODEL)..."
echo ""

claude -p "$ASSEMBLED_PROMPT" \
    --dangerously-skip-permissions \
    --model "$MODEL" \
    --output-format text

CLAUDE_EXIT=$?

if [ "$CLAUDE_EXIT" -ne 0 ]; then
    log_error "Claude exited with code $CLAUDE_EXIT"
    exit 1
fi

# Make ralph.sh executable if it was created
[ -f "ralph.sh" ] && chmod +x ralph.sh

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${GREEN}Setup Complete${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
if [ -n "$PROMPT_TEXT" ]; then
    DISPLAY_GOAL="${PROMPT_TEXT:0:80}"
    [ ${#PROMPT_TEXT} -gt 80 ] && DISPLAY_GOAL+="..."
    echo "  Project Prompt: $DISPLAY_GOAL"
else
    echo "  Project Goal: $PROJECT_GOAL"
fi
echo ""
echo "  Created files:"
for f in AGENTS.md IMPLEMENTATION_PLAN.md PROMPT_plan.md PROMPT_build.md ralph.sh; do
    if [ -f "$f" ]; then
        echo -e "    ${GREEN}+${NC} $f"
    fi
done
if [ -d "specs" ]; then
    echo -e "    ${GREEN}+${NC} specs/"
fi
echo ""
echo "  Next steps:"
echo "    1. Add spec files to specs/ for each topic"
echo "    2. Run: ./ralph.sh plan    (analyze & plan)"
echo "    3. Review IMPLEMENTATION_PLAN.md"
echo "    4. Run: ./ralph.sh         (build)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
