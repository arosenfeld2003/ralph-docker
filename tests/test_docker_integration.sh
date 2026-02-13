#!/bin/bash
# Docker Integration Tests for Ralph Framework
# Verifies Docker compose functionality, networking, volumes, and service interactions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_PROJECT="ralph-test-$(date +%s)"
TIMEOUT_SECONDS=120
CLEANUP_ON_SUCCESS=${CLEANUP_ON_SUCCESS:-true}
CLEANUP_ON_FAILURE=${CLEANUP_ON_FAILURE:-true}

# Test state tracking
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

log_info() {
    echo -e "${CYAN}[TEST]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[TEST]${NC} $1"
}

log_error() {
    echo -e "${RED}[TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[TEST]${NC} $1"
}

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test result tracking
pass_test() {
    local test_name="$1"
    ((TESTS_PASSED++))
    log_success "✓ PASSED: $test_name"
}

fail_test() {
    local test_name="$1"
    local reason="${2:-Unknown error}"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$test_name: $reason")
    log_error "✗ FAILED: $test_name - $reason"
}

start_test() {
    local test_name="$1"
    ((TESTS_TOTAL++))
    log_test "Running test: $test_name"
}

# Cleanup function
cleanup() {
    local force="${1:-false}"

    if [ "$force" = "true" ] || [ "$CLEANUP_ON_SUCCESS" = "true" ] || [ "$CLEANUP_ON_FAILURE" = "true" ]; then
        log_info "Cleaning up test containers and volumes..."

        # Stop and remove containers
        docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" down --volumes --remove-orphans 2>/dev/null || true

        # Remove any dangling test images
        docker images --filter "label=com.docker.compose.project=$COMPOSE_PROJECT" -q | xargs -r docker rmi 2>/dev/null || true

        # Remove test workspace directory if it exists
        [ -d "/tmp/ralph-test-workspace" ] && rm -rf "/tmp/ralph-test-workspace" || true

        log_info "Cleanup completed"
    fi
}

# Trap cleanup on script exit
trap 'cleanup' EXIT

# Wait for service to be ready
wait_for_service() {
    local service_name="$1"
    local health_cmd="$2"
    local timeout="${3:-60}"
    local interval="${4:-2}"

    log_info "Waiting for $service_name to be ready..."

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$health_cmd" &>/dev/null; then
            log_success "$service_name is ready"
            return 0
        fi

        sleep "$interval"
        elapsed=$((elapsed + interval))
        echo -ne "\rWaiting for $service_name... ${elapsed}s/${timeout}s"
    done

    echo ""
    log_error "$service_name failed to become ready within ${timeout}s"
    return 1
}

# Test Docker Compose Build
test_docker_compose_build() {
    start_test "Docker Compose Build"

    if ! cd "$PROJECT_DIR"; then
        fail_test "Docker Compose Build" "Could not change to project directory"
        return 1
    fi

    # Build main Ralph image
    if docker compose -p "$COMPOSE_PROJECT" build ralph 2>/dev/null; then
        log_info "Main Ralph image built successfully"
    else
        fail_test "Docker Compose Build" "Failed to build main Ralph image"
        return 1
    fi

    # Build LiteLLM image for Ollama mode tests
    if docker compose -p "$COMPOSE_PROJECT" build litellm 2>/dev/null; then
        log_info "LiteLLM image built successfully"
    else
        fail_test "Docker Compose Build" "Failed to build LiteLLM image"
        return 1
    fi

    pass_test "Docker Compose Build"
}

# Test container startup with environment variables
test_container_startup() {
    start_test "Container Startup with Environment Variables"

    # Create test workspace
    mkdir -p "/tmp/ralph-test-workspace"
    echo "console.log('test project');" > "/tmp/ralph-test-workspace/test.js"

    # Set test environment variables
    export WORKSPACE_PATH="/tmp/ralph-test-workspace"
    export RALPH_MODE="plan"
    export RALPH_MAX_ITERATIONS="1"
    export RALPH_MODEL="opus"
    export RALPH_OUTPUT_FORMAT="json"
    export RALPH_PUSH_AFTER_COMMIT="false"

    # Start container with test command
    if docker compose -p "$COMPOSE_PROJECT" run --rm \
        -e WORKSPACE_PATH="$WORKSPACE_PATH" \
        -e RALPH_MODE="$RALPH_MODE" \
        -e RALPH_MAX_ITERATIONS="$RALPH_MAX_ITERATIONS" \
        -e RALPH_MODEL="$RALPH_MODEL" \
        -e RALPH_OUTPUT_FORMAT="$RALPH_OUTPUT_FORMAT" \
        -e RALPH_PUSH_AFTER_COMMIT="$RALPH_PUSH_AFTER_COMMIT" \
        ralph version &>/dev/null; then

        log_info "Container started successfully with environment variables"
        pass_test "Container Startup with Environment Variables"
    else
        fail_test "Container Startup with Environment Variables" "Container failed to start or execute command"
        return 1
    fi
}

# Test volume mounts
test_volume_mounts() {
    start_test "Volume Mounts and Workspace Persistence"

    # Create test file in workspace
    mkdir -p "/tmp/ralph-test-workspace"
    echo "test content $(date)" > "/tmp/ralph-test-workspace/volume-test.txt"
    local test_content="$(cat /tmp/ralph-test-workspace/volume-test.txt)"

    # Run container and check if file is accessible
    local container_content
    if container_content=$(docker compose -p "$COMPOSE_PROJECT" run --rm \
        -v "/tmp/ralph-test-workspace:/home/ralph/workspace" \
        ralph shell -c "cat /home/ralph/workspace/volume-test.txt" 2>/dev/null); then

        if [ "$container_content" = "$test_content" ]; then
            log_info "Workspace volume mount working correctly"

            # Test write persistence
            docker compose -p "$COMPOSE_PROJECT" run --rm \
                -v "/tmp/ralph-test-workspace:/home/ralph/workspace" \
                ralph shell -c "echo 'written from container' > /home/ralph/workspace/container-write.txt" &>/dev/null

            if [ -f "/tmp/ralph-test-workspace/container-write.txt" ]; then
                log_info "Write persistence working correctly"
                pass_test "Volume Mounts and Workspace Persistence"
            else
                fail_test "Volume Mounts and Workspace Persistence" "Write persistence failed"
            fi
        else
            fail_test "Volume Mounts and Workspace Persistence" "File content mismatch"
        fi
    else
        fail_test "Volume Mounts and Workspace Persistence" "Could not read mounted file"
    fi
}

# Test LiteLLM service and health checks
test_litellm_service() {
    start_test "LiteLLM Service and Health Checks"

    # Start LiteLLM service
    log_info "Starting LiteLLM service..."
    if ! docker compose -p "$COMPOSE_PROJECT" --profile ollama up -d litellm 2>/dev/null; then
        fail_test "LiteLLM Service and Health Checks" "Failed to start LiteLLM service"
        return 1
    fi

    # Wait for health check to pass
    if wait_for_service "LiteLLM" \
        "docker compose -p $COMPOSE_PROJECT ps litellm --format json | grep -q '\"Health\":\"healthy\"'" \
        60 5; then

        log_info "LiteLLM health check passed"

        # Test direct HTTP health endpoint
        local litellm_port
        if litellm_port=$(docker compose -p "$COMPOSE_PROJECT" port litellm 4000 2>/dev/null | cut -d: -f2); then
            if curl -sf "http://localhost:$litellm_port/health" &>/dev/null; then
                log_info "LiteLLM HTTP health endpoint accessible"
                pass_test "LiteLLM Service and Health Checks"
            else
                fail_test "LiteLLM Service and Health Checks" "HTTP health endpoint not accessible"
            fi
        else
            fail_test "LiteLLM Service and Health Checks" "Could not determine LiteLLM port"
        fi
    else
        fail_test "LiteLLM Service and Health Checks" "Health check failed"
    fi
}

# Test network connectivity between containers
test_network_connectivity() {
    start_test "Network Connectivity Between Containers"

    # Ensure LiteLLM is running
    if ! docker compose -p "$COMPOSE_PROJECT" --profile ollama ps litellm | grep -q "Up"; then
        docker compose -p "$COMPOSE_PROJECT" --profile ollama up -d litellm &>/dev/null
        sleep 10
    fi

    # Test connectivity from ralph-ollama to litellm
    local connectivity_result
    if connectivity_result=$(docker compose -p "$COMPOSE_PROJECT" --profile ollama run --rm \
        ralph-ollama shell -c "curl -sf http://litellm:4000/health" 2>/dev/null); then

        log_info "Network connectivity between containers working"
        pass_test "Network Connectivity Between Containers"
    else
        # Get more details about the failure
        local debug_info
        debug_info=$(docker compose -p "$COMPOSE_PROJECT" --profile ollama run --rm \
            ralph-ollama shell -c "nslookup litellm && curl -v http://litellm:4000/health" 2>&1 || true)

        fail_test "Network Connectivity Between Containers" "Cannot reach litellm service from ralph container"
        log_error "Debug info: $debug_info"
    fi
}

# Test OAuth mode functionality
test_oauth_mode() {
    start_test "OAuth Mode Functionality"

    # Create mock OAuth credentials for testing
    mkdir -p "/tmp/ralph-test-claude"
    cat > "/tmp/ralph-test-claude/credentials.json" << 'EOF'
{
    "session_key": "test-session-key"
}
EOF

    # Test with mock credentials (will fail auth but should handle gracefully)
    local output
    if output=$(docker compose -p "$COMPOSE_PROJECT" run --rm \
        -v "/tmp/ralph-test-claude:/home/ralph/.claude" \
        ralph test 2>&1); then

        # Check if it detected OAuth mode
        if echo "$output" | grep -q "OAuth"; then
            log_info "OAuth mode detection working"
            pass_test "OAuth Mode Functionality"
        else
            fail_test "OAuth Mode Functionality" "OAuth mode not detected properly"
        fi
    else
        # Expected to fail due to invalid credentials, but should detect mode
        if echo "$output" | grep -q -E "(OAuth|credentials)"; then
            log_info "OAuth mode detection working (auth failed as expected)"
            pass_test "OAuth Mode Functionality"
        else
            fail_test "OAuth Mode Functionality" "OAuth mode not detected"
        fi
    fi

    # Cleanup mock credentials
    rm -rf "/tmp/ralph-test-claude"
}

# Test Ollama mode with LiteLLM proxy
test_ollama_mode() {
    start_test "Ollama Mode with LiteLLM Proxy"

    # Start the full Ollama stack
    log_info "Starting Ollama mode services..."
    if ! docker compose -p "$COMPOSE_PROJECT" --profile ollama up -d 2>/dev/null; then
        fail_test "Ollama Mode with LiteLLM Proxy" "Failed to start Ollama services"
        return 1
    fi

    # Wait for services to be ready
    if ! wait_for_service "LiteLLM in Ollama mode" \
        "docker compose -p $COMPOSE_PROJECT ps litellm --format json | grep -q '\"Health\":\"healthy\"'" \
        120 5; then
        fail_test "Ollama Mode with LiteLLM Proxy" "LiteLLM service not ready"
        return 1
    fi

    # Test that ralph-ollama can connect to the proxy
    local test_output
    if test_output=$(docker compose -p "$COMPOSE_PROJECT" --profile ollama exec ralph-ollama \
        /home/ralph/scripts/entrypoint.sh test 2>&1); then

        if echo "$test_output" | grep -q "LiteLLM proxy -> Ollama"; then
            log_info "Ollama mode detection and connectivity working"
            pass_test "Ollama Mode with LiteLLM Proxy"
        else
            fail_test "Ollama Mode with LiteLLM Proxy" "Mode detection failed"
        fi
    else
        fail_test "Ollama Mode with LiteLLM Proxy" "Connection test failed"
        log_error "Test output: $test_output"
    fi
}

# Test error conditions
test_error_conditions() {
    start_test "Error Conditions and Failure Scenarios"

    # Test 1: Missing credentials
    local output
    if output=$(docker compose -p "$COMPOSE_PROJECT" run --rm \
        -e ANTHROPIC_API_KEY="" \
        -e ANTHROPIC_BASE_URL="" \
        ralph test 2>&1); then
        fail_test "Error Conditions" "Should have failed with missing credentials"
        return 1
    else
        if echo "$output" | grep -q "No authentication found"; then
            log_info "Missing credentials properly detected"
        else
            fail_test "Error Conditions" "Missing credentials not properly handled"
            return 1
        fi
    fi

    # Test 2: Invalid LiteLLM URL
    if output=$(docker compose -p "$COMPOSE_PROJECT" run --rm \
        -e ANTHROPIC_BASE_URL="http://invalid-litellm:4000" \
        -e ANTHROPIC_API_KEY="sk-test" \
        ralph test 2>&1); then
        fail_test "Error Conditions" "Should have failed with invalid LiteLLM URL"
        return 1
    else
        if echo "$output" | grep -q -E "(did not become ready|connection refused)"; then
            log_info "Invalid LiteLLM URL properly handled"
        else
            fail_test "Error Conditions" "Invalid LiteLLM URL not properly handled"
            return 1
        fi
    fi

    pass_test "Error Conditions and Failure Scenarios"
}

# Test service dependency management
test_service_dependencies() {
    start_test "Service Dependencies and Startup Order"

    # Stop any running services
    docker compose -p "$COMPOSE_PROJECT" --profile ollama down &>/dev/null || true

    # Start ralph-ollama (which depends on litellm)
    log_info "Testing service dependency startup..."
    if docker compose -p "$COMPOSE_PROJECT" --profile ollama up -d ralph-ollama &>/dev/null; then

        # Check that both services are running
        sleep 15  # Give time for startup

        local litellm_running ralph_running
        litellm_running=$(docker compose -p "$COMPOSE_PROJECT" ps litellm --format json | grep -c '"State":"running"' || echo "0")
        ralph_running=$(docker compose -p "$COMPOSE_PROJECT" ps ralph-ollama --format json | grep -c '"State":"running"' || echo "0")

        if [ "$litellm_running" -gt 0 ] && [ "$ralph_running" -gt 0 ]; then
            log_info "Service dependencies working correctly"
            pass_test "Service Dependencies and Startup Order"
        else
            fail_test "Service Dependencies and Startup Order" "Not all required services are running"
        fi
    else
        fail_test "Service Dependencies and Startup Order" "Failed to start dependent services"
    fi
}

# Test configuration validation
test_configuration_validation() {
    start_test "Configuration Validation"

    # Test various configuration scenarios
    local scenarios=(
        "RALPH_MODE=build RALPH_MODEL=opus RALPH_OUTPUT_FORMAT=pretty"
        "RALPH_MODE=plan RALPH_MODEL=ollama/qwen2.5-coder:7b RALPH_OUTPUT_FORMAT=json"
        "RALPH_MAX_ITERATIONS=5 RALPH_PUSH_AFTER_COMMIT=false"
    )

    for scenario in "${scenarios[@]}"; do
        log_info "Testing configuration: $scenario"

        local config_output
        if config_output=$(env $scenario docker compose -p "$COMPOSE_PROJECT" run --rm ralph version 2>&1); then
            log_info "Configuration scenario passed: $scenario"
        else
            fail_test "Configuration Validation" "Failed with config: $scenario"
            return 1
        fi
    done

    pass_test "Configuration Validation"
}

# Display test summary
show_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph Docker Integration Test Results"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Total Tests: $TESTS_TOTAL"
    echo "  Passed:      $TESTS_PASSED"
    echo "  Failed:      $TESTS_FAILED"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        echo ""
        echo "Failed Tests:"
        for failed_test in "${FAILED_TESTS[@]}"; do
            echo "  - $failed_test"
        done
    fi

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if [ "$TESTS_FAILED" -gt 0 ]; then
        log_error "Some tests failed!"
        return 1
    else
        log_success "All tests passed!"
        return 0
    fi
}

# Main test execution
main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph Docker Integration Tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Project: $COMPOSE_PROJECT"
    echo "  Timeout: ${TIMEOUT_SECONDS}s"
    echo "  Cleanup: Success=$CLEANUP_ON_SUCCESS, Failure=$CLEANUP_ON_FAILURE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Prerequisites check
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        exit 1
    fi

    # Run tests
    test_docker_compose_build
    test_container_startup
    test_volume_mounts
    test_configuration_validation
    test_litellm_service
    test_network_connectivity
    test_oauth_mode
    test_ollama_mode
    test_service_dependencies
    test_error_conditions

    # Show results
    show_summary
}

# Handle command line arguments
case "${1:-run}" in
    run)
        main
        ;;
    cleanup)
        cleanup true
        ;;
    help|--help|-h)
        cat << 'EOF'
Ralph Docker Integration Tests

USAGE:
    ./test_docker_integration.sh [COMMAND]

COMMANDS:
    run       Run all integration tests (default)
    cleanup   Force cleanup of test containers and volumes
    help      Show this help message

ENVIRONMENT VARIABLES:
    CLEANUP_ON_SUCCESS    Clean up after successful tests (default: true)
    CLEANUP_ON_FAILURE    Clean up after failed tests (default: true)

EXAMPLES:
    # Run all tests
    ./test_docker_integration.sh

    # Run tests without cleanup
    CLEANUP_ON_SUCCESS=false ./test_docker_integration.sh

    # Force cleanup manually
    ./test_docker_integration.sh cleanup
EOF
        ;;
    *)
        log_error "Unknown command: $1"
        log_info "Run './test_docker_integration.sh help' for usage information"
        exit 1
        ;;
esac