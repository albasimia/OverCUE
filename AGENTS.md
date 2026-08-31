<!-- AAL:BEGIN -->
<!-- AAL entry schema: 2 -->
# AAL Project Instructions

This repository uses albasimia-ai-logos.

Before starting work:

1. Read `.ai/project.md`.
2. Read `.ai/next.md`.
3. Determine the primary work mode from the current user request.
4. Run `aal context build --mode <mode>`.
5. If deliberation is explicitly requested for that work, add `--with deliberation`. Use `--mode deliberation` only when deliberation itself is the task.
6. Read the generated context before editing files.

Supported modes:

- implementation
- review
- reporting
- exploration
- conversation
- deliberation

Supported overlays:

- deliberation

Rules:

- The current user instruction has the highest priority.
- Do not edit `.aal/logos/` directly.
- Do not activate deliberation unless it is explicitly requested.
- Do not silently ignore a failed context build.
<!-- AAL:END -->
