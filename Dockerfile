FROM node:22.13-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    jq \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Install Entire CLI for AI session observability (optional, non-blocking)
RUN curl -fsSL https://entire.sh/install.sh | bash -s 2>/dev/null \
    && mv /root/.local/bin/entire /usr/local/bin/entire \
    || echo "WARNING: Entire CLI install skipped"

# Install Claude Code CLI (pin to major version for stability)
RUN npm install -g @anthropic-ai/claude-code@1

# Create non-root user for security
RUN useradd -m -s /bin/bash ralph
USER ralph
WORKDIR /home/ralph

# Create directory structure with required subdirectories
RUN mkdir -p .claude/debug .claude/todos .claude/statsig workspace prompts && \
    echo '{}' > .claude/remote-settings.json

# Copy scripts and libraries
COPY --chown=ralph:ralph scripts/ scripts/
COPY --chown=ralph:ralph lib/ lib/
COPY --chown=ralph:ralph prompts/ prompts/
COPY --chown=ralph:ralph skills/ skills/

# Make scripts executable
RUN chmod +x scripts/*.sh

# Environment configuration
ENV RALPH_MODE=build \
    RALPH_MAX_ITERATIONS=0 \
    RALPH_MODEL=opus \
    RALPH_OUTPUT_FORMAT=pretty \
    RALPH_PUSH_AFTER_COMMIT=true

# Working directory for mounted projects
WORKDIR /home/ralph/workspace

ENTRYPOINT ["/home/ralph/scripts/entrypoint.sh"]
CMD ["loop"]
