# TrafficCounter — Security Skill

Applies to any change involving: login, credentials, camera passwords,
PostgreSQL connection, session data, or any network I/O.

## Rules

1. **Camera passwords**
   - Never keep a camera password in plain @State or @AppStorage.
   - Store in macOS Keychain via SecItem* APIs, keyed by camera UUID.
   - Never log camera passwords, even in debug builds.

2. **PostgreSQL credentials**
   - Must be loaded from a config file or environment variable.
   - Never hardcode host, user, password, or database name in
     DatabaseManager.swift or anywhere else.
   - Config files containing credentials must be .gitignore'd.

3. **SQL queries**
   - All statements must be parameterized (PostgresClientKit placeholders).
   - No string concatenation to build SQL.
   - Reject any user input that isn't used as a bound parameter.

4. **Python camera handler**
   - Bind only to 127.0.0.1, never 0.0.0.0.
   - Reject frames larger than a defined max size.
   - Never shell out with interpolated strings; use argument arrays.

5. **Authentication**
   - LoginView.swift must show the same generic error for bad user and
     bad password (no user-enumeration).
   - Session tokens or user IDs must not be persisted in plain text.
   - Logout must clear all in-memory state.

6. **Session data**
   - Session rows (station, barangay, city, directions, times, lanes) are
     user-owned; queries must filter by the logged-in user unless the
     caller is an Admin role.

7. **Dependencies**
   - Any new Swift Package or Python dependency must be reviewed for
     maintenance status and license before being added.
