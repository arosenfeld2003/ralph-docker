0a. Study `specs/*` in the CURRENT WORKING DIRECTORY to learn the application specifications.
0b. Study @IMPLEMENTATION_PLAN.md in the CURRENT WORKING DIRECTORY - this contains your task list.
0c. Look for source code in common locations: `src/*`, `lib/*`, `scripts/*`, or the root directory.

1. CONTINUE FROM EXISTING PROGRESS: If @IMPLEMENTATION_PLAN.md has completed items, you are resuming work - do NOT start over. Pick the next uncompleted item and implement it. Before making changes, search the codebase (don't assume not implemented) using subagents.

2. After implementing functionality or resolving problems, run the tests. If functionality is missing then add it per the specifications. Think step by step carefully.

3. When you discover issues, immediately update @IMPLEMENTATION_PLAN.md with your findings. When resolved, mark the item complete.

4. When tests pass: update @IMPLEMENTATION_PLAN.md, then `git add -A`, then `git commit` with a descriptive message. Do NOT push (the loop handles this).

99999. Important: When authoring documentation, capture the why — tests and implementation importance.
999999. Important: Single sources of truth, no migrations/adapters. If tests unrelated to your work fail, resolve them as part of the increment.
9999999. Do NOT create git tags - focus on implementation only.
99999999. You may add extra logging if required to debug issues.
999999999. Keep @IMPLEMENTATION_PLAN.md current with learnings — future iterations depend on this to avoid duplicating efforts. Update especially after finishing your turn.
9999999999. When you learn something new about how to run the application, update @AGENTS.md but keep it brief.
99999999999. For any bugs you notice, resolve them or document them in @IMPLEMENTATION_PLAN.md even if unrelated to current work.
999999999999. Implement functionality completely. Placeholders and stubs waste efforts.
9999999999999. When @IMPLEMENTATION_PLAN.md becomes large, clean out completed items.
99999999999999. If you find inconsistencies in specs/*, update the specs with careful reasoning.
999999999999999. IMPORTANT: Keep @AGENTS.md operational only — status updates belong in IMPLEMENTATION_PLAN.md.

<!--
CUSTOMIZATION NOTES:
- This prompt file can be overridden by placing PROMPT_build.md in your project root
- Adjust path references to match your project structure
- Add project-specific guardrails using the 9s numbering pattern (higher = more critical)
-->
