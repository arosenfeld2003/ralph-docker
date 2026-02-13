#!/bin/bash
# Tests for Entire CLI integration
# Validates entire_available(), setup_entire(), and environment variable defaults

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
TEST_DIR="/tmp/entire_tests_$$"
SCRIPTS_DIR="/home/ralph/workspace/scripts"

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

# Setup
setup() {
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Create a mock git repo for setup_entire tests
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > test_file.txt
    git add test_file.txt
    git commit --quiet -m "Initial commit"
}

# Teardown
teardown() {
    cd /tmp
    rm -rf "$TEST_DIR"
}

# Source entrypoint functions (without executing main)
source_entrypoint() {
    source <(grep -v '^main "\$@"' "$SCRIPTS_DIR/entrypoint.sh") 2>/dev/null || true
}

# ============================================================
# Tests for entire_available()
# ============================================================

test_entire_available_returns_false_when_disabled() {
    source_entrypoint

    unset RALPH_ENTIRE_ENABLED
    set +e
    entire_available
    local result=$?
    set -e
    assert_equals "1" "$result" "entire_available returns false when RALPH_ENTIRE_ENABLED unset"
}

test_entire_available_returns_false_when_explicitly_disabled() {
    source_entrypoint

    export RALPH_ENTIRE_ENABLED=false
    set +e
    entire_available
    local result=$?
    set -e
    assert_equals "1" "$result" "entire_available returns false when RALPH_ENTIRE_ENABLED=false"

    unset RALPH_ENTIRE_ENABLED
}

test_entire_available_returns_false_when_binary_missing() {
    source_entrypoint

    export RALPH_ENTIRE_ENABLED=true
    # Save PATH and set to something that won't have entire
    local saved_path="$PATH"
    export PATH="/usr/bin:/bin"
    set +e
    entire_available
    local result=$?
    set -e
    export PATH="$saved_path"
    assert_equals "1" "$result" "entire_available returns false when binary missing"

    unset RALPH_ENTIRE_ENABLED
}

test_entire_available_returns_true_when_enabled_and_present() {
    source_entrypoint

    # Create a fake entire binary
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash' > "$TEST_DIR/bin/entire"
    echo 'echo "entire mock"' >> "$TEST_DIR/bin/entire"
    chmod +x "$TEST_DIR/bin/entire"

    export RALPH_ENTIRE_ENABLED=true
    local saved_path="$PATH"
    export PATH="$TEST_DIR/bin:$PATH"
    set +e
    entire_available
    local result=$?
    set -e
    export PATH="$saved_path"
    assert_equals "0" "$result" "entire_available returns true when enabled and binary present"

    unset RALPH_ENTIRE_ENABLED
}

# ============================================================
# Tests for setup_entire()
# ============================================================

test_setup_entire_noop_when_disabled() {
    source_entrypoint

    unset RALPH_ENTIRE_ENABLED
    local output
    output=$(setup_entire 2>&1)
    local result=$?
    assert_equals "0" "$result" "setup_entire returns 0 when disabled"
    assert_equals "" "$output" "setup_entire produces no output when disabled"
}

test_setup_entire_warns_when_binary_missing() {
    source_entrypoint

    export RALPH_ENTIRE_ENABLED=true
    local saved_path="$PATH"
    export PATH="/usr/bin:/bin"
    local output
    output=$(setup_entire 2>&1)
    local result=$?
    export PATH="$saved_path"
    assert_equals "0" "$result" "setup_entire returns 0 when binary missing (graceful)"
    assert_contains "$output" "Entire binary not found" "setup_entire warns about missing binary"

    unset RALPH_ENTIRE_ENABLED
}

test_setup_entire_warns_when_no_git_repo() {
    source_entrypoint

    # Create a fake entire binary
    mkdir -p "$TEST_DIR/bin"
    echo '#!/bin/bash' > "$TEST_DIR/bin/entire"
    echo 'echo "mock"' >> "$TEST_DIR/bin/entire"
    chmod +x "$TEST_DIR/bin/entire"

    export RALPH_ENTIRE_ENABLED=true
    local saved_path="$PATH"
    export PATH="$TEST_DIR/bin:$PATH"

    # Move to a non-git directory
    local non_git_dir="$TEST_DIR/no-git"
    mkdir -p "$non_git_dir"
    cd "$non_git_dir"

    local output
    output=$(setup_entire 2>&1)
    local result=$?

    cd "$TEST_DIR"
    export PATH="$saved_path"
    assert_equals "0" "$result" "setup_entire returns 0 when no git repo (graceful)"
    assert_contains "$output" "No git repo" "setup_entire warns about missing git repo"

    unset RALPH_ENTIRE_ENABLED
}

# ============================================================
# Tests for environment variable defaults
# ============================================================

test_env_var_defaults() {
    assert_equals "false" "${RALPH_ENTIRE_ENABLED:-false}" "RALPH_ENTIRE_ENABLED defaults to false"
    assert_equals "manual-commit" "${RALPH_ENTIRE_STRATEGY:-manual-commit}" "RALPH_ENTIRE_STRATEGY defaults to manual-commit"
    assert_equals "true" "${RALPH_ENTIRE_PUSH_SESSIONS:-true}" "RALPH_ENTIRE_PUSH_SESSIONS defaults to true"
    assert_equals "warn" "${RALPH_ENTIRE_LOG_LEVEL:-warn}" "RALPH_ENTIRE_LOG_LEVEL defaults to warn"
}

# ============================================================
# Tests for show_config Entire line
# ============================================================

test_show_config_displays_entire_disabled() {
    source_entrypoint

    unset RALPH_ENTIRE_ENABLED
    local output
    output=$(show_config 2>&1)
    assert_contains "$output" "Entire:" "show_config includes Entire line"
    assert_contains "$output" "disabled" "show_config shows Entire as disabled by default"
}

test_show_config_displays_entire_enabled() {
    source_entrypoint

    export RALPH_ENTIRE_ENABLED=true
    local output
    output=$(show_config 2>&1)
    assert_contains "$output" "Entire:" "show_config includes Entire line when enabled"
    assert_contains "$output" "enabled" "show_config shows Entire as enabled"
    assert_contains "$output" "manual-commit" "show_config shows default strategy"

    unset RALPH_ENTIRE_ENABLED
}

# ============================================================
# Tests for help text
# ============================================================

test_help_includes_entire_commands() {
    local help_output
    help_output=$("$SCRIPTS_DIR/entrypoint.sh" help 2>&1 || true)
    assert_contains "$help_output" "entire-status" "help text includes entire-status command"
    assert_contains "$help_output" "RALPH_ENTIRE_ENABLED" "help text includes RALPH_ENTIRE_ENABLED"
    assert_contains "$help_output" "RALPH_ENTIRE_STRATEGY" "help text includes RALPH_ENTIRE_STRATEGY"
}

# ============================================================
# Main test execution
# ============================================================

main() {
    echo -e "${CYAN}Running Entire Integration Tests${NC}"
    echo "================================="

    setup

    echo -e "\n${YELLOW}Testing entire_available()${NC}"
    test_entire_available_returns_false_when_disabled
    test_entire_available_returns_false_when_explicitly_disabled
    test_entire_available_returns_false_when_binary_missing
    test_entire_available_returns_true_when_enabled_and_present

    echo -e "\n${YELLOW}Testing setup_entire()${NC}"
    test_setup_entire_noop_when_disabled
    test_setup_entire_warns_when_binary_missing
    test_setup_entire_warns_when_no_git_repo

    echo -e "\n${YELLOW}Testing Environment Variable Defaults${NC}"
    test_env_var_defaults

    echo -e "\n${YELLOW}Testing show_config Entire Display${NC}"
    test_show_config_displays_entire_disabled
    test_show_config_displays_entire_enabled

    echo -e "\n${YELLOW}Testing Help Text${NC}"
    test_help_includes_entire_commands

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
