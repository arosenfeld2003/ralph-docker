#!/bin/bash
# Ralph Loop - Main loop script with output formatting
# Runs inside the Docker container

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[ralph]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ralph]${NC} $1"; }
log_error() { echo -e "${RED}[ralph]${NC} $1"; }
log_success() { echo -e "${GREEN}[ralph]${NC} $1"; }

# Check if Entire CLI is available and enabled
entire_available() {
    [ "${RALPH_ENTIRE_ENABLED:-false}" = "true" ] && command -v entire &>/dev/null
}

# Change to workspace directory
cd "${RALPH_WORKSPACE:-/home/ralph/workspace}"

# Configuration from environment
MODE="${RALPH_MODE:-build}"
MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-0}"
MODEL="${RALPH_MODEL:-opus}"
OUTPUT_FORMAT="${RALPH_OUTPUT_FORMAT:-pretty}"
PUSH_AFTER_COMMIT="${RALPH_PUSH_AFTER_COMMIT:-true}"

# Determine prompt file
case "$MODE" in
    plan)
        PROMPT_FILE="/home/ralph/prompts/PROMPT_plan.md"
        ;;
    build|*)
        PROMPT_FILE="/home/ralph/prompts/PROMPT_build.md"
        ;;
esac

# Check if using local model (Ollama) - prefer _local variants
IS_LOCAL_MODEL=false
if [[ "$MODEL" == ollama/* ]] || [[ -n "${ANTHROPIC_BASE_URL:-}" && "${ANTHROPIC_BASE_URL:-}" != *"anthropic.com"* ]]; then
    IS_LOCAL_MODEL=true
fi

# Check for project-specific prompts (prefer _local for local models)
if [ "$IS_LOCAL_MODEL" = true ] && [ -f "PROMPT_${MODE}_local.md" ]; then
    PROMPT_FILE="PROMPT_${MODE}_local.md"
    log_info "Using local model prompt: $PROMPT_FILE"
elif [ -f "PROMPT_${MODE}.md" ]; then
    PROMPT_FILE="PROMPT_${MODE}.md"
    log_info "Using project prompt: $PROMPT_FILE"
fi

# Verify prompt exists
if [ ! -f "$PROMPT_FILE" ]; then
    log_error "Prompt file not found: $PROMPT_FILE"
    exit 1
fi

# Build model argument
MODEL_ARG="--model $MODEL"

# Iteration counter
ITERATION=0

# Verify we're in a git repo
if ! git rev-parse --git-dir &>/dev/null; then
    log_error "Not a git repository!"
    log_error "Initialize with: git init && git add . && git commit -m 'Initial commit'"
    exit 1
fi

# Get the workspace name from directory
WORKSPACE_NAME=$(basename "$(pwd)")

# Create a new branch for this Ralph session
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RALPH_BRANCH="ralph/${WORKSPACE_NAME}-${TIMESTAMP}"
ORIGINAL_BRANCH=$(git branch --show-current 2>/dev/null || echo "HEAD")

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    log_warn "Uncommitted changes detected"
    log_info "Stashing changes before creating branch..."
    git stash push -m "Ralph auto-stash before $RALPH_BRANCH"
fi

# Create and checkout the new branch
log_info "Creating branch: $RALPH_BRANCH"
if ! git checkout -b "$RALPH_BRANCH" 2>/dev/null; then
    log_error "Failed to create branch $RALPH_BRANCH"
    exit 1
fi

log_info "Starting loop..."
log_info "Prompt: $PROMPT_FILE"
log_info "Model: $MODEL"
log_info "Branch: $RALPH_BRANCH (from $ORIGINAL_BRANCH)"
log_info "Working dir: $(pwd)"

# Check for IMPLEMENTATION_PLAN.md
if [ -f "IMPLEMENTATION_PLAN.md" ]; then
    log_info "Found IMPLEMENTATION_PLAN.md - will continue from existing progress"
else
    log_warn "No IMPLEMENTATION_PLAN.md found - Ralph will create one"
fi
echo ""

# Temp file for capturing output
OUTPUT_TMP=$(mktemp)
trap 'rm -f "$OUTPUT_TMP"' EXIT

# Output formatting command
format_output() {
    if [ "$OUTPUT_FORMAT" = "pretty" ]; then
        /home/ralph/scripts/format-output.sh
    else
        cat
    fi
}

# Check for critical errors in output
# Only check the result JSON line, not the full conversation
check_for_errors() {
    local output_file="$1"

    # Extract just the final result line (contains "type":"result")
    local result_line
    result_line=$(grep '"type":"result"' "$output_file" 2>/dev/null | tail -1)

    # If no result line, check for startup errors in full output
    if [[ -z "$result_line" ]]; then
        # Check for model not found during startup (LiteLLM specific error)
        if grep -q "OllamaException.*not found\|litellm.*model.*not found" "$output_file" 2>/dev/null; then
            log_error "Model not found: $MODEL"
            echo ""
            log_error "Available models - check litellm-config.yaml or run: ollama list"
            return 1
        fi

        # Check for connection errors
        if grep -q "APIConnectionError\|Connection refused\|ECONNREFUSED" "$output_file" 2>/dev/null; then
            log_error "Connection error - is Ollama running?"
            return 1
        fi
    fi

    # Check result line for errors
    if [[ -n "$result_line" ]]; then
        if echo "$result_line" | grep -q '"is_error":true'; then
            # Extract error message if present
            local errors
            errors=$(echo "$result_line" | grep -o '"errors":\[[^]]*\]' | head -1)
            if [[ -n "$errors" ]]; then
                log_warn "Session completed with errors"
                # Don't fail - Ralph might have partially succeeded
            fi
        fi
    fi

    return 0
}

# Main loop
while true; do
    # Check iteration limit
    if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATION" -ge "$MAX_ITERATIONS" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_success "Reached max iterations: $MAX_ITERATIONS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        break
    fi

    ITERATION=$((ITERATION + 1))
    echo ""
    echo "┌─────────────────────────────────────────────┐"
    echo "│  ITERATION $ITERATION                                  │"
    echo "└─────────────────────────────────────────────┘"
    echo ""

    # Run Claude with the prompt, capture output for error checking
    # -p: Headless mode (non-interactive)
    # --dangerously-skip-permissions: Auto-approve tool calls
    # --output-format=stream-json: Structured output for filtering
    cat "$PROMPT_FILE" | claude -p \
        --dangerously-skip-permissions \
        --output-format=stream-json \
        $MODEL_ARG \
        --verbose 2>&1 | tee "$OUTPUT_TMP" | format_output

    CLAUDE_EXIT=${PIPESTATUS[0]}

    # Check for critical errors
    if ! check_for_errors "$OUTPUT_TMP"; then
        log_error "Critical error detected, stopping loop"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "  Raw error output:"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        # Show last 50 lines of raw output for debugging
        tail -50 "$OUTPUT_TMP"
        exit 1
    fi

    if [ "$CLAUDE_EXIT" -ne 0 ]; then
        log_warn "Claude exited with code $CLAUDE_EXIT"
        # Show some context on non-zero exit
        echo "Last output:"
        tail -20 "$OUTPUT_TMP"
    fi

    # Push changes if configured
    if [ "$PUSH_AFTER_COMMIT" = "true" ]; then
        CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
        if [ -n "$CURRENT_BRANCH" ]; then
            log_info "Pushing to origin/$CURRENT_BRANCH..."
            push_output=""
            if push_output=$(git push origin "$CURRENT_BRANCH" 2>&1); then
                log_success "Push successful"
            elif push_output=$(git push -u origin "$CURRENT_BRANCH" 2>&1); then
                log_success "Push successful (set upstream)"
            else
                log_warn "Push failed (continuing anyway)"
                # Check for common SSH issues
                if echo "$push_output" | grep -q "authenticity of host\|Host key verification"; then
                    log_warn "SSH host key not trusted. Run on host machine:"
                    log_warn "  ssh-keyscan <git-host> >> ~/.ssh/known_hosts"
                elif echo "$push_output" | grep -q "Permission denied\|publickey"; then
                    log_warn "SSH key issue. Ensure ~/.ssh is mounted and keys have correct permissions"
                else
                    echo "$push_output" | head -5
                fi
            fi
        fi
    else
        log_info "Push disabled (RALPH_PUSH_AFTER_COMMIT=false)"
    fi

    echo ""
    echo "════════════════════════════════════════════════"
    log_success "ITERATION $ITERATION COMPLETE"
    if entire_available; then
        checkpoint_info=$(entire status --short 2>/dev/null) && \
            log_info "Entire: $checkpoint_info" || true
    fi
    echo "════════════════════════════════════════════════"
    echo ""

    # Small delay between iterations
    sleep 1
done

echo ""
log_success "Loop finished after $ITERATION iterations"
