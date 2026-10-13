# TrafficCounter — Session Lifecycle

Explains how a traffic-counting session moves from user action through
database persistence.

## Stages

1. **Login**
   - LoginView.swift authenticates the user and establishes the
     in-memory user ID + role.

2. **Camera selection**
   - User picks a camera from CameraListSidebar.swift.
   - Camera config (IP, username, password reference) is loaded from
     Keychain / @AppStorage.

3. **Feed start**
   - CameraView.swift initializes the feed by calling
     PythonCameraHandler.swift.
   - The handler launches (or connects to) the local Python process on
     127.0.0.1.

4. **Counting**
   - Python processes frames and emits counts back to Swift.
   - Swift maintains live counters and preview state.

5. **Session metadata capture**
   - Before stopping, Swift records:
     stationRoad, barangay, city, directionFrom, directionTo,
     sessionDate, startTime, endTime, hasMedian,
     numberOfLanes.

6. **Persistence**
   - DatabaseManager.swift writes a session row to PostgreSQL using a
     parameterized INSERT.
   - On success, the in-memory session is finalized and the feed closes.

7. **Review**
   - SessionsView.swift lists past sessions for the logged-in user.
   - Deleting a session removes the row from PostgreSQL and refreshes
     the list.

## Invariants

- A session must never be written without a sessionDate and
  startTime.
- endTime must be >= startTime.
- numberOfLanes is a positive integer.
- hasMedian is a boolean, defaulting to false.
