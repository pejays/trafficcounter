# TrafficCounter — UI Skill

Applies to any change to SwiftUI views under TrafficCounter/TrafficCounter/.

## Rules

1. **Layout**
   - New top-level screens use NavigationSplitView with
     CameraListSidebar.swift as the sidebar.
   - Follow existing padding and spacing tokens; do not introduce new
     magic numbers.
   - Every list row and control must render correctly in both light and
     dark mode.

2. **Interaction**
   - Every network or camera action must expose a loading state using the
     isTestingConnection / isConnectionSuccessful pattern already used
     in CameraView.swift.
   - Long-running actions must be cancellable.
   - Never block the main thread; camera and DB work runs off-main.

3. **Feedback**
   - Errors surface via .alert or an inline banner — never silent failure.
   - Success confirmations are non-modal (toast or inline checkmark).
   - Destructive actions (delete camera, delete session) require a
     confirmation dialog.

4. **Icons and naming**
   - Use SF Symbols, not custom image assets, unless an SF Symbol is missing.
   - View names follow <Feature>View.swift; subcomponents follow
     <Feature><Part>.swift.

5. **Accessibility**
   - All icon-only buttons carry an .accessibilityLabel.
   - Color is never the only signal for state (pair with text or icon).

6. **Camera-specific**
   - The add-camera sheet must validate IP format before enabling Save.
   - Camera list sorting is stable (by name, then by UUID).
