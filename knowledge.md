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

## Automatic-session integration

- `AutoSessionCoordinator` is the desktop's existing real-time bridge for
  website-created automatic sessions. It refreshes the shared session data,
  selects the assigned camera, enables counting only during the active window,
  uploads ordered live counts, and completes the session at its end time.
- Camera, Sessions, Dashboard, and Reports views consume this coordinator as
  read-only UI state; these views must not duplicate its activation, upload,
  or completion operations.

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
- 2026-11-10: Expanded the live camera console, session center, dashboard,
  and reporting overview around the existing AutoSessionCoordinator without
  changing automatic-session lifecycle behavior.
# Camera stability note (2026-11-11)

- The desktop camera helper must launch `TrafficCounter/python/rtsp_capture.py`
  from this repository, not the legacy Documents/TrafficCounter copy.
- The handler is intentionally limited to one traffic model, 1280x720 input,
  and 10 FPS. It is bound to `127.0.0.1:8888`; the Swift client prevents
  overlapping frame/count requests.
- RTSP source settings are supplied by the selected desktop camera rather than
  a hard-coded private IP. A private camera address still requires a route from
  the active network (same LAN, VPN, or router/NVR configuration).
- The video helper targets 30 FPS, but dynamically lowers its production rate
  (never below 10 FPS) if sustained detector frame time or CPU load indicates
  the Mac cannot maintain that rate.
- Camera preview and detection use separate loops: the native 2560×1440/24 FPS
  stream is rendered as a 1920×1080 local preview, while detection consumes
  only the newest 1280×720 frame and never delays the preview.
- Camera selection must remain stable during Supabase polling. Replacing a
  semantically identical `Camera` value creates a new UUID and causes SwiftUI
  to recreate `CameraFeedView`, which stops and restarts the RTSP helper.
- Camera configurations carry a stream profile. Existing cameras retain the
  Hikvision-compatible `/Streaming/Channels/101` path, while the Tapo C210
  profile uses its local RTSP high-quality `/stream1` path. The selected
  profile is passed from Swift to the loopback-only Python helper.
- The RTSP connection probe redacts credentials before writing ffmpeg errors
  to the Xcode console.
- Switching the selected camera keeps the `CameraFeedView` mounted and sends
  the new configuration to the existing Python helper. Queued helper launches
  are generation-guarded so an old camera selection cannot kill a replacement
  process.
- `CameraFeedView` must never stop the shared RTSP helper in `onDisappear`.
  SwiftUI may remove the old view during a camera selection change, after the
  replacement helper has started. The helper remains active across camera and
  app-tab changes and stops only through an explicit Disable action.
- The counting region is the directed half-plane above/right of the dynamic
  red line. A tracked ID counts once when its bounding box reaches that line
  from the approach side (or its centre skips past the line between detector
  frames); reverse-side entries never count. ID matching spans short missing
  boxes and brief class-label flicker, and the `counted` flag is retained with
  the ID while it is temporarily lost.
- Live automatic-session counts use an `auto_session_id` conflict upsert. A
  final desktop snapshot is written when an active session transitions out of
  the active window, including when the website closes it first.
- Camera Enable/Disable is stored as `cameras.status` (`online`/`offline`) so
  the desktop and VehiSights website reflect the same availability state.
- Camera schedule and active-session countdowns use a view-bound one-second
  task rather than a recreated Combine publisher, so time remaining continues
  to update while the camera console redraws.
- Automatic-session activation, live count snapshots, and completion use the
  same direct Supabase REST connection as camera save/update operations. The
  desktop upserts one `auto_session_details` row per `auto_session_id` every
  time the counter changes (normally every two seconds), then saves one final
  snapshot before marking the session ended. This avoids dependence on a
  separate ngrok/Laravel connection and lets the website read the same shared
  rows in real time.
- The desktop treats an automatic-session count upload as successful only when
  Supabase returns the upserted `auto_session_details` row for that exact
  session. The Xcode console logs the confirmed session code and eight
  category counts; absence of this confirmation means no result was saved.
- Python `/counts` changes are bridged to the automatic-session coordinator
  immediately. The two-second timer is only a backup; it is not the source of
  truth. Raw counts are retained before a session-state check so a session
  ending at the same moment as a detector update still completes with the
  detected values instead of an inactive-view zero array.
- Preview frame fetching and detector-count fetching are independent. The
  local helper's `/counts` endpoint is polled every 250 ms, so a delayed
  RTSP-to-JPEG preview response cannot starve automatic-session persistence.

