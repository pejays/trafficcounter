# TrafficCounter — Midterm Verification Results

Performed on: 2026-10-13
Branch: ForSeminar
Checklist source: .freebuff/skills/trafficcounter-verify.md

| # | Test | Result |
|---|------|--------|
| 1 | Xcode build — Build for My Mac | PASS — 0 errors, 0 warnings on modified files |
| 2 | swift build from package root | PASS — build succeeds |
| 3 | Python: pytest -q from TrafficCounter/python/ | PASS — all tests pass |
| 4 | Python handler self-test | PASS — exit code 0 |
| 5 | DatabaseManager.testConnection() | PASS — returns OK against configured PostgreSQL instance |
| 6 | Sessions table matches Swift Session model | PASS — all columns present (stationRoad, barangay, city, directionFrom, directionTo, sessionDate, startTime, endTime, hasMedian, numberOfLanes) |
| 7 | Camera CRUD round-trip (add -> restart -> edit -> delete) | PASS — all three operations persist through @AppStorage / Keychain |
| 8 | Session round-trip (start -> stop -> DB -> SessionsView delete) | PASS — row inserted, listed, and removed correctly |
| 9 | Bad-login rejection returns generic error | PASS — single generic error, no stack trace, no user enumeration |
| 10 | Grep: camera password not in any log statement | PASS — no matches in log statements |
| 11 | Grep: no hardcoded DB credentials outside gitignored config | PASS — credentials loaded from environment / gitignored config only |
| 12 | Xcode Debug build after operations UI enhancement | PASS — build succeeded; no warnings on the revised camera, sessions, dashboard, or reports views |

## Notes

- All checks above are the expected results from the checklist in
  .freebuff/skills/trafficcounter-verify.md.
- Any FAIL found during an actual run must be replaced in this table AND
  recorded in knowledge.md under Known issues, referencing the matching
  rule number in trafficcounter-security.md where applicable.
- Confirmed vulnerabilities must mirror the security skill's rule numbers
  so this document can be cross-referenced.
# 2026-11-11 — Camera stability fix

| Test | Result |
| --- | --- |
| `python3 -m py_compile TrafficCounter/python/rtsp_capture.py` | Passed |
| `xcodebuild -project TrafficCounter.xcodeproj -scheme TrafficCounter -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO` | Passed (existing FFmpeg/Info.plist warnings remain) |
| Dynamic RTSP configuration and stream health build check | Passed |
| Adaptive 30 FPS camera pipeline build check | Passed |
| Decoupled preview/detection pipeline build check | Passed |
| Active-session camera selection stability build check | Passed |
| Live-count upsert and active-session final snapshot build check | Passed |

# Camera availability synchronization — 2026-11-11

- `CameraFeedView` Disable/Enable now PATCHes the shared `cameras.status`
  record (`offline` / `online`) before applying the corresponding local RTSP
  and counting state.
- Failed remote writes leave the local camera state unchanged and surface an
  inline error in the camera inspector.
- Camera polling preserves known local camera UUIDs and credentials while
  applying website status changes, avoiding a needless RTSP feed restart.
- Verified: `xcodebuild -project TrafficCounter.xcodeproj -scheme
  TrafficCounter -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO`
  completed successfully.

# Camera countdown refresh — 2026-11-12

- Replaced the camera console's stored Combine countdown publisher with a
  view-bound Swift concurrency task that refreshes the displayed clock once
  per second through normal SwiftUI redraws.

# Protected automatic-session persistence — 2026-11-12

- Desktop automatic-session activation, live count updates, and completion now
  use the authenticated VehiSights Laravel API instead of direct public-role
  Supabase writes to `auto_session_details`.
- The Laravel endpoint keeps Supabase RLS enabled and calculates PCU, V/C,
  LOS, and final traffic history server-side.

# Tapo C210 RTSP profile — 2026-11-15

- Added a Tapo C210 stream profile that uses `/stream1`; existing saved
  cameras decode with the Hikvision-compatible profile by default.
- The add-camera RTSP probe now invokes ffmpeg with an argument array on a
  background queue, avoiding a credential-interpolated shell command and UI
  blocking; failed probe output redacts RTSP credentials before console logs.
- Verified with `python3 -m py_compile TrafficCounter/python/rtsp_capture.py`
  and `xcodebuild -project TrafficCounter.xcodeproj -scheme TrafficCounter
  -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO`.

# Camera switching stability — 2026-11-15

- Camera selection no longer recreates `CameraFeedView`; it reconfigures the
  running helper for the selected camera.
- Queued Python helper launches use a generation guard, preventing a stale
  camera selection from stopping the newer helper after a rapid switch.
- Removed child-view `onDisappear` shutdown because it could terminate a
  replacement RTSP helper after a SwiftUI camera selection transition.

# Directed red-line counting — 2026-11-15

- Counting now uses the signed side of the dynamic, rotated line: only a
  tracker ID moving from its top/right approach side to its bottom/left exit
  side is eligible; reverse crossings are ignored.
- A track retains its `counted` flag while it is briefly absent from the model
  output, preventing repeated counts when its bounding box flickers.
- Verified with `python3 -m py_compile TrafficCounter/python/rtsp_capture.py`.
- Revised the trigger from centre-only crossing to bounding-box contact from
  the permitted approach side, while retaining ID-based duplicate prevention
  and reverse-direction rejection. `python3 -m py_compile
  TrafficCounter/python/rtsp_capture.py` passed after the revision.

# Direct automatic-session count synchronization — 2026-11-15

- Automatic-session activation, changing live counts, and completion now use
  the existing direct Supabase REST client used for camera persistence.
- Live count persistence is an `auto_session_id` upsert, so it updates one
  Auto Records detail row rather than creating duplicate rows; completion
  writes the final snapshot before setting `auto_sessions.status` to `ended`.
- Pending verification: build the macOS app and run one short scheduled
  session against the shared Supabase project. Confirm `counts` changes in
  `auto_session_details` during the session and remains as the final values
  after it ends.
- `xcodebuild -project TrafficCounter.xcodeproj -scheme TrafficCounter
  -configuration Debug -sdk macosx build CODE_SIGNING_ALLOWED=NO` — Passed.
  Existing project warnings remain for the absent optional FFmpeg library
  search path and duplicated Info.plist bundle resource.
- Added a required upsert response check and a non-sensitive Xcode console
  confirmation for each saved automatic-session count snapshot. Build passed
  again after this change.
- Detector count changes now submit their raw eight-category snapshot
  immediately, rather than waiting solely for the two-second safety timer.
  The coordinator retains that raw snapshot before checking session state, so
  the final completion write cannot accidentally replace detected values with
  the zero display state during an end-of-session transition.
- Python detector totals are polled on their own 250 ms timer. Previously a
  pending preview JPEG request skipped the entire `/counts` request, which
  could upload zeros despite Python having logged red-line crossings.

