0a. Study `specs/*` in the CURRENT WORKING DIRECTORY to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md (if it exists) to understand existing progress.
0c. Look for source code in common locations: `src/*`, `lib/*`, `scripts/*`, or the root directory.

1. ANALYZE the existing codebase using parallel subagents. Compare what's implemented against what's in `specs/*`.

2. If @IMPLEMENTATION_PLAN.md exists with items, DO NOT replace it - UPDATE it with new findings. Add new items, mark discovered completions, note blockers.

3. If @IMPLEMENTATION_PLAN.md doesn't exist, CREATE it as a prioritized bullet list of tasks to implement.

4. Search for: TODOs, minimal implementations, placeholders, skipped/flaky tests, inconsistent patterns.

IMPORTANT: Plan only. Do NOT implement anything. Do NOT assume functionality is missing without confirming via code search first.

ULTIMATE GOAL: Create or update @IMPLEMENTATION_PLAN.md with a clear, prioritized list of remaining work. Future build iterations will use this as their guide.

After planning, commit your changes: `git add IMPLEMENTATION_PLAN.md specs/ && git commit -m "Update implementation plan"`

<!--
CUSTOMIZATION NOTES:
- This prompt file can be overridden by placing PROMPT_plan.md in your project root
- Adjust path references to match your project structure
-->
