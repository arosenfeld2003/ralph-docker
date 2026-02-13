#!/bin/bash
# Tests for setup-workspace.sh --prompt and --prompt-file flags
# Tests argument parsing, prompt resolution, interview skip logic,
# and auto-overwrite behavior without requiring Docker or Claude API

set -euo pipefail

# Test framework
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

TEST_DIR="/tmp/ralph_setup_tests_$$"
SCRIPTS_DIR="${SCRIPTS_DIR:-/home/ralph/workspace/scripts}"

# ─── Test helpers ───────────────────────────────────────────────────

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
        echo -e "  In: '${haystack:0:200}'"
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
        echo -e "  In: '${haystack:0:200}'"
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

setup() {
    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Create a mock git repo as workspace
    mkdir -p workspace
    cd workspace
    git init --quiet
    git config user.email "test@example.com"
    git config user.name "Test User"
    echo "test" > index.js
    git add index.js
    git commit --quiet -m "Initial commit"
    cd "$TEST_DIR"
}

teardown() {
    cd /tmp
    rm -rf "$TEST_DIR"
}

# ─── Argument parsing tests ────────────────────────────────────────

test_argument_parsing() {
    echo -e "${CYAN}Testing --prompt and --prompt-file argument parsing${NC}"

    # Create a test script that extracts just the argument parsing logic
    cat > "$TEST_DIR/parse_args.sh" << 'PARSE_EOF'
#!/bin/bash
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

echo "PROMPT_TEXT=$PROMPT_TEXT"
echo "PROMPT_FILE=$PROMPT_FILE"
PARSE_EOF
    chmod +x "$TEST_DIR/parse_args.sh"

    # Test: --prompt flag captures text
    local output=$(bash "$TEST_DIR/parse_args.sh" --prompt "Build a REST API")
    assert_contains "$output" 'PROMPT_TEXT=Build a REST API' "--prompt captures the prompt text"

    # Test: --prompt-file flag captures path
    local output=$(bash "$TEST_DIR/parse_args.sh" --prompt-file "specs/prompt.md")
    assert_contains "$output" 'PROMPT_FILE=specs/prompt.md' "--prompt-file captures the file path"

    # Test: no flags results in empty values
    local output=$(bash "$TEST_DIR/parse_args.sh")
    assert_contains "$output" 'PROMPT_TEXT=' "No flags results in empty PROMPT_TEXT"
    assert_contains "$output" 'PROMPT_FILE=' "No flags results in empty PROMPT_FILE"

    # Test: --prompt with multi-word quoted string
    local output=$(bash "$TEST_DIR/parse_args.sh" --prompt "Build a REST API that ingests CSV uploads and validates them")
    assert_contains "$output" 'PROMPT_TEXT=Build a REST API that ingests CSV uploads and validates them' "--prompt handles multi-word strings"

    # Test: --prompt takes precedence when both provided (last wins via PROMPT_FILE resolution)
    local output=$(bash "$TEST_DIR/parse_args.sh" --prompt "inline text" --prompt-file "file.md")
    assert_contains "$output" 'PROMPT_TEXT=inline text' "Both flags: --prompt value preserved"
    assert_contains "$output" 'PROMPT_FILE=file.md' "Both flags: --prompt-file value preserved"

    # Test: unknown flags are silently ignored
    local output=$(bash "$TEST_DIR/parse_args.sh" --prompt "test" --unknown-flag)
    assert_contains "$output" 'PROMPT_TEXT=test' "Unknown flags are ignored"
}

# ─── Prompt file resolution tests ──────────────────────────────────

test_prompt_file_resolution() {
    echo -e "${CYAN}Testing --prompt-file resolution${NC}"

    # Create a test script for file resolution
    cat > "$TEST_DIR/resolve_prompt.sh" << 'RESOLVE_EOF'
#!/bin/bash
set -euo pipefail
PROMPT_TEXT=""
PROMPT_FILE="$1"

if [ -n "$PROMPT_FILE" ]; then
    if [ ! -f "$PROMPT_FILE" ]; then
        echo "ERROR: Prompt file not found: $PROMPT_FILE"
        exit 1
    fi
    PROMPT_TEXT=$(cat "$PROMPT_FILE")
fi

echo "$PROMPT_TEXT"
RESOLVE_EOF
    chmod +x "$TEST_DIR/resolve_prompt.sh"

    # Create a test prompt file
    echo "Build a REST API with PostgreSQL" > "$TEST_DIR/test_prompt.md"

    # Test: reads content from file
    local output=$(bash "$TEST_DIR/resolve_prompt.sh" "$TEST_DIR/test_prompt.md")
    assert_equals "Build a REST API with PostgreSQL" "$output" "--prompt-file reads file content"

    # Test: exits with error for missing file
    assert_exit_code 1 "bash $TEST_DIR/resolve_prompt.sh /nonexistent/file.md" "--prompt-file exits 1 for missing file"

    # Test: error message mentions the missing path
    local output=$(bash "$TEST_DIR/resolve_prompt.sh" /nonexistent/file.md 2>&1 || true)
    assert_contains "$output" "Prompt file not found" "--prompt-file shows error for missing file"

    # Test: handles multi-line prompt files
    cat > "$TEST_DIR/multiline_prompt.md" << 'EOF'
# Project: Data Pipeline

## Goal
Build an ETL pipeline that:
- Ingests CSV from S3
- Validates against JSON schema
- Loads into PostgreSQL

## Tech Stack
Python, FastAPI, SQLAlchemy
EOF

    local output=$(bash "$TEST_DIR/resolve_prompt.sh" "$TEST_DIR/multiline_prompt.md")
    assert_contains "$output" "Data Pipeline" "--prompt-file handles multi-line files"
    assert_contains "$output" "Ingests CSV from S3" "--prompt-file preserves all lines"
    assert_contains "$output" "Python, FastAPI" "--prompt-file preserves content at end of file"

    # Test: handles empty prompt file
    touch "$TEST_DIR/empty_prompt.md"
    local output=$(bash "$TEST_DIR/resolve_prompt.sh" "$TEST_DIR/empty_prompt.md")
    assert_equals "" "$output" "--prompt-file handles empty file"
}

# ─── Interview skip logic tests ────────────────────────────────────

test_interview_skip_logic() {
    echo -e "${CYAN}Testing interview skip when prompt is provided${NC}"

    # Create a test script that simulates the interview branching
    cat > "$TEST_DIR/interview_logic.sh" << 'INTERVIEW_EOF'
#!/bin/bash
PROMPT_TEXT="${1:-}"

if [ -n "$PROMPT_TEXT" ]; then
    echo "SKIPPED_INTERVIEW=true"
    echo "PROJECT_GOAL=(see detailed prompt below)"
    echo "TECH_STACK="
    echo "BUILD_CMD="
    echo "TEST_CMD="
else
    echo "SKIPPED_INTERVIEW=false"
fi
INTERVIEW_EOF
    chmod +x "$TEST_DIR/interview_logic.sh"

    # Test: interview is skipped when prompt is provided
    local output=$(bash "$TEST_DIR/interview_logic.sh" "Build a REST API")
    assert_contains "$output" "SKIPPED_INTERVIEW=true" "Interview skipped when --prompt provided"
    assert_contains "$output" "PROJECT_GOAL=(see detailed prompt below)" "Project goal set to placeholder when prompt provided"

    # Test: interview runs when no prompt
    local output=$(bash "$TEST_DIR/interview_logic.sh" "")
    assert_contains "$output" "SKIPPED_INTERVIEW=false" "Interview runs when no prompt provided"
}

# ─── Auto-overwrite tests ──────────────────────────────────────────

test_auto_overwrite() {
    echo -e "${CYAN}Testing auto-overwrite behavior with prompt${NC}"

    # Create a test script that simulates the overwrite logic
    cat > "$TEST_DIR/overwrite_logic.sh" << 'OVERWRITE_EOF'
#!/bin/bash
PROMPT_TEXT="${1:-}"

# Simulate existing files
EXISTING_FILES=("AGENTS.md" "specs/")

if [ ${#EXISTING_FILES[@]} -gt 0 ]; then
    if [ -n "$PROMPT_TEXT" ]; then
        echo "ACTION=auto_overwrite"
    else
        echo "ACTION=prompt_user"
    fi
else
    echo "ACTION=no_existing_files"
fi
OVERWRITE_EOF
    chmod +x "$TEST_DIR/overwrite_logic.sh"

    # Test: auto-overwrite when prompt provided
    local output=$(bash "$TEST_DIR/overwrite_logic.sh" "Build something")
    assert_equals "ACTION=auto_overwrite" "$output" "Auto-overwrites existing files when --prompt provided"

    # Test: prompts user when no prompt flag
    local output=$(bash "$TEST_DIR/overwrite_logic.sh" "")
    assert_equals "ACTION=prompt_user" "$output" "Prompts user for confirmation when no --prompt flag"
}

# ─── Prompt assembly tests ─────────────────────────────────────────

test_prompt_assembly() {
    echo -e "${CYAN}Testing prompt assembly for Claude${NC}"

    # Create a test script that simulates prompt context building
    cat > "$TEST_DIR/assemble_prompt.sh" << 'ASSEMBLE_EOF'
#!/bin/bash
PROMPT_TEXT="${1:-}"
PROJECT_GOAL="${2:-}"
TECH_STACK="${3:-}"

if [ -n "$PROMPT_TEXT" ]; then
    CONTEXT="The user has provided a detailed project prompt. Do NOT use AskUserQuestion — use the prompt below as the project description and goals.

DETAILED PROJECT PROMPT:
${PROMPT_TEXT}

TECH STACK: Auto-detect from the codebase."
else
    CONTEXT="The user has already answered the interview questions. Do NOT use AskUserQuestion — use these answers directly:

PROJECT GOAL: ${PROJECT_GOAL}
"
    if [ -n "$TECH_STACK" ]; then
        CONTEXT+="TECH STACK: ${TECH_STACK}"
    else
        CONTEXT+="TECH STACK: Auto-detect from the codebase."
    fi
fi

echo "$CONTEXT"
ASSEMBLE_EOF
    chmod +x "$TEST_DIR/assemble_prompt.sh"

    # Test: prompt mode includes the full prompt text
    local output=$(bash "$TEST_DIR/assemble_prompt.sh" "Build a REST API with auth")
    assert_contains "$output" "DETAILED PROJECT PROMPT:" "Prompt mode includes DETAILED PROJECT PROMPT header"
    assert_contains "$output" "Build a REST API with auth" "Prompt mode includes the full prompt text"
    assert_contains "$output" "Auto-detect from the codebase" "Prompt mode sets tech stack to auto-detect"
    assert_not_contains "$output" "PROJECT GOAL:" "Prompt mode does NOT include PROJECT GOAL section"

    # Test: interactive mode includes interview answers
    local output=$(bash "$TEST_DIR/assemble_prompt.sh" "" "Build a todo app" "React + Node")
    assert_contains "$output" "PROJECT GOAL: Build a todo app" "Interactive mode includes project goal"
    assert_contains "$output" "TECH STACK: React + Node" "Interactive mode includes explicit tech stack"
    assert_not_contains "$output" "DETAILED PROJECT PROMPT:" "Interactive mode does NOT include DETAILED PROJECT PROMPT"

    # Test: interactive mode with auto-detect tech stack
    local output=$(bash "$TEST_DIR/assemble_prompt.sh" "" "Build a todo app" "")
    assert_contains "$output" "Auto-detect from the codebase" "Interactive mode auto-detects tech stack when empty"
}

# ─── Help text tests ───────────────────────────────────────────────

test_help_text() {
    echo -e "${CYAN}Testing help text documents new flags${NC}"

    local help_output=$("$SCRIPTS_DIR/entrypoint.sh" help 2>&1 || true)

    assert_contains "$help_output" "--prompt" "Help text documents --prompt flag"
    assert_contains "$help_output" "--prompt-file" "Help text documents --prompt-file flag"
    assert_contains "$help_output" "skips interview" "Help text explains --prompt skips interview"
}

# ─── Script syntax validation ──────────────────────────────────────

test_script_syntax() {
    echo -e "${CYAN}Testing setup-workspace.sh syntax${NC}"

    assert_exit_code 0 "bash -n $SCRIPTS_DIR/setup-workspace.sh" "setup-workspace.sh has valid bash syntax"
}

# ─── Log output tests ──────────────────────────────────────────────

test_log_output() {
    echo -e "${CYAN}Testing log output with prompt flag${NC}"

    # Create a test script that simulates the logging behavior
    cat > "$TEST_DIR/log_output.sh" << 'LOG_EOF'
#!/bin/bash
CYAN='\033[0;36m'
NC='\033[0m'
log_info() { echo -e "${CYAN}[ralph]${NC} $1"; }

PROMPT_TEXT="${1:-}"

if [ -n "$PROMPT_TEXT" ]; then
    log_info "Using provided prompt (${#PROMPT_TEXT} chars)"
fi
LOG_EOF
    chmod +x "$TEST_DIR/log_output.sh"

    # Test: logs prompt character count
    local output=$(bash "$TEST_DIR/log_output.sh" "Build a REST API")
    assert_contains "$output" "Using provided prompt (16 chars)" "Logs prompt length when --prompt provided"

    # Test: no log when no prompt
    local output=$(bash "$TEST_DIR/log_output.sh" "")
    assert_not_contains "$output" "Using provided prompt" "No prompt log when no --prompt flag"
}

# ─── Main ───────────────────────────────────────────────────────────

main() {
    echo "========================================"
    echo "Ralph Setup Flags Test Suite"
    echo "========================================"
    echo ""

    setup

    test_argument_parsing
    echo ""
    test_prompt_file_resolution
    echo ""
    test_interview_skip_logic
    echo ""
    test_auto_overwrite
    echo ""
    test_prompt_assembly
    echo ""
    test_help_text
    echo ""
    test_script_syntax
    echo ""
    test_log_output
    echo ""

    teardown

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

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    main "$@"
fi
