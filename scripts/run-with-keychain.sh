#!/bin/bash
# Run Ralph Docker with credentials extracted from macOS Keychain
# Usage: ./run-with-keychain.sh [docker-compose arguments]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RALPH_DOCKER_DIR="$(dirname "$SCRIPT_DIR")"
CREDS_FILE="$HOME/.claude/.credentials.json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${CYAN}[ralph]${NC} $1"; }
log_error() { echo -e "${RED}[ralph]${NC} $1"; }
log_success() { echo -e "${GREEN}[ralph]${NC} $1"; }

cleanup() {
    # Remove credentials file
    if [[ -f "$CREDS_FILE" ]]; then
        rm -f "$CREDS_FILE"
        log_info "Cleaned up temporary credentials"
    fi
}

# Ensure cleanup runs on interrupt
trap cleanup INT TERM

# Check if running on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    log_error "This script only works on macOS (uses Keychain)"
    exit 1
fi

# Extract credentials from Keychain
log_info "Extracting credentials from macOS Keychain..."
CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || echo "")

if [[ -z "$CREDS" ]]; then
    log_error "Could not find Claude credentials in Keychain"
    echo "Make sure you're logged in with: claude auth login"
    exit 1
fi

# Write credentials to file that Claude CLI expects
echo "$CREDS" > "$CREDS_FILE"
chmod 600 "$CREDS_FILE"
log_success "Credentials written to $CREDS_FILE"

# Change to ralph-docker directory
cd "$RALPH_DOCKER_DIR"

# Export RALPH_* environment variables so docker compose can use them
export RALPH_MODE="${RALPH_MODE:-build}"
export RALPH_MAX_ITERATIONS="${RALPH_MAX_ITERATIONS:-0}"
export RALPH_MODEL="${RALPH_MODEL:-opus}"
export RALPH_OUTPUT_FORMAT="${RALPH_OUTPUT_FORMAT:-pretty}"
export RALPH_PUSH_AFTER_COMMIT="${RALPH_PUSH_AFTER_COMMIT:-true}"
export WORKSPACE_PATH="${WORKSPACE_PATH:-.}"

# Run docker compose (not exec, so cleanup runs after)
log_info "Starting Ralph with Max subscription credentials..."
log_info "  Mode: $RALPH_MODE"
log_info "  Max Iterations: $RALPH_MAX_ITERATIONS (0=unlimited)"
log_info "  Model: $RALPH_MODEL"
log_info "  Workspace: $WORKSPACE_PATH"
docker compose "$@"
EXIT_CODE=$?

# Cleanup credentials file
cleanup
exit $EXIT_CODE
