import SwiftUI
import Combine

struct ContentView: View {
    @StateObject private var sessionCoordinator = AutoSessionCoordinator()
    @State private var selectedTab = "Dashboard"
    @State private var activeSchedule: [String: Any]? = nil
    @State private var scheduledSessionCode = ""
    @State private var keepCameraFeedRunning = false
    @State private var currentTime = Date()
    @State private var timeOffset: TimeInterval = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    let userId: Int
    let userName: String

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label("Dashboard", systemImage: "chart.bar.fill").tag("Dashboard")
                Label("Camera", systemImage: "video.fill").tag("Camera")
                Label("Sessions", systemImage: "clock.arrow.circlepath").tag("Sessions")
//                Label("Reports", systemImage: "doc.text.fill").tag("Reports")
//                Label("Settings", systemImage: "gear").tag("Settings")
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 180)
            .navigationTitle("Traffic Counter")
        } detail: {
            ZStack {
                // Keep this view mounted after Camera has first been opened.
                // The RTSP helper then continues feeding/counting while the
                // operator reviews Dashboard or Sessions, without reconnecting
                // on every tab change.
                CameraView(
                    userId: userId,
                    userName: userName,
                    sessionCoordinator: sessionCoordinator,
                    activeSchedule: $activeSchedule,
                    scheduledSessionCode: $scheduledSessionCode,
                    shouldMaintainFeed: $keepCameraFeedRunning
                )
                .opacity(selectedTab == "Camera" ? 1 : 0)
                .allowsHitTesting(selectedTab == "Camera")

                if selectedTab == "Sessions" {
                    SessionsView(sessionCoordinator: sessionCoordinator)
                } else if selectedTab == "Dashboard" {
                    DashboardView(sessionCoordinator: sessionCoordinator)
                } else if selectedTab == "Reports" {
                    ReportsView(sessionCoordinator: sessionCoordinator)
                } else if selectedTab == "Settings" {
                    Text("Settings View - Coming Soon").frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 700)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {}) {
                    HStack(spacing: 12) {
                        Text(formattedDate(currentTime.addingTimeInterval(timeOffset)))
                            .font(.system(size: 13, weight: .medium)).foregroundColor(.secondary)
                        Text(formattedTime(currentTime.addingTimeInterval(timeOffset)))
                            .font(.system(size: 14, weight: .semibold, design: .monospaced)).foregroundColor(.primary)
                    }.padding(.horizontal, 8)
                }.buttonStyle(.plain)
            }
        }
        .onAppear {
            syncTime()
            sessionCoordinator.start()
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == "Camera" { keepCameraFeedRunning = true }
        }
        .onDisappear { sessionCoordinator.stop() }
        .onReceive(timer) { currentTime = $0 }
    }

    private func syncTime() {
        guard let url = URL(string: "http://worldtimeapi.org/api/timezone/Asia/Manila") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = json["datetime"] as? String else { return }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let onlineTime = formatter.date(from: value) else { return }
            DispatchQueue.main.async { timeOffset = onlineTime.timeIntervalSince(Date()) }
        }.resume()
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "h:mm:ss a"
        formatter.amSymbol = "AM"; formatter.pmSymbol = "PM"
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "EEE, MMM. d yyyy"
        return formatter.string(from: date)
    }
}

private struct DashboardView: View {
    @ObservedObject var sessionCoordinator: AutoSessionCoordinator
    private var active: RemoteAutoSession? { sessionCoordinator.activeSession }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Traffic operations").font(.largeTitle.bold())
            Text("Real-time status for the desktop detection station.").foregroundColor(.secondary)
            HStack(spacing: 14) {
                DashboardMetric(title: "Active session", value: active?.sessionCode ?? "None", icon: "record.circle.fill", tint: active == nil ? .secondary : .red)
                DashboardMetric(title: "Scheduled", value: "\(sessionCoordinator.sessions.filter { $0.status == "scheduled" }.count)", icon: "calendar", tint: .orange)
                DashboardMetric(title: "Completed", value: "\(sessionCoordinator.sessions.filter { $0.status == "ended" }.count)", icon: "checkmark.circle.fill", tint: .green)
            }
            Group {
                if let active {
                    VStack(alignment: .leading, spacing: 8) { Label("Counting is active", systemImage: "dot.radiowaves.left.and.right").font(.headline).foregroundColor(.green); Text("\(active.cameraName) - \(active.roadName ?? active.location)"); Text("The camera console is receiving and sending counts for this session.").font(.caption).foregroundColor(.secondary) }
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                } else {
                    ContentUnavailableView("No active automatic session", systemImage: "calendar.badge.clock", description: Text("A session created on the website will appear and activate here automatically."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: active == nil ? .center : .topLeading)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct ReportsView: View {
    @ObservedObject var sessionCoordinator: AutoSessionCoordinator
    private var completed: [RemoteAutoSession] { sessionCoordinator.sessions.filter { $0.status == "ended" } }
    private var totalPCU: Double { completed.reduce(0) { $0 + ($1.detail?.totalPcu ?? 0) } }
    private var totalVehicles: Int { completed.reduce(0) { $0 + ($1.detail?.counts?.reduce(0, +) ?? 0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Reporting overview").font(.largeTitle.bold())
            Text("A ready-to-review summary of synchronized automatic sessions. Full survey forms remain available in the web dashboard.").foregroundColor(.secondary)
            HStack(spacing: 14) { DashboardMetric(title: "Completed sessions", value: "\(completed.count)", icon: "doc.text.fill", tint: .blue); DashboardMetric(title: "Recorded vehicles", value: "\(totalVehicles)", icon: "car.2.fill", tint: .teal); DashboardMetric(title: "Total PCU", value: String(format: "%.1f", totalPCU), icon: "chart.bar.fill", tint: .purple) }
            if completed.isEmpty { ContentUnavailableView("No completed sessions yet", systemImage: "doc.text", description: Text("Completed automatic sessions will be summarized here.")) }
            else { List(completed) { session in HStack { VStack(alignment: .leading) { Text(session.roadName ?? session.location).font(.headline); Text(session.sessionCode).font(.caption).foregroundColor(.secondary) }; Spacer(); Text("LOS \(session.detail?.los ?? "-")").font(.caption.bold()); Text(String(format: "%.1f PCU", session.detail?.totalPcu ?? 0)).monospacedDigit() } } }
            Spacer()
        }.padding(32)
    }
}

private struct DashboardMetric: View { let title: String; let value: String; let icon: String; let tint: Color; var body: some View { HStack { Image(systemName: icon).font(.title2).foregroundColor(tint); VStack(alignment: .leading) { Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1); Text(title).font(.caption).foregroundColor(.secondary) }; Spacer() }.padding(16).frame(maxWidth: .infinity).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)) } }

#Preview { ContentView(userId: 1, userName: "Preview User") }
