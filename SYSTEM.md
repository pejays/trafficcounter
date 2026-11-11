# TrafficCounter — System Definition

## 1. What the system is

**TrafficCounter — Road Traffic Monitoring and Session Logging System** is a
macOS desktop application for automated vehicle counting using live RTSP
camera feeds. It combines a native SwiftUI interface with a local Python
computer-vision pipeline and persists per-session traffic data to
PostgreSQL for later review and reporting.

End-to-end workflow:

> Operator logs in -> selects a camera from the sidebar -> the SwiftUI feed
> view hands the RTSP stream to a local Python handler -> the handler
> processes frames and emits vehicle counts -> the operator stops the
> session -> SwiftUI captures session metadata (station, barangay, city,
> directions, times, lanes, median presence) -> DatabaseManager writes the
> row to PostgreSQL -> SessionsView lets the operator review and delete
> past sessions.

Target stack environment: macOS (Xcode + SwiftUI + Swift Package Manager),
Python 3.x for the computer-vision handler, PostgreSQL accessed through
PostgresClientKit and postgres-nio. Authentication uses bcrypt-hashed
credentials.

## 2. Users and roles

Role | Auth backend | Landing page | Capabilities
-----|--------------|--------------|-------------
**Operator** | Local account (bcrypt) | CameraView.swift | Start/stop sessions, view live counts, add/edit/delete own cameras
**Supervisor** | Local account | SessionsView.swift | Review sessions across cameras, delete records, export summaries
**Administrator** | Local account | (future admin panel) | Manage accounts, database configuration, camera registry

Role selection happens at login. Camera credentials are stored in macOS
Keychain; PostgreSQL credentials are loaded from environment variables or a
gitignored config file. Session rows are scoped to the logged-in user
unless the caller holds Supervisor or Administrator role.

## 3. Repository layout

.freebuff/skills/          Project guidance skills for AI coding assistants
TrafficCounter/            SwiftUI app source
TrafficCounter/python/     Python camera handler + tests
TrafficCounter.xcodeproj   Xcode project
SYSTEM.md                  This file
knowledge.md               Living notes and known issues
agents.md                  Instructions for AI assistants
skill.md                   Index of the skill files
VERIFICATION.md            Midterm verification results
