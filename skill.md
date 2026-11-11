# TrafficCounter — Skill Index

Project-specific guidance files live under .freebuff/skills/.

## Files

1. **trafficcounter-security.md** — Credentials, camera passwords,
   PostgreSQL access, session data scoping, dependency review.

2. **trafficcounter-ui.md** — SwiftUI layout, interaction, feedback,
   icons, accessibility, camera-sheet behavior.

3. **trafficcounter-verify.md** — Pre-commit checklist: build, Python
   tests, DB checks, functional round-trips, security spot-checks.

4. **session-lifecycle.md** — How a session moves from login to camera
   selection to counting to PostgreSQL persistence to review.

## When to load which

See agents.md for the load-when matrix. In short:

- Auth, DB, or camera-password change -> security
- Any SwiftUI view change -> ui
- About to commit -> verify
- Session start/stop or persistence change -> session-lifecycle

## Related root files

- SYSTEM.md — what the system is, users, roles, layout
- knowledge.md — schema assumptions, known issues, change log
- agents.md — instructions for AI coding assistants
- VERIFICATION.md — midterm verification results
