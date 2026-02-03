<!-- TEMPLATE NOTE: This is a template prompt. Update src/* paths below to match YOUR project structure -->
0a. Study `specs/*` with parallel subagents to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if present) to understand the plan so far.
0c. Study `src/lib/*` with parallel subagents to understand shared utilities & components. <!-- UPDATE PATH -->
0d. For reference, the application source code is in `src/*`. <!-- CHANGE THIS PATH TO YOUR SOURCE LOCATION -->

1. Study @IMPLEMENTATION_PLAN.md (if present; it may be incorrect) and use parallel subagents to study existing source code in `src/*` <!-- UPDATE PATH --> and compare it against `specs/*`. Analyze findings, prioritize tasks, and create/update @IMPLEMENTATION_PLAN.md as a bullet point list sorted in priority of items yet to be implemented. Think step by step carefully. Consider searching for TODO, minimal implementations, placeholders, skipped/flaky tests, and inconsistent patterns. Study @IMPLEMENTATION_PLAN.md to determine starting point for research and keep it up to date with items considered complete/incomplete using subagents.

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing; confirm with code search first. Treat `src/lib` as the project's standard library for shared utilities and components. Prefer consolidated, idiomatic implementations there over ad-hoc copies.

ULTIMATE GOAL: We want to achieve [YOUR PROJECT GOAL HERE]. Consider missing elements and plan accordingly. If an element is missing, search first to confirm it doesn't exist, then if needed author the specification at specs/FILENAME.md. If you create a new element then document the plan to implement it in @IMPLEMENTATION_PLAN.md using a subagent.

<!--
TEMPLATE CUSTOMIZATION REQUIRED:
- **CRITICAL**: Replace [YOUR PROJECT GOAL HERE] with your actual project goal
- **IMPORTANT**: Update ALL path references (src/*, src/lib/*) to match YOUR actual project structure
- The src/* paths are PLACEHOLDERS - you must change them to your source code location
- Add project-specific constraints as needed
- Works with Claude Code (cloud) and local models via Ollama
- See TEMPLATE_USAGE.md for detailed setup instructions
-->
