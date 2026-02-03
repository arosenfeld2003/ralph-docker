#!/bin/bash
# OAuth Mode Specific Tests
# Tests the OAuth authentication flow and credential handling

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_PROJECT="ralph-oauth-test-$(date +%s)"

log_info() {
    echo -e "${CYAN}[OAUTH-TEST]${NC} $1"
}

log_error() {
    echo -e "${RED}[OAUTH-TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OAUTH-TEST]${NC} $1"
}

cleanup() {
    log_info "Cleaning up OAuth test environment..."
    docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" down --volumes --remove-orphans 2>/dev/null || true
    rm -rf "/tmp/ralph-oauth-test"
}

trap 'cleanup' EXIT

test_oauth_credential_detection() {
    log_info "Testing OAuth credential detection..."

    # Create test OAuth credentials directory
    mkdir -p "/tmp/ralph-oauth-test/.claude"

    # Test 1: OAuth with credentials.json
    cat > "/tmp/ralph-oauth-test/.claude/credentials.json" << 'EOF'
{
    "session_key": "test-session-key-12345",
    "organization_uuid": "test-org-uuid",
    "refresh_token": "test-refresh-token"
}
EOF

    local output
    if output=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "/tmp/ralph-oauth-test/.claude:/home/ralph/.claude:ro" \
        ralph test 2>&1); then

        if echo "$output" | grep -q "Auth mode: OAuth (Max subscription)"; then
            log_success "OAuth credentials.json detected correctly"
        else
            log_error "OAuth credentials.json not detected properly"
            return 1
        fi
    else
        # Expected behavior - auth will fail but should detect the mode
        if echo "$output" | grep -q "OAuth"; then
            log_success "OAuth mode detected (auth failed as expected)"
        else
            log_error "OAuth mode not detected in error output"
            return 1
        fi
    fi

    # Test 2: OAuth with .credentials.json (alternative location)
    rm "/tmp/ralph-oauth-test/.claude/credentials.json"
    cat > "/tmp/ralph-oauth-test/.claude/.credentials.json" << 'EOF'
{
    "session_key": "test-session-key-alt",
    "organization_uuid": "test-org-uuid-alt"
}
EOF

    if output=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "/tmp/ralph-oauth-test/.claude:/home/ralph/.claude:ro" \
        ralph test 2>&1); then

        if echo "$output" | grep -q "Auth mode: OAuth credentials file"; then
            log_success "OAuth .credentials.json detected correctly"
        else
            log_error "OAuth .credentials.json not detected properly"
            return 1
        fi
    else
        if echo "$output" | grep -q "OAuth"; then
            log_success "OAuth mode with .credentials.json detected"
        else
            log_error "OAuth mode with .credentials.json not detected"
            return 1
        fi
    fi

    log_success "OAuth credential detection tests passed"
}

test_oauth_volume_mount() {
    log_info "Testing OAuth volume mount requirements..."

    # Create minimal credentials
    mkdir -p "/tmp/ralph-oauth-test/.claude"
    echo '{"session_key": "test"}' > "/tmp/ralph-oauth-test/.claude/credentials.json"

    # Test read-only mount (production scenario)
    local output
    if output=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "/tmp/ralph-oauth-test/.claude:/home/ralph/.claude:ro" \
        ralph shell -c "ls -la /home/ralph/.claude/" 2>&1); then

        if echo "$output" | grep -q "credentials.json"; then
            log_success "Read-only OAuth volume mount working"
        else
            log_error "OAuth credentials file not accessible in read-only mount"
            return 1
        fi
    else
        log_error "Failed to access OAuth volume mount"
        return 1
    fi

    # Test write access for debug/todos directories
    if output=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "/tmp/ralph-oauth-test/.claude:/home/ralph/.claude" \
        ralph shell -c "touch /home/ralph/.claude/debug/test.log && touch /home/ralph/.claude/todos/test.json" 2>&1); then

        if [ -f "/tmp/ralph-oauth-test/.claude/debug/test.log" ] && [ -f "/tmp/ralph-oauth-test/.claude/todos/test.json" ]; then
            log_success "Write access to debug/todos directories working"
        else
            log_error "Write access to debug/todos directories failed"
            return 1
        fi
    else
        log_error "Failed to test write access to OAuth directories"
        return 1
    fi

    log_success "OAuth volume mount tests passed"
}

test_oauth_environment_isolation() {
    log_info "Testing OAuth environment variable isolation..."

    # Create test credentials
    mkdir -p "/tmp/ralph-oauth-test/.claude"
    echo '{"session_key": "oauth-test-key"}' > "/tmp/ralph-oauth-test/.claude/credentials.json"

    # Test that API key environment variables don't override OAuth
    local output
    if output=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "/tmp/ralph-oauth-test/.claude:/home/ralph/.claude:ro" \
        -e ANTHROPIC_API_KEY="should-be-ignored" \
        -e ANTHROPIC_BASE_URL="should-be-ignored" \
        ralph test 2>&1); then

        if echo "$output" | grep -q "Auth mode: OAuth"; then
            log_success "OAuth takes precedence over environment variables"
        else
            log_error "OAuth not prioritized over environment variables"
            return 1
        fi
    else
        # Check if OAuth mode was detected in error output
        if echo "$output" | grep -q "OAuth"; then
            log_success "OAuth mode detected despite environment variables"
        else
            log_error "OAuth mode not detected with conflicting environment variables"
            return 1
        fi
    fi

    log_success "OAuth environment isolation tests passed"
}

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph OAuth Mode Integration Tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    cd "$PROJECT_DIR"

    test_oauth_credential_detection
    test_oauth_volume_mount
    test_oauth_environment_isolation

    log_success "All OAuth mode tests passed!"
}

main "$@"