# TrafficCounter — Verification Skill

Run this checklist before every commit on ForSeminar.

## Build

1. Open TrafficCounter.xcodeproj in Xcode and build for My Mac.
   - Must be zero errors, zero warnings on new or modified files.
2. Run swift build from the package root if the project is
   SwiftPM-compatible.

## Python handler

3. From TrafficCounter/python/, run pytest -q.
   - All tests must pass.
4. Smoke test the handler:
   python -m trafficcounter_handler --self-test
   - Must exit 0.

## Database

5. Call DatabaseManager.testConnection() from a debug build.
   - Must return OK against the configured PostgreSQL instance.
6. Verify the sessions table matches the current Swift model
   (stationRoad, barangay, city, directionFrom, directionTo,
   sessionDate, startTime, endTime, hasMedian, numberOfLanes).
   - Any drift must be captured in knowledge.md.

## Functional

7. Camera CRUD round-trip:
   add camera -> restart app -> edit camera -> delete camera.
   - All three steps persist correctly through @AppStorage / Keychain.
8. Session round-trip:
   start session -> stop session -> confirm row in PostgreSQL ->
   open SessionsView.swift -> delete row -> confirm removal in DB.
9. Bad-login test:
   wrong email + wrong password in LoginView.swift.
   - Must return a single generic error with no stack trace.

## Security spot-checks

10. Grep for the camera password field name across the codebase.
    - Must not appear in any log statement.
11. Grep for password= and connection strings.
    - Must not appear hardcoded outside of .gitignore'd config files.

## Reporting

Log results in VERIFICATION.md at repo root using the standard table
format (Test | Result).
