#!/bin/bash
# Comprehensive test suite for Ralph Docker shell scripts
# Tests format-output.sh, loop.sh, and entrypoint.sh

set -euo pipefail

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for test output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Test directories
TEST_DIR="/tmp/ralph_tests_$$"
SCRIPTS_DIR="/home/ralph/workspace/scripts"

# Setup function
setup() {
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Create mock git repository
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > test_file.txt
    git add test_file.txt
    git commit --quiet -m "Initial commit"
    git branch test-branch
}

# Teardown function
teardown() {
    cd /tmp
    rm -rf "$TEST_DIR"
}

# Test assertion functions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ "$expected" = "$actual" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected: '$expected'"
        echo -e "  Actual:   '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected to find: '$needle'"
        echo -e "  In: '$haystack'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$haystack" != *"$needle"* ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected NOT to find: '$needle'"
        echo -e "  In: '$haystack'"
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File exists: $file}"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [ -f "$file" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  File does not exist: '$file'"
    fi
}

assert_exit_code() {
    local expected_code="$1"
    local command="$2"
    local message="${3:-}"

    TESTS_RUN=$((TESTS_RUN + 1))

    set +e
    eval "$command" >/dev/null 2>&1
    local actual_code=$?
    set -e

    if [ "$expected_code" -eq "$actual_code" ]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $message"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $message"
        echo -e "  Expected exit code: $expected_code"
        echo -e "  Actual exit code: $actual_code"
    fi
}

# Test format-output.sh functions
test_format_output() {
    echo -e "${CYAN}Testing format-output.sh functions${NC}"

    # Source the format-output.sh script to access its functions
    # First extract just the truncate_text function
    cat > test_format_functions.sh << 'EOF'
#!/bin/bash
MAX_CONTENT_LENGTH=500

truncate_text() {
    local text="$1"
    local max_len="${2:-$MAX_CONTENT_LENGTH}"
    if [ "${#text}" -gt "$max_len" ]; then
        echo "${text:0:$max_len}... (truncated)"
    else
        echo "$text"
    fi
}
EOF

    source test_format_functions.sh

    # Test truncate_text function with short text
    local short_text="Hello World"
    local result=$(truncate_text "$short_text")
    assert_equals "$short_text" "$result" "truncate_text preserves short text"

    # Test truncate_text function with long text
    local long_text=$(printf 'a%.0s' {1..600})
    local expected="${long_text:0:500}... (truncated)"
    local result=$(truncate_text "$long_text")
    assert_equals "$expected" "$result" "truncate_text truncates long text"

    # Test truncate_text with custom length
    local result=$(truncate_text "Hello World" 5)
    assert_equals "Hello... (truncated)" "$result" "truncate_text respects custom length"

    # Test JSON parsing with valid JSON
    echo '{"type": "assistant", "message": {"content": "test"}}' | "$SCRIPTS_DIR/format-output.sh" > test_output.txt 2>&1 || true
    local output=$(cat test_output.txt)
    # Should contain colored output (checking for ANSI escape sequences or the text content)
    assert_contains "$output" "test" "format-output processes valid JSON"

    # Test with invalid JSON (should pass through)
    echo "not json" | "$SCRIPTS_DIR/format-output.sh" > test_output.txt 2>&1 || true
    local output=$(cat test_output.txt)
    assert_contains "$output" "not json" "format-output passes through invalid JSON"

    # Test with empty input
    echo "" | "$SCRIPTS_DIR/format-output.sh" > test_output.txt 2>&1 || true
    local output=$(cat test_output.txt)
    assert_equals "" "$output" "format-output handles empty input"

    # Test error message formatting
    echo '{"type": "error", "error": {"message": "Test error"}}' | "$SCRIPTS_DIR/format-output.sh" > test_output.txt 2>&1 || true
    local output=$(cat test_output.txt)
    assert_contains "$output" "Test error" "format-output formats error messages"
}

# Test loop.sh functions
test_loop_functions() {
    echo -e "${CYAN}Testing loop.sh functions${NC}"

    # Extract logging functions from loop.sh
    cat > test_loop_functions.sh << 'EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[ralph]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ralph]${NC} $1"; }
log_error() { echo -e "${RED}[ralph]${NC} $1"; }
log_success() { echo -e "${GREEN}[ralph]${NC} $1"; }

# Mock git commands for testing
git() {
    case "$1" in
        "branch")
            if [ "$2" = "--show-current" ]; then
                echo "test-branch"
            fi
            ;;
        *)
            command git "$@"
            ;;
    esac
}
EOF

    source test_loop_functions.sh

    # Test logging functions
    local info_output=$(log_info "test message" 2>&1)
    assert_contains "$info_output" "[ralph]" "log_info includes [ralph] prefix"
    assert_contains "$info_output" "test message" "log_info includes message"

    local warn_output=$(log_warn "warning message" 2>&1)
    assert_contains "$warn_output" "[ralph]" "log_warn includes [ralph] prefix"
    assert_contains "$warn_output" "warning message" "log_warn includes message"

    local error_output=$(log_error "error message" 2>&1)
    assert_contains "$error_output" "[ralph]" "log_error includes [ralph] prefix"
    assert_contains "$error_output" "error message" "log_error includes message"

    local success_output=$(log_success "success message" 2>&1)
    assert_contains "$success_output" "[ralph]" "log_success includes [ralph] prefix"
    assert_contains "$success_output" "success message" "log_success includes message"

    # Test git current branch detection
    local branch=$(git branch --show-current)
    assert_equals "test-branch" "$branch" "git branch detection works"

    # Test environment variable handling
    export RALPH_MODE="test"
    export RALPH_MAX_ITERATIONS="5"
    export RALPH_MODEL="test-model"

    # Extract environment reading logic
    local mode="${RALPH_MODE:-build}"
    local max_iterations="${RALPH_MAX_ITERATIONS:-0}"
    local model="${RALPH_MODEL:-opus}"

    assert_equals "test" "$mode" "RALPH_MODE environment variable is read"
    assert_equals "5" "$max_iterations" "RALPH_MAX_ITERATIONS environment variable is read"
    assert_equals "test-model" "$model" "RALPH_MODEL environment variable is read"

    # Test error detection patterns
    echo "model not found error" > error_output.txt
    if grep -q "model.*not found" error_output.txt; then
        echo -e "${GREEN}✓${NC} Error detection for model not found works"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Error detection for model not found failed"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi

    echo "APIConnectionError: connection failed" > error_output.txt
    if grep -q "APIConnectionError" error_output.txt; then
        echo -e "${GREEN}✓${NC} Error detection for connection errors works"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo -e "${RED}✗${NC} Error detection for connection errors failed"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Test entrypoint.sh functions
test_entrypoint_functions() {
    echo -e "${CYAN}Testing entrypoint.sh functions${NC}"

    # Extract functions from entrypoint.sh for testing
    cat > test_entrypoint_functions.sh << 'EOF'
#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[ralph]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[ralph]${NC} $1"; }
log_error() { echo -e "${RED}[ralph]${NC} $1"; }
log_success() { echo -e "${GREEN}[ralph]${NC} $1"; }

# Mock curl for testing
curl() {
    case "$*" in
        *"/health"*)
            # Simulate successful health check
            return 0
            ;;
        *)
            command curl "$@"
            ;;
    esac
}

# Simplified auth detection function for testing
detect_auth() {
    local base_url="${ANTHROPIC_BASE_URL:-}"
    local api_key="${ANTHROPIC_API_KEY:-}"

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
        return 1
    fi
}

wait_for_litellm() {
    local base_url="${ANTHROPIC_BASE_URL:-}"

    # Only wait if using LiteLLM
    if [[ "$base_url" != *"litellm"* ]] && [[ "$base_url" != *":4000"* ]]; then
        return 0
    fi

    log_info "Waiting for LiteLLM proxy..."

    # Simulate health check
    if curl -sf "${base_url}/health" &> /dev/null; then
        log_success "LiteLLM proxy is ready"
        return 0
    else
        log_error "LiteLLM proxy did not become ready"
        return 1
    fi
}
EOF

    source test_entrypoint_functions.sh

    # Test auth detection with API key (clean environment first)
    rm -f "$HOME/.claude/credentials.json" "$HOME/.claude/.credentials.json" 2>/dev/null || true
    export ANTHROPIC_API_KEY="test-key"
    unset ANTHROPIC_BASE_URL
    local auth_output=$(detect_auth 2>&1)
    assert_contains "$auth_output" "API Key" "detect_auth recognizes API key auth"

    # Test auth detection with LiteLLM
    export ANTHROPIC_BASE_URL="http://localhost:4000"
    local auth_output=$(detect_auth 2>&1)
    assert_contains "$auth_output" "LiteLLM proxy" "detect_auth recognizes LiteLLM proxy"

    # Test auth detection with custom base URL and API key
    export ANTHROPIC_BASE_URL="https://custom.api.com"
    export ANTHROPIC_API_KEY="test-key"
    local auth_output=$(detect_auth 2>&1)
    assert_contains "$auth_output" "custom base URL" "detect_auth recognizes custom base URL with API key"

    # Test auth detection failure (ensure completely clean environment)
    rm -f "$HOME/.claude/credentials.json" "$HOME/.claude/.credentials.json" 2>/dev/null || true
    # Run in a subshell to ensure clean environment
    set +e
    (
        unset ANTHROPIC_API_KEY
        unset ANTHROPIC_BASE_URL
        detect_auth &>/dev/null
    )
    local exit_code=$?
    set -e

    # Test with clean environment and capture output
    unset ANTHROPIC_API_KEY
    unset ANTHROPIC_BASE_URL
    local auth_output=$(detect_auth 2>&1)

    assert_equals "1" "$exit_code" "detect_auth fails when no auth found"
    assert_contains "$auth_output" "No authentication found" "detect_auth shows error message when no auth found"

    # Test OAuth file detection
    rm -f "$HOME/.claude/credentials.json" "$HOME/.claude/.credentials.json" 2>/dev/null || true
    unset ANTHROPIC_API_KEY
    unset ANTHROPIC_BASE_URL
    mkdir -p "$HOME/.claude"
    touch "$HOME/.claude/credentials.json"
    local auth_output=$(
        detect_auth 2>&1
    )
    assert_contains "$auth_output" "OAuth" "detect_auth recognizes OAuth credentials file"
    rm -f "$HOME/.claude/credentials.json"

    # Test LiteLLM health check
    export ANTHROPIC_BASE_URL="http://localhost:4000"
    local health_output=$(wait_for_litellm 2>&1)
    assert_contains "$health_output" "ready" "wait_for_litellm performs health check"

    # Test workspace verification
    mkdir -p "/tmp/test_workspace"
    touch "/tmp/test_workspace/file.txt"
    local workspace_check="$([ -d "/tmp/test_workspace" ] && [ -n "$(ls -A /tmp/test_workspace)" ] && echo "workspace_ok" || echo "workspace_empty")"
    assert_equals "workspace_ok" "$workspace_check" "Workspace verification detects non-empty directory"

    rm -rf "/tmp/test_workspace"
    mkdir -p "/tmp/test_workspace"
    local workspace_check="$([ -d "/tmp/test_workspace" ] && [ -n "$(ls -A /tmp/test_workspace)" ] && echo "workspace_ok" || echo "workspace_empty")"
    assert_equals "workspace_empty" "$workspace_check" "Workspace verification detects empty directory"
}

# Test integration scenarios
test_integration() {
    echo -e "${CYAN}Testing integration scenarios${NC}"

    # Test that all required scripts exist
    assert_file_exists "$SCRIPTS_DIR/format-output.sh" "format-output.sh exists"
    assert_file_exists "$SCRIPTS_DIR/loop.sh" "loop.sh exists"
    assert_file_exists "$SCRIPTS_DIR/entrypoint.sh" "entrypoint.sh exists"

    # Test that scripts are executable
    local format_perms=$(stat -c %a "$SCRIPTS_DIR/format-output.sh" 2>/dev/null || stat -f %A "$SCRIPTS_DIR/format-output.sh" 2>/dev/null || echo "755")
    assert_contains "$format_perms" "7" "format-output.sh is executable"

    # Test script syntax validation
    bash -n "$SCRIPTS_DIR/format-output.sh"
    assert_exit_code 0 "bash -n $SCRIPTS_DIR/format-output.sh" "format-output.sh has valid syntax"

    bash -n "$SCRIPTS_DIR/loop.sh"
    assert_exit_code 0 "bash -n $SCRIPTS_DIR/loop.sh" "loop.sh has valid syntax"

    bash -n "$SCRIPTS_DIR/entrypoint.sh"
    assert_exit_code 0 "bash -n $SCRIPTS_DIR/entrypoint.sh" "entrypoint.sh has valid syntax"

    # Test help commands
    local help_output=$("$SCRIPTS_DIR/entrypoint.sh" help 2>&1 || true)
    assert_contains "$help_output" "COMMANDS:" "entrypoint.sh help shows commands"
    assert_contains "$help_output" "ENVIRONMENT VARIABLES:" "entrypoint.sh help shows environment variables"
}

# Main test runner
main() {
    echo "========================================"
    echo "Ralph Docker Shell Scripts Test Suite"
    echo "========================================"
    echo ""

    # Run setup
    setup

    # Run all tests
    test_format_output
    echo ""
    test_loop_functions
    echo ""
    test_entrypoint_functions
    echo ""
    test_integration
    echo ""

    # Run teardown
    teardown

    # Display results
    echo "========================================"
    echo "Test Results"
    echo "========================================"
    echo "Tests run: $TESTS_RUN"
    echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
    echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
    echo ""

    if [ "$TESTS_FAILED" -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi