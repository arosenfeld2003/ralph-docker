#!/bin/bash
# Ollama Mode Specific Tests
# Tests the Ollama integration via LiteLLM proxy

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_PROJECT="ralph-ollama-test-$(date +%s)"

log_info() {
    echo -e "${CYAN}[OLLAMA-TEST]${NC} $1"
}

log_error() {
    echo -e "${RED}[OLLAMA-TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OLLAMA-TEST]${NC} $1"
}

cleanup() {
    log_info "Cleaning up Ollama test environment..."
    docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama down --volumes --remove-orphans 2>/dev/null || true
}

trap 'cleanup' EXIT

wait_for_service() {
    local service_name="$1"
    local health_cmd="$2"
    local timeout="${3:-60}"

    log_info "Waiting for $service_name to be ready..."

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$health_cmd" &>/dev/null; then
            log_success "$service_name is ready"
            return 0
        fi

        sleep 2
        elapsed=$((elapsed + 2))
        echo -ne "\rWaiting for $service_name... ${elapsed}s/${timeout}s"
    done

    echo ""
    log_error "$service_name failed to become ready within ${timeout}s"
    return 1
}

test_litellm_proxy_startup() {
    log_info "Testing LiteLLM proxy startup..."

    # Start LiteLLM service
    if ! docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama up -d litellm 2>/dev/null; then
        log_error "Failed to start LiteLLM service"
        return 1
    fi

    # Wait for health check
    if wait_for_service "LiteLLM" \
        "docker compose -p $COMPOSE_PROJECT -f $PROJECT_DIR/docker-compose.yml ps litellm --format json | grep -q '\"Health\":\"healthy\"'" \
        120; then

        log_success "LiteLLM proxy started successfully"
    else
        log_error "LiteLLM proxy failed to start"
        return 1
    fi
}

test_litellm_api_endpoints() {
    log_info "Testing LiteLLM API endpoints..."

    # Get the exposed port
    local litellm_port
    if ! litellm_port=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" port litellm 4000 2>/dev/null | cut -d: -f2); then
        log_error "Could not determine LiteLLM port"
        return 1
    fi

    # Test health endpoint
    if curl -sf "http://localhost:$litellm_port/health" &>/dev/null; then
        log_success "LiteLLM health endpoint accessible"
    else
        log_error "LiteLLM health endpoint not accessible"
        return 1
    fi

    # Test models endpoint (should list configured models)
    local models_response
    if models_response=$(curl -sf "http://localhost:$litellm_port/v1/models" -H "Authorization: Bearer sk-ralph-local" 2>/dev/null); then
        if echo "$models_response" | grep -q "ollama/qwen2.5-coder"; then
            log_success "LiteLLM models endpoint working and configured models available"
        else
            log_error "LiteLLM models endpoint not returning expected models"
            log_error "Response: $models_response"
            return 1
        fi
    else
        log_error "LiteLLM models endpoint not accessible"
        return 1
    fi
}

test_ralph_ollama_connection() {
    log_info "Testing Ralph-Ollama container connection to LiteLLM..."

    # Start the full Ollama stack
    if ! docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama up -d 2>/dev/null; then
        log_error "Failed to start Ollama stack"
        return 1
    fi

    # Wait for LiteLLM to be healthy
    if ! wait_for_service "LiteLLM for Ollama stack" \
        "docker compose -p $COMPOSE_PROJECT -f $PROJECT_DIR/docker-compose.yml ps litellm --format json | grep -q '\"Health\":\"healthy\"'" \
        120; then
        log_error "LiteLLM not ready for Ollama stack test"
        return 1
    fi

    # Test connection from ralph-ollama to litellm
    local connection_test
    if connection_test=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama exec ralph-ollama \
        curl -sf "http://litellm:4000/health" 2>&1); then

        log_success "Ralph-Ollama can connect to LiteLLM proxy"
    else
        log_error "Ralph-Ollama cannot connect to LiteLLM proxy"
        log_error "Connection test output: $connection_test"
        return 1
    fi

    # Test authentication detection
    local auth_test
    if auth_test=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama exec ralph-ollama \
        /home/ralph/scripts/entrypoint.sh test 2>&1); then

        if echo "$auth_test" | grep -q "LiteLLM proxy -> Ollama"; then
            log_success "Ralph-Ollama correctly detects LiteLLM proxy mode"
        else
            log_error "Ralph-Ollama not detecting LiteLLM proxy mode correctly"
            log_error "Auth test output: $auth_test"
            return 1
        fi
    else
        # May fail due to missing Ollama backend, but should detect the mode
        if echo "$auth_test" | grep -q "LiteLLM proxy -> Ollama"; then
            log_success "Ralph-Ollama mode detection working (connection failure expected)"
        else
            log_error "Ralph-Ollama mode detection failed"
            return 1
        fi
    fi
}

test_ollama_environment_variables() {
    log_info "Testing Ollama-specific environment variables..."

    # Test model configuration
    local test_model="ollama/qwen2.5-coder:32b"
    local config_test

    if config_test=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama run --rm \
        -e RALPH_MODEL="$test_model" \
        ralph-ollama shell -c "echo \$RALPH_MODEL" 2>/dev/null); then

        if [ "$config_test" = "$test_model" ]; then
            log_success "RALPH_MODEL environment variable working correctly"
        else
            log_error "RALPH_MODEL environment variable not set correctly"
            return 1
        fi
    else
        log_error "Failed to test RALPH_MODEL environment variable"
        return 1
    fi

    # Test ANTHROPIC_BASE_URL points to LiteLLM
    local base_url_test
    if base_url_test=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama run --rm \
        ralph-ollama shell -c "echo \$ANTHROPIC_BASE_URL" 2>/dev/null); then

        if [ "$base_url_test" = "http://litellm:4000" ]; then
            log_success "ANTHROPIC_BASE_URL points to LiteLLM correctly"
        else
            log_error "ANTHROPIC_BASE_URL not configured correctly: $base_url_test"
            return 1
        fi
    else
        log_error "Failed to test ANTHROPIC_BASE_URL"
        return 1
    fi

    # Test ANTHROPIC_API_KEY is set to local key
    local api_key_test
    if api_key_test=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama run --rm \
        ralph-ollama shell -c "echo \$ANTHROPIC_API_KEY" 2>/dev/null); then

        if [ "$api_key_test" = "sk-ralph-local" ]; then
            log_success "ANTHROPIC_API_KEY set correctly for local mode"
        else
            log_error "ANTHROPIC_API_KEY not configured correctly"
            return 1
        fi
    else
        log_error "Failed to test ANTHROPIC_API_KEY"
        return 1
    fi
}

test_service_dependencies() {
    log_info "Testing Ollama service dependencies..."

    # Clean slate
    docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama down &>/dev/null || true

    # Start ralph-ollama which should automatically start litellm due to depends_on
    if docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama up -d ralph-ollama &>/dev/null; then

        # Wait a moment for startup
        sleep 15

        # Check that both services are running
        local litellm_running ralph_running
        litellm_running=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" ps litellm --format json | grep -c '"State":"running"' || echo "0")
        ralph_running=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" ps ralph-ollama --format json | grep -c '"State":"running"' || echo "0")

        if [ "$litellm_running" -gt 0 ] && [ "$ralph_running" -gt 0 ]; then
            log_success "Service dependencies working - both LiteLLM and Ralph-Ollama are running"
        else
            log_error "Service dependencies failed - not all required services are running"
            log_error "LiteLLM running: $litellm_running, Ralph-Ollama running: $ralph_running"
            return 1
        fi
    else
        log_error "Failed to start ralph-ollama with dependencies"
        return 1
    fi
}

test_host_network_configuration() {
    log_info "Testing host network configuration for Ollama connectivity..."

    # Test that the extra_hosts configuration works
    local host_resolution
    if host_resolution=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama run --rm \
        litellm sh -c "nslookup host.docker.internal" 2>&1); then

        if echo "$host_resolution" | grep -q "Address:"; then
            log_success "host.docker.internal resolves correctly for LiteLLM"
        else
            log_error "host.docker.internal not resolving for LiteLLM"
            log_error "Resolution output: $host_resolution"
            return 1
        fi
    else
        log_error "Failed to test host.docker.internal resolution"
        return 1
    fi

    # Test from ralph-ollama container as well
    if host_resolution=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama run --rm \
        ralph-ollama shell -c "nslookup host.docker.internal" 2>&1); then

        if echo "$host_resolution" | grep -q "Address:"; then
            log_success "host.docker.internal resolves correctly for Ralph-Ollama"
        else
            log_error "host.docker.internal not resolving for Ralph-Ollama"
            return 1
        fi
    else
        log_error "Failed to test host.docker.internal resolution from Ralph-Ollama"
        return 1
    fi
}

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph Ollama Mode Integration Tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    cd "$PROJECT_DIR"

    test_litellm_proxy_startup
    test_litellm_api_endpoints
    test_ollama_environment_variables
    test_host_network_configuration
    test_service_dependencies
    test_ralph_ollama_connection

    log_success "All Ollama mode tests passed!"
}

main "$@"