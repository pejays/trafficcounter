# TrafficCounter — Knowledge Base

Living notes about the system. Update whenever a fact changes.

## Database schema assumptions

- Sessions table columns (must stay in sync with Session Swift model):
  stationRoad, barangay, city, directionFrom, directionTo,
  sessionDate, startTime, endTime, hasMedian, numberOfLanes.
- hasMedian defaults to false.
- numberOfLanes is a positive integer.
- endTime >= startTime is enforced at the app layer.
- PostgreSQL is accessed via PostgresClientKit; queries must be
  parameterized.

## Camera handling

- Camera configs persist via @AppStorage under key "savedCameras".
- Passwords are intended to live in macOS Keychain, keyed by camera UUID.
- Python handler binds only to 127.0.0.1.
- RTSP capture is handled by TrafficCounter/python/rtsp_capture.py.

## Python handler

- Entry point: TrafficCounter/python/rtsp_capture.py.
- Database smoke test: TrafficCounter/python/test_db.py.
- Python version: 3.x (see project README once added).

## Known issues

1. Camera passwords may still be held in @State in CameraView.swift for
   the add-camera sheet. Tracked under trafficcounter-security.md rule 1.
   Target: migrate to Keychain before final defense.
2. DatabaseManager credentials currently come from a local config; confirm
   that no connection string is hardcoded before every push.

## Verification reminders

- Before each commit on ForSeminar: run through
  .freebuff/skills/trafficcounter-verify.md.
- Log results in VERIFICATION.md.

## Change log

- 2026-10-13: Initial knowledge base created alongside skill files.
