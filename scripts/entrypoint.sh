#!/bin/bash
# Ralph Docker Entrypoint
# Handles auth detection, command routing, and environment setup

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${CYAN}[ralph]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[ralph]${NC} $1"
}

log_error() {
    echo -e "${RED}[ralph]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[ralph]${NC} $1"
}

# Environment variable validation functions
validate_ralph_mode() {
    local mode="${RALPH_MODE:-}"
    if [ -n "$mode" ] && [ "$mode" != "build" ] && [ "$mode" != "plan" ]; then
        log_error "Invalid RALPH_MODE: '$mode'"
        log_error "Valid values: build, plan"
        log_error "Leave unset to use default: build"
        return 1
    fi
}

validate_ralph_output_format() {
    local format="${RALPH_OUTPUT_FORMAT:-}"
    if [ -n "$format" ] && [ "$format" != "pretty" ] && [ "$format" != "json" ]; then
        log_error "Invalid RALPH_OUTPUT_FORMAT: '$format'"
        log_error "Valid values: pretty, json"
        log_error "Leave unset to use default: pretty"
        return 1
    fi
}

validate_ralph_max_iterations() {
    local max_iter="${RALPH_MAX_ITERATIONS:-}"
    if [ -n "$max_iter" ]; then
        # Check if it's a valid non-negative integer
        if ! [[ "$max_iter" =~ ^[0-9]+$ ]]; then
            log_error "Invalid RALPH_MAX_ITERATIONS: '$max_iter'"
            log_error "Must be a non-negative integer (0 for unlimited)"
            log_error "Leave unset to use default: 0"
            return 1
        fi
    fi
}

validate_ralph_push_after_commit() {
    local push="${RALPH_PUSH_AFTER_COMMIT:-}"
    if [ -n "$push" ] && [ "$push" != "true" ] && [ "$push" != "false" ]; then
        log_error "Invalid RALPH_PUSH_AFTER_COMMIT: '$push'"
        log_error "Valid values: true, false"
        log_error "Leave unset to use default: true"
        return 1
    fi
}

validate_ralph_model() {
    local model="${RALPH_MODEL:-}"
    if [ -n "$model" ]; then
        # Allow common Claude model names or ollama/* pattern
        case "$model" in
            opus|sonnet|haiku|claude-*|ollama/*)
                # Valid model names
                ;;
            *)
                log_error "Invalid RALPH_MODEL: '$model'"
                log_error "Valid values: opus, sonnet, haiku, claude-*, ollama/*"
                log_error "Examples: opus, sonnet, claude-3-sonnet, ollama/llama2"
                log_error "Leave unset to use default: opus"
                return 1
                ;;
        esac
    fi
}

# Validate all environment variables
validate_environment() {
    local validation_failed=false

    if ! validate_ralph_mode; then
        validation_failed=true
    fi

    if ! validate_ralph_output_format; then
        validation_failed=true
    fi

    if ! validate_ralph_max_iterations; then
        validation_failed=true
    fi

    if ! validate_ralph_push_after_commit; then
        validation_failed=true
    fi

    if ! validate_ralph_model; then
        validation_failed=true
    fi

    if [ "$validation_failed" = true ]; then
        log_error "Environment variable validation failed"
        log_error "Fix the above errors and try again"
        return 1
    fi
}

# Detect authentication mode
detect_auth() {
    local base_url="${ANTHROPIC_BASE_URL:-}"
    local api_key="${ANTHROPIC_API_KEY:-}"

    # Check if using LiteLLM proxy (Ollama mode) - check both URL patterns and API key
    if [[ "$base_url" == *"litellm"* ]] || [[ "$base_url" == *":4000"* ]]; then
        log_info "Auth mode: LiteLLM proxy -> Ollama (local)"
        return 0
    elif [ -n "$api_key" ] && [ -n "$base_url" ]; then
        log_info "Auth mode: API Key with custom base URL"
        return 0
    elif [ -n "$api_key" ]; then
        log_info "Auth mode: API Key"
        return 0
    elif [ -f "$HOME/.claude/.credentials.json" ]; then
        log_info "Auth mode: OAuth credentials file"
        return 0
    elif [ -f "$HOME/.claude/credentials.json" ]; then
        log_info "Auth mode: OAuth credentials"
        return 0
    else
        log_error "No authentication found!"
        log_error "Option 1: Set ANTHROPIC_API_KEY environment variable"
        log_error "Option 2: Run 'docker compose run --rm ralph login' to authenticate interactively"
        log_error "For Ollama: Use --profile ollama with docker compose"
        return 1
    fi
}

# Wait for LiteLLM proxy to be ready
wait_for_litellm() {
    local base_url="${ANTHROPIC_BASE_URL:-}"
    local api_key="${ANTHROPIC_API_KEY:-}"

    # Only wait if using LiteLLM
    if [[ "$base_url" != *"litellm"* ]] && [[ "$base_url" != *":4000"* ]]; then
        return 0
    fi

    log_info "Waiting for LiteLLM proxy..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        # Try health endpoint with API key
        if curl -sf -H "Authorization: Bearer ${api_key}" "${base_url}/health" &> /dev/null; then
            echo ""
            log_success "LiteLLM proxy is ready"
            return 0
        fi

        echo -ne "\r${CYAN}[ralph]${NC} Waiting for LiteLLM... attempt $attempt/$max_attempts"
        sleep 2
        attempt=$((attempt + 1))
    done

    echo ""
    log_error "LiteLLM proxy did not become ready"
    log_error "Check if Ollama is running on the host: ollama serve"
    return 1
}

# Verify workspace is mounted
verify_workspace() {
    if [ ! -d "/home/ralph/workspace" ] || [ -z "$(ls -A /home/ralph/workspace 2>/dev/null)" ]; then
        log_warn "Workspace appears empty"
        log_warn "Mount your project: -v /path/to/project:/home/ralph/workspace"
    fi
}

# Check if Entire CLI is available and enabled
entire_available() {
    [ "${RALPH_ENTIRE_ENABLED:-false}" = "true" ] && command -v entire &>/dev/null
}

# Set up Entire session observability (gracefully degrades if unavailable)
setup_entire() {
    [ "${RALPH_ENTIRE_ENABLED:-false}" != "true" ] && return 0
    command -v entire &>/dev/null || { log_warn "Entire binary not found"; return 0; }
    git rev-parse --git-dir &>/dev/null || { log_warn "No git repo for Entire"; return 0; }

    local flags="--strategy ${RALPH_ENTIRE_STRATEGY:-manual-commit}"
    [ "${RALPH_ENTIRE_PUSH_SESSIONS:-true}" = "false" ] && flags="$flags --skip-push-sessions"

    if entire enable $flags --force 2>&1; then
        # Fix hooks: entire enable writes hooks using "go run .../main.go" which requires
        # Go to be installed. Replace with the "entire" binary which is already available.
        local settings=".claude/settings.json"
        if [ -f "$settings" ] && grep -q 'go run.*entire/main.go' "$settings"; then
            sed -i 's|go run \${CLAUDE_PROJECT_DIR}/cmd/entire/main.go|entire|g' "$settings"
            log_info "Fixed Entire hooks to use binary instead of go run"
        fi
        log_success "Entire enabled (${RALPH_ENTIRE_STRATEGY:-manual-commit})"
    else
        log_warn "Entire enable failed, continuing without observability"
    fi
}

# Display configuration
show_config() {
    local base_url="${ANTHROPIC_BASE_URL:-}"
    local backend="Claude API (cloud)"

    if [[ "$base_url" == *"litellm"* ]] || [[ "$base_url" == *":4000"* ]]; then
        backend="LiteLLM -> Ollama (local)"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph Loop - Containerized"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Mode:       ${RALPH_MODE:-build}"
    echo "  Model:      ${RALPH_MODEL:-opus}"
    echo "  Format:     ${RALPH_OUTPUT_FORMAT:-pretty}"
    echo "  Max Iter:   ${RALPH_MAX_ITERATIONS:-0} (0=unlimited)"
    echo "  Push:       ${RALPH_PUSH_AFTER_COMMIT:-true}"
    echo "  Backend:    $backend"
    if [ "${RALPH_ENTIRE_ENABLED:-false}" = "true" ]; then
        local entire_status="enabled (${RALPH_ENTIRE_STRATEGY:-manual-commit})"
        command -v entire &>/dev/null || entire_status="enabled (binary missing)"
        echo "  Entire:     $entire_status"
    else
        echo "  Entire:     disabled"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main command routing
main() {
    local cmd="${1:-loop}"
    shift || true

    case "$cmd" in
        loop)
            validate_environment || exit 1
            detect_auth || exit 1
            wait_for_litellm || exit 1
            verify_workspace
            setup_entire
            show_config
            exec /home/ralph/scripts/loop.sh "$@"
            ;;
        entire-status)
            entire_available && entire status || log_warn "Entire not available"
            ;;
        setup)
            validate_environment || exit 1
            detect_auth || exit 1
            wait_for_litellm || exit 1
            verify_workspace
            log_info "Starting workspace setup..."
            exec /home/ralph/scripts/setup-workspace.sh "$@"
            ;;
        login)
            log_info "Starting interactive Claude login..."
            exec claude auth login
            ;;
        shell)
            log_info "Starting interactive shell..."
            exec /bin/bash
            ;;
        version)
            claude --version
            ;;
        test)
            validate_environment || exit 1
            detect_auth || exit 1
            wait_for_litellm || exit 1
            log_success "All checks passed!"
            claude --version
            ;;
        help|--help|-h)
            cat << 'EOF'
Ralph Docker - Containerized Ralph Loop

COMMANDS:
  loop            Run the Ralph loop (default)
  setup           Set up a project for Ralph (interactive interview + file generation)
                    --prompt "text"    Provide a detailed project prompt (skips interview, auto-overwrites)
                    --prompt-file path Provide prompt from a file (path relative to your WORKSPACE_PATH)
  login           Authenticate with Claude interactively (credentials persist in ~/.claude volume)
  shell           Start an interactive bash shell
  version         Show Claude CLI version
  test            Run connectivity tests
  entire-status   Show Entire session observability status
  help            Show this help message

AUTHENTICATION:
  Option 1: ANTHROPIC_API_KEY environment variable
  Option 2: docker compose run --rm ralph login (interactive, persists in ~/.claude volume)

ENVIRONMENT VARIABLES:
  ANTHROPIC_API_KEY       Anthropic API key (simplest auth method)
  RALPH_MODE              build|plan (default: build)
  RALPH_MAX_ITERATIONS    Max iterations, 0=unlimited (default: 0)
  RALPH_MODEL             Model name (default: opus, or ollama/model for local)
  RALPH_OUTPUT_FORMAT     pretty|json (default: pretty)
  RALPH_PUSH_AFTER_COMMIT Push to git after commits (default: true)

  RALPH_ENTIRE_ENABLED        Enable Entire session tracking (default: false)
  RALPH_ENTIRE_STRATEGY       manual-commit|auto-commit (default: manual-commit)
  RALPH_ENTIRE_PUSH_SESSIONS  Push checkpoints on git push (default: true)
  RALPH_ENTIRE_LOG_LEVEL      Entire log verbosity (default: warn)

VOLUMES:
  /home/ralph/workspace   Your project directory
  /home/ralph/.claude     Claude credentials and config

EXAMPLES:
  # API key mode
  ANTHROPIC_API_KEY=sk-... docker compose run --rm ralph

  # Set up a new project (interactive interview, generates all files)
  WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup

  # Set up with a detailed prompt (replaces existing files)
  WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup --prompt "Problem: ..."

  # Set up from a prompt file (path is relative to WORKSPACE_PATH)
  WORKSPACE_PATH=/path/to/project docker compose run --rm ralph setup --prompt-file specs/prompt.md

  # Interactive login (one-time, credentials persist in ~/.claude volume)
  docker compose run --rm ralph login

  # After login, just run
  docker compose up ralph

  # Ollama mode (local models via LiteLLM proxy)
  docker compose --profile ollama up ralph-ollama

  # Plan mode with 5 iterations
  RALPH_MODE=plan RALPH_MAX_ITERATIONS=5 docker compose up ralph

  # Interactive shell for debugging
  docker compose run --rm ralph shell
EOF
            ;;
        *)
            log_error "Unknown command: $cmd"
            log_info "Run 'help' for usage information"
            exit 1
            ;;
    esac
}

main "$@"
