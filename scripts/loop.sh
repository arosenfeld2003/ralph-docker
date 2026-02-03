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

# Check for project-specific prompts
if [ -f "PROMPT_${MODE}.md" ]; then
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

# Get current branch
CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

log_info "Starting loop..."
log_info "Prompt: $PROMPT_FILE"
log_info "Model: $MODEL"
log_info "Branch: $CURRENT_BRANCH"
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
check_for_errors() {
    local output_file="$1"

    # Check for model not found (specific LiteLLM error format)
    if grep -q "model.*not found\|OllamaException.*not found" "$output_file" 2>/dev/null; then
        log_error "Model not found: $MODEL"
        echo ""
        log_error "Available models in litellm-config.yaml:"
        echo "  - ollama/qwen2.5-coder:7b"
        echo "  - ollama/qwen2.5-coder:14b"
        echo "  - ollama/qwen2.5-coder:32b"
        echo "  - ollama/devstral"
        echo ""
        log_error "Make sure the model is pulled: ollama pull <model>"
        return 1
    fi

    # Check for connection errors (specific patterns)
    if grep -q "APIConnectionError\|Connection refused\|ECONNREFUSED\|connect ETIMEDOUT" "$output_file" 2>/dev/null; then
        log_error "Connection error - is Ollama running?"
        echo ""
        echo "Start Ollama with: ollama serve"
        return 1
    fi

    # Check for auth errors (more specific patterns to avoid false positives)
    if grep -q '"error".*[Ii]nvalid API key\|"error".*[Uu]nauthorized\|AuthenticationError' "$output_file" 2>/dev/null; then
        log_error "Authentication error"
        return 1
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

    if [ $CLAUDE_EXIT -ne 0 ]; then
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
            local push_output
            if push_output=$(git push origin "$CURRENT_BRANCH" 2>&1); then
                log_success "Push successful"
            elif push_output=$(git push -u origin "$CURRENT_BRANCH" 2>&1); then
                log_success "Push successful (set upstream)"
            else
                log_warn "Push failed: $push_output"
            fi
        fi
    fi

    echo ""
    echo "════════════════════════════════════════════════"
    log_success "ITERATION $ITERATION COMPLETE"
    echo "════════════════════════════════════════════════"
    echo ""

    # Small delay between iterations
    sleep 1
done

echo ""
log_success "Loop finished after $ITERATION iterations"
