# Agent Operations Guide

## Project Goal

Improve the UX for Ralph-Docker - the README is much too long and doesn't flow naturally. Additionally, give the user a clear summary of the work that was done after completion (whether the ralph loop finishes or is terminated).

## Tech Stack

- Docker for containerization
- Bash for shell scripting (primary automation)
- Node.js for JavaScript utilities (output formatter, Claude CLI)
- Python for proxy service

## Build & Run

- Build: `docker compose build ralph`
- Run: `docker compose up ralph`

## Validation

- Tests: `./tests/run_tests.sh`
- Syntax check (Bash): `bash -n scripts/*.sh`
- Syntax check (JS): `node --check lib/output-formatter.js`

## Environment Notes

- **Docker**: Not available inside the container. Build/test must be done on host.
- **Git**: Available. Use for commits and tags.
- **Git Remote**: Not configured. Push commands will fail until remote is added.
- **Node.js**: Available for running JavaScript files.

## Work Summary Feature

- Located at end of loop.sh after main loop
- generate_work_summary() shows commits, files changed, duration, next steps
- cleanup_scaffolding() removes Ralph files before PR creation
- Graceful interruption (Ctrl+C) triggers summary via signal trap

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
