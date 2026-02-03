# Implementation Plan

## Current Status
While the development framework is functionally stable, there are architectural inconsistencies that need resolution to clarify the system's purpose and ensure proper functionality across all components.

## Priority Items

### 1. Critical: Prompt-Reality Mismatch
- The agent prompts reference "src/*" for application source code, but no src/ directory exists
- This is a fundamental issue - the system is a development framework/template, not an application with source code
- Either add example application code or fix prompt references

### 2. Missing Test Suite
- No formal test suite exists (no test files, test configuration, or test dependencies)
- Only basic connectivity tests and syntax checks available
- Need comprehensive testing for shell scripts, JavaScript formatter, Docker integration

### 3. Documentation Inconsistencies
- README and prompts assume application context that doesn't exist
- Unclear if this is meant to be a reusable template or specific application
- Need to clarify purpose and fix documentation

### 4. Dual Output Formatters
- Both Node.js (output-formatter.js) and Bash (format-output.sh) formatters exist with similar functionality
- Potential redundancy that should be consolidated

## Completed Items

### Shell Script Error Handling and Variable Quoting
**Files**: scripts/format-output.sh, scripts/loop.sh, scripts/extract-credentials.sh
**Issues Found**:
- format-output.sh: Missing `set -euo pipefail` for proper error handling
- format-output.sh: Unquoted variables in length comparison
- loop.sh: Invalid `local` keyword used outside function scope
- loop.sh: Unquoted variable in CLAUDE_EXIT comparison
- extract-credentials.sh: Missing directory creation before writing credentials
**Resolution**:
- Added `set -euo pipefail` to format-output.sh
- Fixed variable quoting in format-output.sh truncate_text function
- Changed `local push_output` to regular variable declaration in loop.sh
- Quoted CLAUDE_EXIT variable in loop.sh comparison
- Added `mkdir -p` to ensure directory exists in extract-credentials.sh

### Unused Variable in entrypoint.sh
**File**: scripts/entrypoint.sh
**Issue**: `auth_header` variable was constructed but never used.
**Resolution**: Removed the dead code. Health check now uses unauthenticated endpoint (LiteLLM allows this).

### Git Error Suppression in loop.sh
**File**: scripts/loop.sh
**Issue**: Git push errors were suppressed, making debugging difficult.
**Resolution**: Git push now logs actual errors while maintaining graceful fallback behavior.

### Missing jq Dependency Check in format-output.sh
**File**: scripts/format-output.sh
**Issue**: No validation that jq was installed before use.
**Resolution**: Added dependency check at script start with graceful fallback to raw output.

### Variable Quoting in loop.sh
**File**: scripts/loop.sh
**Issue**: `$OUTPUT_TMP` was not quoted in trap command.
**Resolution**: Fixed quoting to use single quotes with proper variable expansion.

### Linux Compatibility - host.docker.internal
**Files**: docker-compose.yml, litellm-config.yaml, .env.example
**Issue**: `host.docker.internal:host-gateway` only works on Docker Desktop (macOS/Windows).
**Resolution**: Added DOCKER_HOST_IP environment variable support for Linux compatibility.

### Unpinned Dependencies
**Files**: Dockerfile
**Issue**: Node.js and Claude Code CLI versions were unpinned.
**Resolution**: Pinned Node.js to 22.13-slim and Claude Code CLI to major version 1.

### Missing Restart Policies
**File**: docker-compose.yml
**Issue**: No restart policies for services.
**Resolution**: Added `restart: on-failure` to ralph and ralph-ollama services.

### Health Check Token Hardcoding
**File**: docker-compose.yml
**Issue**: Bearer token was hardcoded in litellm health check.
**Resolution**: Removed Bearer token (LiteLLM allows unauthenticated health checks).

### Inconsistent Environment Variable Names in .env.example
**File**: .env.example
**Issue**: Used wrong variable name `ANTHROPIC_AUTH_TOKEN`.
**Resolution**: Updated to correct variable names with proper documentation.

## Notes
- specs/ directory created with ARCHITECTURE.md and FEATURES.md
- README serves as primary documentation
- All scripts use proper `set -euo pipefail` for error handling
- Security model is well-implemented (non-root user, credential isolation)
- Docker is not available inside the container, so build tests must be done on the host machine
