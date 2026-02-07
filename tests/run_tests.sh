#!/bin/bash
# Test runner script for Ralph Docker shell scripts
# Executes all tests and provides consolidated reporting

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Configuration
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$TESTS_DIR")"
VERBOSE=false
STOP_ON_FIRST_FAILURE=false

# Statistics
TOTAL_TEST_FILES=0
PASSED_TEST_FILES=0
FAILED_TEST_FILES=0
START_TIME=$(date +%s)

# Help message
show_help() {
    cat << 'EOF'
Ralph Docker Test Runner

USAGE:
    ./run_tests.sh [OPTIONS] [TEST_PATTERN]

OPTIONS:
    -v, --verbose           Show verbose output from tests
    -f, --fail-fast        Stop on first test failure
    -h, --help             Show this help message
    -l, --list             List available test files

EXAMPLES:
    ./run_tests.sh                    # Run all tests
    ./run_tests.sh -v                 # Run with verbose output
    ./run_tests.sh --fail-fast        # Stop on first failure
    ./run_tests.sh test_shell_*       # Run specific test pattern

ENVIRONMENT:
    RALPH_TEST_VERBOSE=1              # Enable verbose mode
    RALPH_TEST_FAIL_FAST=1           # Enable fail-fast mode
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--fail-fast)
                STOP_ON_FIRST_FAILURE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_tests
                exit 0
                ;;
            -*)
                echo -e "${RED}Unknown option: $1${NC}"
                show_help
                exit 1
                ;;
            *)
                TEST_PATTERN="$1"
                shift
                ;;
        esac
    done
}

# List available tests
list_tests() {
    echo "Available test files:"
    find "$TESTS_DIR" -name "test_*.sh" -type f | sort | while read -r test_file; do
        local test_name=$(basename "$test_file" .sh)
        echo "  - $test_name"
    done
}

# Run a single test file
run_test_file() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .sh)

    echo -e "${BLUE}Running $test_name...${NC}"

    TOTAL_TEST_FILES=$((TOTAL_TEST_FILES + 1))

    local start_time=$(date +%s)
    local temp_output=$(mktemp)
    local exit_code=0

    # Run the test
    if [ "$VERBOSE" = true ]; then
        if bash "$test_file" 2>&1 | tee "$temp_output"; then
            exit_code=0
        else
            exit_code=$?
        fi
    else
        if bash "$test_file" > "$temp_output" 2>&1; then
            exit_code=0
        else
            exit_code=$?
        fi
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $exit_code -eq 0 ]; then
        PASSED_TEST_FILES=$((PASSED_TEST_FILES + 1))
        echo -e "${GREEN}✓ $test_name passed${NC} (${duration}s)"

        # Show summary even in non-verbose mode
        if [ "$VERBOSE" = false ]; then
            local summary=$(grep -E "(Tests run|Tests passed|Tests failed)" "$temp_output" | tail -3 || true)
            if [ -n "$summary" ]; then
                echo "$summary" | sed 's/^/  /'
            fi
        fi
    else
        FAILED_TEST_FILES=$((FAILED_TEST_FILES + 1))
        echo -e "${RED}✗ $test_name failed${NC} (${duration}s)"

        # Always show failures
        echo -e "${RED}Failure output:${NC}"
        cat "$temp_output" | sed 's/^/  /'

        if [ "$STOP_ON_FIRST_FAILURE" = true ]; then
            rm -f "$temp_output"
            exit 1
        fi
    fi

    rm -f "$temp_output"
    echo ""
}

# Check prerequisites
check_prerequisites() {
    echo -e "${CYAN}Checking prerequisites...${NC}"

    # Check if we're in the right directory
    if [ ! -f "$WORKSPACE_DIR/scripts/format-output.sh" ]; then
        echo -e "${RED}Error: Cannot find scripts directory. Make sure you're running from the tests directory.${NC}"
        exit 1
    fi

    # Check required tools
    local missing_tools=()

    if ! command -v bash &> /dev/null; then
        missing_tools+=("bash")
    fi

    if ! command -v git &> /dev/null; then
        missing_tools+=("git")
    fi

    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "${RED}Error: Missing required tools: ${missing_tools[*]}${NC}"
        exit 1
    fi

    echo -e "${GREEN}Prerequisites check passed${NC}"
}

# Setup test environment
setup_environment() {
    echo -e "${CYAN}Setting up test environment...${NC}"

    # Set environment variables for tests
    export RALPH_TEST_MODE=1
    export PATH="$WORKSPACE_DIR/scripts:$PATH"

    # Handle environment overrides
    if [ "${RALPH_TEST_VERBOSE:-}" = "1" ]; then
        VERBOSE=true
    fi

    if [ "${RALPH_TEST_FAIL_FAST:-}" = "1" ]; then
        STOP_ON_FIRST_FAILURE=true
    fi

    echo -e "${GREEN}Test environment ready${NC}"
}

# Main test execution
run_tests() {
    local test_pattern="${TEST_PATTERN:-test_*.sh}"

    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}Ralph Docker Shell Scripts Test Suite${NC}"
    echo -e "${MAGENTA}========================================${NC}"
    echo ""

    # Find and run tests
    local test_files=()
    while IFS= read -r -d '' test_file; do
        test_files+=("$test_file")
    done < <(find "$TESTS_DIR" -name "$test_pattern" -type f -print0 | sort -z)

    if [ ${#test_files[@]} -eq 0 ]; then
        echo -e "${YELLOW}No test files found matching pattern: $test_pattern${NC}"
        exit 1
    fi

    echo "Found ${#test_files[@]} test file(s)"
    echo ""

    # Run each test file
    for test_file in "${test_files[@]}"; do
        run_test_file "$test_file"
    done
}

# Generate final report
generate_report() {
    local end_time=$(date +%s)
    local total_duration=$((end_time - START_TIME))

    echo -e "${MAGENTA}========================================${NC}"
    echo -e "${MAGENTA}Test Run Summary${NC}"
    echo -e "${MAGENTA}========================================${NC}"

    echo "Total test files: $TOTAL_TEST_FILES"
    echo -e "Passed: ${GREEN}$PASSED_TEST_FILES${NC}"
    echo -e "Failed: ${RED}$FAILED_TEST_FILES${NC}"
    echo "Total time: ${total_duration}s"
    echo ""

    if [ $FAILED_TEST_FILES -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed!${NC}"

        # Additional success information
        echo ""
        echo "Test coverage includes:"
        echo "  ✓ format-output.sh functions (truncate_text, stream parsing, ANSI colors)"
        echo "  ✓ loop.sh functions (git operations, iteration control, environment handling)"
        echo "  ✓ extract-credentials.sh (OAuth extraction, file operations)"
        echo "  ✓ entrypoint.sh (auth detection, mode selection, health checks)"
        echo "  ✓ Integration testing and script validation"

        exit 0
    else
        echo -e "${RED}❌ Some tests failed!${NC}"
        echo ""
        echo "To debug failures:"
        echo "  1. Run with -v flag for verbose output"
        echo "  2. Check individual test files for specific issues"
        echo "  3. Ensure all dependencies are installed"

        exit 1
    fi
}

# Cleanup on exit
cleanup() {
    # Clean up any temporary files created during testing
    find /tmp -name "ralph_tests_*" -type d -exec rm -rf {} + 2>/dev/null || true
    find /tmp -name "test_creds" -type d -exec rm -rf {} + 2>/dev/null || true
}

# Signal handlers
trap cleanup EXIT
trap 'echo -e "\n${YELLOW}Test run interrupted${NC}"; exit 130' INT TERM

# Main execution
main() {
    local TEST_PATTERN=""

    # Parse command line arguments
    parse_args "$@"

    # Setup and run tests
    check_prerequisites
    setup_environment
    run_tests
    generate_report
}

# Run main function if script is executed directly
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi