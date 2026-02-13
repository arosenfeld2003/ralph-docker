# Contributing to Ralph Docker

Thanks for your interest in contributing! This guide will help you get started.

## Getting Started

1. **Fork** the repository
2. **Clone** your fork: `git clone git@github.com:YOUR_USERNAME/ralph-docker.git`
3. **Create a branch**: `git checkout -b my-feature`
4. **Make your changes**
5. **Test**: Run the test suite (see below)
6. **Commit**: Write clear commit messages
7. **Push**: `git push origin my-feature`
8. **Open a PR**: Target the `main` branch

## Development Setup

```bash
# Prerequisites
# - Docker Desktop (macOS/Windows) or Docker Engine (Linux)
# - Claude Max subscription (for OAuth mode testing)
# - Ollama (optional, for local model testing)

# Clone
git clone git@github.com:YOUR_USERNAME/ralph-docker.git
cd ralph-docker

# Run tests
./tests/run_tests.sh
```

## What to Contribute

- Bug fixes
- Documentation improvements
- New test cases
- Prompt improvements (PROMPT_build.md, PROMPT_plan.md)
- Output formatter enhancements

## Code Guidelines

- **Shell scripts**: Use `set -euo pipefail`, quote variables, use `shellcheck` if available
- **Keep it simple**: This is a lightweight tool, avoid over-engineering
- **Test your changes**: Add or update tests for any behavioral changes
- **Document the why**: Comments should explain reasoning, not restate code

## Commit Messages

Follow the conventional format:

```
type: Short description

Longer explanation if needed.
```

Types: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`

## Pull Request Process

1. PRs require at least one approval before merging
2. All status checks must pass
3. PRs are squash-merged to keep history clean
4. Branches are auto-deleted after merge

## Reporting Issues

- Use [GitHub Issues](https://github.com/arosenfeld2003/ralph-docker/issues)
- For security vulnerabilities, see [SECURITY.md](SECURITY.md)
- Include steps to reproduce, expected vs actual behavior, and your environment

## Code of Conduct

Be respectful, constructive, and collaborative. We're all here to build something useful.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
