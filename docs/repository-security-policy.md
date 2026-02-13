# Repository Security Policy

This document describes the security policies, settings, and governance decisions for the ralph-docker repository.

## GitHub Repository Settings

### General

| Setting | Value | Rationale |
|---------|-------|-----------|
| Visibility | Public | Open source project, encouraging community contributions |
| License | MIT | Permissive license, standard for developer tools |
| Issues | Enabled | Primary channel for bug reports and feature requests |
| Wiki | Disabled | Documentation lives in `docs/` and README.md to stay version-controlled |
| Discussions | Disabled | Issues suffice for a project of this size |

### Merge Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| Squash merge | Enabled (preferred) | Clean history from contributor PRs |
| Merge commit | Enabled | Available for multi-commit PRs where history matters |
| Rebase merge | Disabled | Prevents confusing commit rewrites |
| Auto-delete branches | Enabled | Keeps the repo tidy after PRs merge |

### Branch Protection (main)

| Rule | Value | Rationale |
|------|-------|-----------|
| Require PR reviews | 1 approval | Prevents unreviewed code from reaching main |
| Dismiss stale reviews | Yes | Forces re-review after changes are pushed |
| Force pushes | Blocked | Protects commit history |
| Branch deletion | Blocked | Prevents accidental deletion of main |
| Admin enforcement | Off | Allows maintainer to bypass in emergencies |

### Security Features

| Feature | Status | Rationale |
|---------|--------|-----------|
| Secret scanning | Enabled | Detects accidentally committed credentials |
| Push protection | Enabled | Blocks pushes containing secrets before they reach the repo |
| Dependabot alerts | Enabled | Notifies about vulnerable dependencies |
| Dependabot security updates | Enabled | Auto-creates PRs to fix vulnerable dependencies |

## Governance Files

| File | Purpose |
|------|---------|
| `LICENSE` | MIT license — defines legal terms for use and contribution |
| `SECURITY.md` | Vulnerability reporting process (private advisories, not public issues) |
| `CONTRIBUTING.md` | Contributor guide — fork, branch, test, PR workflow |
| `.github/CODEOWNERS` | Auto-assigns reviewers; maintainer owns all files |

## Credential Security Model

Ralph Docker supports two authentication methods:

```
Option A: ANTHROPIC_API_KEY env var → container environment → Claude CLI
Option B: docker compose run --rm ralph login → ~/.claude volume → Claude CLI
```

### Safeguards

1. **API keys in memory only**: When using `ANTHROPIC_API_KEY`, the key exists only as an environment variable — never written to disk by Ralph
2. **Login credentials in mounted volume**: Interactive login credentials persist in the host's `~/.claude` directory (mounted into the container)
3. **Non-root container**: Ralph runs as user `ralph` (UID 1000), not root
4. **No credential logging**: Credential values are never written to stdout/stderr or log files
5. **Gitignored**: `.credentials.json` patterns are excluded from version control

### What is NOT protected

- The mounted `~/.claude` volume is readable by the container
- The mounted workspace is fully writable — Ralph can modify any file in it
- `--dangerously-skip-permissions` means Claude CLI auto-approves all tool use inside the container

## Container Isolation Model

```
┌─────────────── Host ───────────────┐
│                                     │
│  ┌──────── Container ────────────┐  │
│  │ User: ralph (non-root)        │  │
│  │ Mounts:                       │  │
│  │   - workspace (read/write)    │  │
│  │   - .claude config (read)     │  │
│  │ No access to:                 │  │
│  │   - Host filesystem           │  │
│  │   - Host network (default)    │  │
│  │   - Other containers          │  │
│  │   - Docker socket             │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
```

### Blast radius

If Ralph produces unexpected behavior, the impact is limited to:
- Files within the mounted workspace directory
- Git commits/pushes to the workspace repository
- API calls using the provided Claude credentials

Ralph **cannot**:
- Access files outside the mounted workspace
- Install software on the host
- Modify system configuration
- Access other Docker containers or the Docker socket

## Dependency Management

### Current dependencies

| Dependency | Source | Auto-updated |
|------------|--------|--------------|
| Node.js 22 | Dockerfile (apt) | No — pinned for stability |
| Claude CLI | npm (Dockerfile) | Dependabot monitors |
| Entire CLI | GitHub release (Dockerfile) | No — optional, non-blocking install |
| LiteLLM | Python pip (litellm.Dockerfile) | Dependabot monitors |

### Update policy

- **Security patches**: Apply immediately via Dependabot PRs
- **Minor/major updates**: Review and test before merging
- **Base image**: Periodically update `node:22-slim` to latest patch

## Incident Response

1. **Credential leak**: Rotate the affected Claude API token immediately via claude.ai/settings
2. **Container escape CVE**: Update Docker Engine, rebuild images
3. **Dependency CVE**: Merge Dependabot PR or pin to patched version
4. **Malicious PR**: Reject; branch protection prevents direct pushes to main

## Review Checklist for PRs

When reviewing contributions, check for:

- [ ] No hardcoded credentials or tokens
- [ ] No new volume mounts that expand container access
- [ ] Shell scripts use `set -euo pipefail`
- [ ] Variables are properly quoted
- [ ] No `curl | sh` or similar unsafe install patterns
- [ ] Prompt changes don't instruct Claude to exfiltrate data
- [ ] Docker changes maintain non-root user
- [ ] Test coverage for behavioral changes
