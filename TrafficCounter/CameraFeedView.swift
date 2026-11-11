import SwiftUI
import Combine

struct CameraFeedView: View {
    @ObservedObject var cameraHandler: PythonCameraHandler
    @ObservedObject var sessionCoordinator: AutoSessionCoordinator
    @StateObject private var appState = AppState.shared
    @Binding var selectedCamera: Camera?
    @Binding var activeSchedule: [String: Any]?
    @Binding var scheduledSessionCode: String
    @Binding var shouldMaintainFeed: Bool
    @State private var selectedSchedule: RemoteAutoSession?
    @State private var now = Date()
    let userId: Int
    let userName: String
    private let liveUploadTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let categories = ["Private Car", "Jeepney", "UV", "Bus/Minibus", "Light Truck", "Heavy Truck", "Motorcycle", "Tricycle"]
    private let factorByKey: [String: Double] = ["private car": 1.0, "jeepney": 1.5, "uv": 1.5, "bus-minibus": 2.5, "light truck": 2.0, "heavy truck": 3.0, "motorcycle": 0.5, "tricycle": 0.7]

    private var rawOrderedCounts: [Int] { ["private car", "jeepney", "uv", "bus-minibus", "light truck", "heavy truck", "motorcycle", "tricycle"].map { cameraHandler.vehicleCounts[$0] ?? 0 } }
    // Counts only become visible and eligible for upload during the active
    // session assigned by VehiSight. This prevents stale local values from
    // appearing as live classification outside a scheduled session.
    private var orderedCounts: [Int] { isAssignedActiveCamera ? rawOrderedCounts : Array(repeating: 0, count: categories.count) }
    private var totalPCU: Double { guard isAssignedActiveCamera else { return 0 }; return cameraHandler.vehicleCounts.reduce(0) { $0 + Double($1.value) * (factorByKey[$1.key] ?? 0) } }
    private var capacity: Double { let session = activeCameraSession ?? nextScheduledSession; return max(1, Double(session?.lanes ?? 1) * (session?.baseCapacityPerLane ?? 720)) }
    private var vcRatio: Double { totalPCU / capacity }
    private var los: String { switch vcRatio { case ..<0.20: return "A"; case ..<0.45: return "B"; case ..<0.70: return "C"; case ..<0.85: return "D"; case ...1: return "E"; default: return "F" } }
    private var activeCameraSession: RemoteAutoSession? { guard let id = selectedCamera?.remoteId else { return nil }; return sessionCoordinator.activeSession?.cameraId == id ? sessionCoordinator.activeSession : nil }
    private var isAssignedActiveCamera: Bool { activeCameraSession != nil }
    private var shouldRunFeed: Bool { shouldMaintainFeed || isAssignedActiveCamera }
    private var nextScheduledSession: RemoteAutoSession? { selectedCameraSessions.first { $0.status.lowercased() == "scheduled" && (SessionDateParser.parse($0.startTime) ?? .distantPast) >= now } }
    private var selectedCameraSessions: [RemoteAutoSession] {
        guard let id = selectedCamera?.remoteId else { return [] }
        return sessionCoordinator.sessions.filter { $0.cameraId == id }.sorted { lhs, rhs in
            let rank: (RemoteAutoSession) -> Int = { $0.status == "active" ? 0 : ($0.status == "scheduled" ? 1 : 2) }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            let left = SessionDateParser.parse(lhs.startTime) ?? .distantPast
            let right = SessionDateParser.parse(rhs.startTime) ?? .distantPast
            return rank(lhs) == 1 ? left < right : left > right
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(alignment: .top, spacing: 16) {
                preview
                inspector.frame(width: 360)
            }
        }
        .padding(.bottom, 16)
        .onAppear {
            startFeedIfNeeded()
            synchronizeCountingState(resetForNewSession: true)
        }
        .onChange(of: shouldMaintainFeed) { _, _ in startFeedIfNeeded() }
        .onChange(of: sessionCoordinator.activeSession?.id) { _, _ in
            startFeedIfNeeded()
            synchronizeCountingState(resetForNewSession: true)
        }
        .onReceive(liveUploadTimer) { _ in if isAssignedActiveCamera { Task { await sessionCoordinator.submitCounts(orderedCounts) } } }
        .onReceive(clock) { now = $0 }
        .onDisappear { cameraHandler.stopCamera() }
        .sheet(item: $selectedSchedule) { session in
            CameraScheduleDetailView(session: session)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCamera?.name ?? "Camera console").font(.title.bold())
                Text(isAssignedActiveCamera ? "Automatic session is active - counts are syncing every 2 seconds" : nextScheduledSession.map { "Next automatic session \(countdown(to: $0))" } ?? "Live preview - waiting for a website schedule assigned to this camera").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            connectionBadge
            Button(action: toggleCamera) { Label(appState.isCameraEnabled ? "Disable" : "Enable", systemImage: appState.isCameraEnabled ? "video.slash" : "video") }.buttonStyle(.bordered)
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    private var connectionBadge: some View {
        Label(cameraHandler.isConnected ? "Camera connected" : "Connecting", systemImage: cameraHandler.isConnected ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath")
            .font(.subheadline.weight(.medium)).foregroundColor(cameraHandler.isConnected ? .green : .orange)
            .padding(.horizontal, 10).padding(.vertical, 7).background(.thinMaterial, in: Capsule())
    }

    private var preview: some View {
        ZStack {
            Color.black
            if appState.isCameraEnabled, let frame = cameraHandler.currentFrame { Image(nsImage: frame).resizable().aspectRatio(contentMode: .fit) }
            else if appState.isCameraEnabled { VStack(spacing: 12) { ProgressView().controlSize(.large); Text("Connecting to the RTSP stream").foregroundColor(.white); Text("The local detection service is preparing the live feed.").foregroundColor(.white.opacity(0.65)).font(.caption) } }
            else { ContentUnavailableView("Camera disabled", systemImage: "video.slash", description: Text("Enable the camera to resume the live preview.")).foregroundColor(.white) }
        }
        // Keep the actual video surface in standard landscape format. A frame
        // with another ratio is fitted inside this area, never cropped or zoomed.
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.10), lineWidth: 1))
        .padding(.leading, 16)
        .padding(.vertical, 4)
        .frame(maxHeight: .infinity)
    }

    private var inspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sessionCard
                analyticsCard
                classificationCard
                schedulesCard
                if let error = sessionCoordinator.lastError { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.orange) }
                if let error = cameraHandler.lastError { Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundColor(.orange) }
            }.padding(.vertical, 4).padding(.trailing, 16)
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Label(isAssignedActiveCamera ? "COUNTING NOW" : (nextScheduledSession == nil ? "SESSION STATUS" : "UP NEXT"), systemImage: isAssignedActiveCamera ? "record.circle.fill" : "clock").font(.caption.weight(.bold)).foregroundColor(isAssignedActiveCamera ? .red : (nextScheduledSession == nil ? .secondary : .orange)); Spacer(); Text(isAssignedActiveCamera ? "LIVE" : (nextScheduledSession == nil ? "STANDBY" : countdown(to: nextScheduledSession!))).font(.caption.bold().monospacedDigit()).foregroundColor(isAssignedActiveCamera ? .red : (nextScheduledSession == nil ? .secondary : .orange)) }
            if let session = activeCameraSession { Text(session.sessionCode).font(.headline); Text("\(session.roadName ?? session.location) - \(session.direction ?? "Direction not set")").font(.caption).foregroundColor(.secondary); Text("Capacity: \(Int(capacity)) PCU/hr").font(.caption).foregroundColor(.secondary) }
            else if let session = nextScheduledSession { Text(session.schedule?.scheduleName ?? session.sessionCode).font(.headline); Text("\(session.roadName ?? session.location) - \(session.direction ?? "Direction not set")").font(.caption).foregroundColor(.secondary); Text("Starts \(formattedStart(session)) • Capacity: \(Int(capacity)) PCU/hr").font(.caption).foregroundColor(.secondary) }
            else { Text("No active session for this camera").font(.subheadline); Text("Sessions created on the VehiSight website appear automatically.").font(.caption).foregroundColor(.secondary) }
        }.padding(14).background((isAssignedActiveCamera ? Color.red : (nextScheduledSession == nil ? Color.gray : Color.orange)).opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
    }

    private var analyticsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) { metric("PCU", String(format: "%.1f", totalPCU), "car.2.fill", .blue); Divider().frame(height: 38); metric("V/C", String(format: "%.2f", vcRatio), "chart.line.uptrend.xyaxis", .purple) }
            Divider().padding(.horizontal, 12)
            HStack(spacing: 0) { metric("LOS", los, "gauge.with.dots.needle.67percent", losColor); Divider().frame(height: 38); metric("Vehicles", "\(orderedCounts.reduce(0, +))", "car.fill", .teal) }
        }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var classificationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isAssignedActiveCamera ? "LIVE CLASSIFICATION" : "LIVE CLASSIFICATION • WAITING FOR ACTIVE SESSION").font(.caption.weight(.bold)).foregroundColor(.secondary)
            ForEach(Array(categories.enumerated()), id: \.offset) { index, name in HStack { Text(name).font(.subheadline); Spacer(); Text("\(orderedCounts[index])").font(.subheadline.bold().monospacedDigit()).foregroundColor(.secondary) }.padding(.vertical, 2) }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var schedulesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SCHEDULES FOR THIS CAMERA").font(.caption.weight(.bold)).foregroundColor(.secondary)
            if selectedCameraSessions.isEmpty { Text("No website schedules assigned to this camera.").font(.caption).foregroundColor(.secondary) }
            else { ForEach(selectedCameraSessions.prefix(3)) { schedule in Button { selectedSchedule = schedule } label: { ScheduleMiniCard(session: schedule, now: now) }.buttonStyle(.plain).accessibilityLabel("View details for \(schedule.schedule?.scheduleName ?? schedule.sessionCode)") } }
        }.padding(14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View { HStack(spacing: 8) { Image(systemName: icon).foregroundColor(color); VStack(alignment: .leading, spacing: 1) { Text(value).font(.headline.monospacedDigit()); Text(title).font(.caption).foregroundColor(.secondary) }; Spacer() }.padding(12).frame(maxWidth: .infinity) }
    private var losColor: Color { ["A": .green, "B": .mint, "C": .yellow, "D": .orange, "E": .red, "F": .purple][los] ?? .secondary }
    private func countdown(to session: RemoteAutoSession) -> String { guard let start = SessionDateParser.parse(session.startTime) else { return "Scheduled" }; let seconds = max(0, Int(start.timeIntervalSince(now))); return seconds == 0 ? "Starting now" : String(format: "Starts in %02d:%02d", seconds / 60, seconds % 60) }
    private func formattedStart(_ session: RemoteAutoSession) -> String { guard let date = SessionDateParser.parse(session.startTime) else { return session.startTime }; return date.formatted(date: .omitted, time: .shortened) }
    private func toggleCamera() { guard var camera = selectedCamera else { return }; if appState.isCameraEnabled { cameraHandler.stopCamera(); appState.isCameraEnabled = false; camera.isEnabled = false } else { cameraHandler.startCamera(); appState.isCameraEnabled = true; camera.isEnabled = true }; NotificationCenter.default.post(name: NSNotification.Name("UpdateCameraState"), object: camera) }
    private func startFeedIfNeeded() {
        guard shouldRunFeed, let camera = selectedCamera else { return }
        cameraHandler.saveCameraToUserDefaults(name: camera.name, ip: camera.ip, username: camera.username, password: camera.password)
        cameraHandler.startCamera()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard let currentCamera = selectedCamera else { return }
            let savedPosition = UserDefaults.standard.double(forKey: "line_position_\(currentCamera.ip)")
            cameraHandler.updateCountingLine(position: savedPosition == 0 ? 0.7 : savedPosition)
        }
    }
    private func synchronizeCountingState(resetForNewSession: Bool) { if isAssignedActiveCamera { appState.isCameraEnabled = true; if resetForNewSession { cameraHandler.resetCounts() }; cameraHandler.toggleCounting(isActive: true) } else { cameraHandler.toggleCounting(isActive: false) } }
}

@MainActor private struct ScheduleMiniCard: View {
    let session: RemoteAutoSession
    let now: Date
    private var start: Date? { SessionDateParser.parse(session.startTime) }
    private var statusColor: Color { ["active": .green, "scheduled": .orange, "ended": .purple][session.status.lowercased()] ?? .secondary }
    private var subtitle: String {
        guard session.status.lowercased() == "scheduled", let start else { return start?.formatted(date: .abbreviated, time: .shortened) ?? session.startTime }
        let seconds = max(0, Int(start.timeIntervalSince(now)))
        return seconds == 0 ? "Starting now" : String(format: "Starts in %02d:%02d", seconds / 60, seconds % 60)
    }
    var body: some View { HStack { VStack(alignment: .leading, spacing: 3) { Text(session.schedule?.scheduleName ?? session.sessionCode).font(.caption.weight(.semibold)); Text(subtitle).font(.caption2.monospacedDigit()).foregroundColor(session.status.lowercased() == "scheduled" ? .orange : .secondary) }; Spacer(); Text(session.status.uppercased()).font(.caption2.bold()).foregroundColor(statusColor); Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundColor(.secondary) }.padding(9).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 8)).contentShape(RoundedRectangle(cornerRadius: 8)) }
}

@MainActor private struct CameraScheduleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let session: RemoteAutoSession

    private var statusColor: Color { ["active": .green, "ended": .purple, "scheduled": .orange][session.status.lowercased()] ?? .secondary }
    private var detail: RemoteAutoSessionDetail? { session.detail }
    private var timeWindow: String {
        let start = SessionDateParser.parse(session.startTime)
        let end = session.endTime.flatMap(SessionDateParser.parse)
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Asia/Manila"); formatter.dateFormat = "EEE, MMM d, yyyy • h:mm a"
        guard let start else { return session.startTime }
        return "\(formatter.string(from: start)) - \(end.map { formatter.string(from: $0) } ?? "Open")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) { Text(session.schedule?.scheduleName ?? "Automatic session").font(.title2.bold()); Text(session.sessionCode).font(.caption.monospaced()).foregroundColor(.secondary) }
                Spacer()
                Text(session.status.uppercased()).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6).background(statusColor.opacity(0.16), in: Capsule()).foregroundColor(statusColor)
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }.buttonStyle(.plain).foregroundColor(.secondary).accessibilityLabel("Close session details")
            }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
                GridRow { field("Road", session.roadName ?? session.location, "road.lanes"); field("Camera", session.cameraName, "video.fill") }
                GridRow { field("Location", [session.barangay, session.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "), "mappin.and.ellipse"); field("Direction", session.direction ?? "Not specified", "arrow.left.arrow.right") }
                GridRow { field("Schedule", timeWindow, "clock"); field("Road setup", "\(session.lanes ?? 1) lane(s)\(session.hasMedian == true ? ", median present" : "")", "signpost.right") }
            }
            if let detail {
                Divider()
                Text("RECORDED RESULTS").font(.caption.weight(.bold)).foregroundColor(.secondary)
                HStack(spacing: 12) { result("Vehicles", "\(detail.counts?.reduce(0, +) ?? 0)"); result("PCU", String(format: "%.1f", detail.totalPcu ?? 0)); result("V/C", String(format: "%.2f", detail.vcRatio ?? 0)); result("LOS", detail.los ?? "-") }
            }
        }
        .padding(24).frame(width: 600)
    }

    private func field(_ title: String, _ value: String, _ icon: String) -> some View { VStack(alignment: .leading, spacing: 4) { Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary); Text(value.isEmpty ? "Not specified" : value).font(.subheadline).lineLimit(2) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func result(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 3) { Text(value).font(.headline.monospacedDigit()); Text(title).font(.caption).foregroundColor(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)) }
}
