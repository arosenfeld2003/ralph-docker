#!/bin/bash
# Unit tests for entrypoint.sh functions
# Tests authentication detection, configuration display, and utility functions

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
TEST_DIR="/tmp/entrypoint_tests_$$"
SCRIPTS_DIR="/home/ralph/workspace/scripts"

# Source the entrypoint script functions without running main
# We need to prevent main from executing when sourcing
ENTRYPOINT_SOURCED=true
source <(grep -v '^main "\$@"' "$SCRIPTS_DIR/entrypoint.sh") 2>/dev/null || true

# Setup function
setup() {
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Save original environment
    ORIGINAL_RALPH_MODE="${RALPH_MODE:-}"
    ORIGINAL_CLAUDE_SESSION_KEY="${CLAUDE_SESSION_KEY:-}"
    ORIGINAL_WORKSPACE_PATH="${WORKSPACE_PATH:-}"
}

# Teardown function
teardown() {
    cd /tmp
    rm -rf "$TEST_DIR"

    # Restore original environment
    if [ -n "$ORIGINAL_RALPH_MODE" ]; then
        export RALPH_MODE="$ORIGINAL_RALPH_MODE"
    else
        unset RALPH_MODE
    fi

    if [ -n "$ORIGINAL_CLAUDE_SESSION_KEY" ]; then
        export CLAUDE_SESSION_KEY="$ORIGINAL_CLAUDE_SESSION_KEY"
    else
        unset CLAUDE_SESSION_KEY
    fi

    if [ -n "$ORIGINAL_WORKSPACE_PATH" ]; then
        export WORKSPACE_PATH="$ORIGINAL_WORKSPACE_PATH"
    else
        unset WORKSPACE_PATH
    fi
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

# Test detect_auth function
test_detect_auth_api_key() {
    unset ANTHROPIC_BASE_URL
    export ANTHROPIC_API_KEY="test-api-key"

    local result
    detect_auth >/dev/null 2>&1
    result=$?
    assert_equals "0" "$result" "detect_auth should succeed with API key"

    unset ANTHROPIC_API_KEY
}

test_detect_auth_litellm() {
    export ANTHROPIC_BASE_URL="http://litellm:4000"
    unset ANTHROPIC_API_KEY

    local result
    detect_auth >/dev/null 2>&1
    result=$?
    assert_equals "0" "$result" "detect_auth should succeed with LiteLLM URL"

    unset ANTHROPIC_BASE_URL
}

test_detect_auth_no_auth() {
    unset ANTHROPIC_BASE_URL
    unset ANTHROPIC_API_KEY

    local result=0
    detect_auth >/dev/null 2>&1 || result=$?
    assert_equals "1" "$result" "detect_auth should fail without authentication"
}

# Test logging functions
test_log_functions() {
    # Test log_info
    local info_output=$(log_info "Test info message" 2>&1)
    assert_contains "$info_output" "[ralph]" "log_info should output ralph prefix"
    assert_contains "$info_output" "Test info message" "log_info should output message"

    # Test log_warn
    local warn_output=$(log_warn "Test warning" 2>&1)
    assert_contains "$warn_output" "[ralph]" "log_warn should output ralph prefix"
    assert_contains "$warn_output" "Test warning" "log_warn should output message"

    # Test log_error
    local error_output=$(log_error "Test error" 2>&1)
    assert_contains "$error_output" "[ralph]" "log_error should output ralph prefix"
    assert_contains "$error_output" "Test error" "log_error should output message"

    # Test log_success
    local success_output=$(log_success "Test success" 2>&1)
    assert_contains "$success_output" "[ralph]" "log_success should output ralph prefix"
    assert_contains "$success_output" "Test success" "log_success should output message"
}

# Test verify_workspace function
test_verify_workspace() {
    # The verify_workspace function checks /home/ralph/workspace specifically
    # and only logs warnings - it doesn't fail
    local result

    # This function always returns 0 as it only logs warnings
    verify_workspace >/dev/null 2>&1
    result=$?
    assert_equals "0" "$result" "verify_workspace should always return success (only warns)"

    # Test that the function produces output when workspace is empty
    # Since /home/ralph/workspace exists and is not empty, we can't test the warning case
    # without modifying the actual workspace
}

# Test show_config function
test_show_config() {
    export RALPH_MODE="oauth"
    export RALPH_MODEL="claude-3-opus"
    export RALPH_FORMAT="pretty"
    export RALPH_ITERATIONS="5"
    export RALPH_AUTO_PUSH="true"

    local config_output=$(show_config 2>&1)

    assert_contains "$config_output" "Ralph Loop" "show_config should output header"
    assert_contains "$config_output" "Mode:" "show_config should show mode label"
    assert_contains "$config_output" "oauth" "show_config should show auth mode"
    assert_contains "$config_output" "claude-3-opus" "show_config should show model"
    assert_contains "$config_output" "pretty" "show_config should show format"
    assert_contains "$config_output" "Max Iter:" "show_config should show iterations label"
    assert_contains "$config_output" "Push:" "show_config should show push label"
    assert_contains "$config_output" "true" "show_config should show auto-push setting"
}

# Test setup_entire function
test_setup_entire_disabled() {
    unset RALPH_ENTIRE_ENABLED
    local output
    output=$(setup_entire 2>&1)
    local result=$?
    assert_equals "0" "$result" "setup_entire returns 0 when disabled"
}

test_setup_entire_enabled_no_binary() {
    export RALPH_ENTIRE_ENABLED=true
    local saved_path="$PATH"
    export PATH="/usr/bin:/bin"
    local output
    output=$(setup_entire 2>&1)
    local result=$?
    export PATH="$saved_path"
    assert_equals "0" "$result" "setup_entire returns 0 gracefully when binary missing"
    assert_contains "$output" "not found" "setup_entire warns when binary missing"
    unset RALPH_ENTIRE_ENABLED
}

# Test show_config with Entire
test_show_config_entire() {
    unset RALPH_ENTIRE_ENABLED
    local config_output=$(show_config 2>&1)
    assert_contains "$config_output" "Entire:" "show_config shows Entire label"
    assert_contains "$config_output" "disabled" "show_config shows Entire disabled by default"

    export RALPH_ENTIRE_ENABLED=true
    config_output=$(show_config 2>&1)
    assert_contains "$config_output" "enabled" "show_config shows Entire enabled when set"
    unset RALPH_ENTIRE_ENABLED
}

# Main test execution
main() {
    echo -e "${CYAN}Running Entrypoint Functions Tests${NC}"
    echo "================================="

    setup

    # Run all test functions
    echo -e "\n${YELLOW}Testing Authentication Detection${NC}"
    test_detect_auth_api_key
    test_detect_auth_litellm
    test_detect_auth_no_auth

    echo -e "\n${YELLOW}Testing Logging Functions${NC}"
    test_log_functions

    echo -e "\n${YELLOW}Testing Workspace Verification${NC}"
    test_verify_workspace

    echo -e "\n${YELLOW}Testing Configuration Display${NC}"
    test_show_config

    echo -e "\n${YELLOW}Testing Entire Integration${NC}"
    test_setup_entire_disabled
    test_setup_entire_enabled_no_binary
    test_show_config_entire

    teardown

    # Print summary
    echo "================================="
    echo -e "${CYAN}Test Summary${NC}"
    echo "Tests run: $TESTS_RUN"
    echo -e "${GREEN}Tests passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Tests failed: $TESTS_FAILED${NC}"

    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "\n${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Execute main if run directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi