#!/bin/bash
# Performance and Stress Tests
# Tests Docker integration under various load conditions

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COMPOSE_PROJECT="ralph-perf-test-$(date +%s)"

log_info() {
    echo -e "${CYAN}[PERF-TEST]${NC} $1"
}

log_error() {
    echo -e "${RED}[PERF-TEST]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[PERF-TEST]${NC} $1"
}

cleanup() {
    log_info "Cleaning up performance test environment..."
    docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" down --volumes --remove-orphans 2>/dev/null || true
    rm -rf "/tmp/ralph-perf-test"*
}

trap 'cleanup' EXIT

test_container_startup_time() {
    log_info "Testing container startup performance..."

    local start_time end_time duration

    # Test OAuth mode startup
    start_time=$(date +%s)
    if docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm ralph version &>/dev/null; then
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        if [ $duration -lt 30 ]; then
            log_success "OAuth mode startup time: ${duration}s (< 30s target)"
        else
            log_error "OAuth mode startup time: ${duration}s (> 30s - slow)"
        fi
    else
        log_error "OAuth mode container failed to start"
        return 1
    fi

    # Test Ollama mode startup
    start_time=$(date +%s)
    if docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama up -d litellm &>/dev/null; then
        # Wait for health check
        while ! docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" ps litellm --format json | grep -q '"Health":"healthy"'; do
            sleep 1
        done
        end_time=$(date +%s)
        duration=$((end_time - start_time))

        if [ $duration -lt 60 ]; then
            log_success "Ollama mode startup time: ${duration}s (< 60s target)"
        else
            log_error "Ollama mode startup time: ${duration}s (> 60s - slow)"
        fi
    else
        log_error "Ollama mode containers failed to start"
        return 1
    fi
}

test_concurrent_containers() {
    log_info "Testing concurrent container handling..."

    # Create multiple workspaces
    for i in {1..3}; do
        mkdir -p "/tmp/ralph-perf-test-$i"
        echo "console.log('test project $i');" > "/tmp/ralph-perf-test-$i/test.js"
    done

    # Start multiple containers simultaneously
    local pids=()
    for i in {1..3}; do
        (
            docker compose -p "${COMPOSE_PROJECT}-$i" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
                -v "/tmp/ralph-perf-test-$i:/home/ralph/workspace" \
                ralph version
        ) &
        pids+=($!)
    done

    # Wait for all to complete
    local failed=0
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            ((failed++))
        fi
    done

    if [ $failed -eq 0 ]; then
        log_success "All 3 concurrent containers completed successfully"
    else
        log_error "$failed out of 3 concurrent containers failed"
        return 1
    fi

    # Cleanup concurrent test containers
    for i in {1..3}; do
        docker compose -p "${COMPOSE_PROJECT}-$i" -f "$PROJECT_DIR/docker-compose.yml" down --volumes 2>/dev/null || true
    done
}

test_volume_performance() {
    log_info "Testing volume mount performance..."

    # Create a workspace with many files
    local test_workspace="/tmp/ralph-perf-test-volume"
    mkdir -p "$test_workspace"

    # Create 1000 small files
    log_info "Creating test files..."
    for i in {1..1000}; do
        echo "// Test file $i" > "$test_workspace/test_file_$i.js"
    done

    # Test read performance
    local start_time end_time duration
    start_time=$(date +%s.%N)

    if docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "$test_workspace:/home/ralph/workspace" \
        ralph shell -c "find /home/ralph/workspace -name '*.js' | wc -l" &>/dev/null; then

        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc -l)

        # Should complete in under 5 seconds
        if (( $(echo "$duration < 5" | bc -l) )); then
            log_success "Volume read performance: ${duration}s (< 5s target)"
        else
            log_error "Volume read performance: ${duration}s (> 5s - slow)"
        fi
    else
        log_error "Volume read test failed"
        return 1
    fi

    # Test write performance
    start_time=$(date +%s.%N)

    if docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run --rm \
        -v "$test_workspace:/home/ralph/workspace" \
        ralph shell -c "for i in {1..100}; do echo '// Generated file' > /home/ralph/workspace/generated_\$i.js; done" &>/dev/null; then

        end_time=$(date +%s.%N)
        duration=$(echo "$end_time - $start_time" | bc -l)

        # Should complete in under 3 seconds
        if (( $(echo "$duration < 3" | bc -l) )); then
            log_success "Volume write performance: ${duration}s (< 3s target)"
        else
            log_error "Volume write performance: ${duration}s (> 3s - slow)"
        fi
    else
        log_error "Volume write test failed"
        return 1
    fi

    rm -rf "$test_workspace"
}

test_memory_usage() {
    log_info "Testing memory usage..."

    # Start container and check memory usage
    local container_id
    if container_id=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" run -d ralph shell); then

        sleep 5  # Let container settle

        # Get memory stats
        local memory_usage
        if memory_usage=$(docker stats --no-stream --format "{{.MemUsage}}" "$container_id" 2>/dev/null); then

            # Extract memory in MB (assuming format like "123MiB / 2GiB")
            local memory_mb
            memory_mb=$(echo "$memory_usage" | cut -d' ' -f1 | sed 's/MiB//' | sed 's/GiB/000/' | cut -d'.' -f1)

            if [ "$memory_mb" -lt 200 ]; then
                log_success "Memory usage: ${memory_mb}MB (< 200MB target)"
            else
                log_error "Memory usage: ${memory_mb}MB (> 200MB - high)"
            fi
        else
            log_error "Could not get memory stats"
        fi

        docker stop "$container_id" &>/dev/null
    else
        log_error "Could not start container for memory test"
        return 1
    fi
}

test_litellm_response_time() {
    log_info "Testing LiteLLM proxy response time..."

    # Start LiteLLM
    if ! docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" --profile ollama up -d litellm &>/dev/null; then
        log_error "Failed to start LiteLLM for performance test"
        return 1
    fi

    # Wait for health
    local timeout=60
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" ps litellm --format json | grep -q '"Health":"healthy"'; then
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    if [ $elapsed -ge $timeout ]; then
        log_error "LiteLLM not ready for performance test"
        return 1
    fi

    # Get port and test response time
    local litellm_port
    if litellm_port=$(docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" port litellm 4000 | cut -d: -f2); then

        # Test health endpoint response time
        local start_time end_time duration
        start_time=$(date +%s.%N)

        if curl -sf "http://localhost:$litellm_port/health" &>/dev/null; then
            end_time=$(date +%s.%N)
            duration=$(echo "$end_time - $start_time" | bc -l)

            # Should respond in under 1 second
            if (( $(echo "$duration < 1" | bc -l) )); then
                log_success "LiteLLM health response time: ${duration}s (< 1s target)"
            else
                log_error "LiteLLM health response time: ${duration}s (> 1s - slow)"
            fi
        else
            log_error "LiteLLM health endpoint not responding"
            return 1
        fi

        # Test models endpoint response time
        start_time=$(date +%s.%N)

        if curl -sf "http://localhost:$litellm_port/v1/models" -H "Authorization: Bearer sk-ralph-local" &>/dev/null; then
            end_time=$(date +%s.%N)
            duration=$(echo "$end_time - $start_time" | bc -l)

            # Should respond in under 2 seconds
            if (( $(echo "$duration < 2" | bc -l) )); then
                log_success "LiteLLM models response time: ${duration}s (< 2s target)"
            else
                log_error "LiteLLM models response time: ${duration}s (> 2s - slow)"
            fi
        else
            log_error "LiteLLM models endpoint not responding"
            return 1
        fi

    else
        log_error "Could not determine LiteLLM port for performance test"
        return 1
    fi
}

test_resource_cleanup() {
    log_info "Testing resource cleanup efficiency..."

    # Start and stop containers multiple times to test cleanup
    local start_time end_time duration

    start_time=$(date +%s)

    for i in {1..5}; do
        log_info "Cleanup test iteration $i/5"

        # Start services
        docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" up -d ralph &>/dev/null

        # Stop services
        docker compose -p "$COMPOSE_PROJECT" -f "$PROJECT_DIR/docker-compose.yml" down --volumes &>/dev/null
    done

    end_time=$(date +%s)
    duration=$((end_time - start_time))

    # 5 iterations should complete in under 2 minutes
    if [ $duration -lt 120 ]; then
        log_success "Resource cleanup: ${duration}s for 5 iterations (< 120s target)"
    else
        log_error "Resource cleanup: ${duration}s for 5 iterations (> 120s - slow)"
    fi

    # Check for leftover containers
    local leftover_containers
    if leftover_containers=$(docker ps -a --filter "label=com.docker.compose.project=$COMPOSE_PROJECT" --format "{{.Names}}" | wc -l); then
        if [ "$leftover_containers" -eq 0 ]; then
            log_success "No leftover containers after cleanup"
        else
            log_error "$leftover_containers leftover containers found"
        fi
    fi
}

main() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Ralph Docker Performance Tests"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Check for bc (basic calculator) for timing calculations
    if ! command -v bc >/dev/null 2>&1; then
        log_error "bc (basic calculator) is required for timing tests"
        exit 1
    fi

    cd "$PROJECT_DIR"

    test_container_startup_time
    test_memory_usage
    test_volume_performance
    test_concurrent_containers
    test_litellm_response_time
    test_resource_cleanup

    log_success "All performance tests completed!"
}

main "$@"