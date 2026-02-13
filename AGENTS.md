# Agent Operations Guide

## Environment Notes

- **Docker**: Not available inside the container. Build/test must be done on host.
- **Git**: Available. Use for commits and tags.
- **Git Remote**: Not configured. Push commands will fail until remote is added.
- **Node.js**: Available for running JavaScript files.

## Running Tests

```bash
# Build and test on host machine (not inside container)
docker compose build ralph
docker compose run --rm ralph test
```

## Common Commands

```bash
# Check syntax of shell scripts
bash -n scripts/*.sh

# Check syntax of JavaScript
node --check lib/output-formatter.js

# Check Entire session observability status (if enabled)
entire status
```
