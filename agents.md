# TrafficCounter — Agent Instructions

Instructions for any AI coding assistant (Claude, Cursor, Copilot, etc.)
working on this repository.

## Before you write code

1. Read SYSTEM.md — it defines what the project is and who uses it.
2. Read knowledge.md — it lists schema assumptions and known issues.
3. Load the relevant skill file(s) below based on the change you're making.

## Skill files

All live under .freebuff/skills/. Load only what you need.

| Skill file | Load when |
|------------|-----------|
| trafficcounter-security.md | Touching login, credentials, camera passwords, PostgreSQL connection, session data, or any network I/O |
| trafficcounter-ui.md | Adding or modifying any SwiftUI view under TrafficCounter/ |
| trafficcounter-verify.md | Before committing — run through the checklist |
| session-lifecycle.md | Working on session start/stop, metadata capture, or session persistence/review |

## Ground rules

- Do not introduce a new framework, package, or Python dependency without
  flagging it first.
- Preserve the existing NavigationSplitView + CameraListSidebar layout
  unless the task explicitly changes the navigation model.
- All SQL must be parameterized.
- All camera passwords must go through Keychain, never @State or
  @AppStorage.
- Never block the main thread from camera or database work.
- If a change touches more than one of {auth, DB, camera, UI}, load
  multiple skill files and note which rules apply.
- Update knowledge.md whenever you discover or resolve a schema
  assumption or known issue.
- Log verification results in VERIFICATION.md before every commit to
  ForSeminar.

## What not to do

- Do not commit xcuserdata/, DerivedData/, .DS_Store, or any local config
  file containing credentials.
- Do not re-enable plaintext password comparisons in login code.
- Do not bind the Python handler to anything other than 127.0.0.1.
