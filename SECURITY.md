# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| main branch | Yes |
| Feature branches | No |

## Reporting a Vulnerability

**Do not open a public issue for security vulnerabilities.**

Instead, please report vulnerabilities privately via one of these methods:

1. **GitHub Security Advisories** (preferred): Go to [Security > Advisories](https://github.com/arosenfeld2003/ralph-docker/security/advisories/new) and create a new draft advisory.
2. **Email**: Contact the maintainer directly at the email listed on their GitHub profile.

### What to include

- Description of the vulnerability
- Steps to reproduce
- Affected files/components
- Potential impact
- Suggested fix (if any)

### Response timeline

- **Acknowledgment**: Within 48 hours
- **Assessment**: Within 1 week
- **Fix**: Depends on severity (critical: ASAP, high: 1-2 weeks, medium/low: next release)

## Security Considerations

This project handles sensitive credentials and runs code autonomously. Key areas of concern:

### Credential Handling
- API keys are passed via environment variable (never written to disk by Ralph)
- Interactive login credentials (`claude auth login`) persist in the mounted `~/.claude` volume
- No temporary credential files are created or cleaned up
- **Never commit credentials** to the repository

### Container Security
- Ralph runs with `--dangerously-skip-permissions` inside the container
- Container isolation limits blast radius to the mounted workspace
- The container runs as a non-root user (`ralph`)
- Only the specified workspace directory is mounted

### Git Operations
- Ralph creates branches and commits autonomously
- Ralph auto-creates `ralph/<workspace>-<timestamp>` branches (never modifies main directly)
- Review all Ralph-generated commits before merging to main

### What We Consider Vulnerabilities
- Credential leakage (tokens written to unexpected locations or logs)
- Container escape scenarios
- Unauthorized access to files outside the mounted workspace
- Injection via prompt files or spec files that could execute host commands
- Dependencies with known CVEs

### What We Do NOT Consider Vulnerabilities
- Ralph modifying files within the mounted workspace (this is expected behavior)
- Ralph making commits to the workspace branch (this is expected behavior)
- Behavior resulting from `--dangerously-skip-permissions` (acknowledged trade-off for automation)
