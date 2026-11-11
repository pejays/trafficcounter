import SwiftUI

struct SessionsView: View {
    @ObservedObject var sessionCoordinator: AutoSessionCoordinator
    @State private var filter = "All"
    @State private var searchText = ""
    @State private var selectedSession: RemoteAutoSession?
    private let filters = ["All", "Active", "Scheduled", "Ended"]

    private var filteredSessions: [RemoteAutoSession] {
        sessionCoordinator.sessions.filter { session in
            let matchesFilter = filter == "All" || session.status.caseInsensitiveCompare(filter) == .orderedSame
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return matchesFilter }
            let searchable = [session.sessionCode, session.roadName, session.schedule?.scheduleName, session.cameraName, session.barangay, session.city, session.direction].compactMap { $0 }.joined(separator: " ")
            return matchesFilter && searchable.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredSessions.isEmpty { emptyState }
            else { sessionList }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $selectedSession) { session in SessionDetailSheet(session: session) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) { Text("Sessions").font(.largeTitle.bold()); Text("Automatic counts from VehiSight, updated in real time.").foregroundColor(.secondary) }
                Spacer()
                Label("Live", systemImage: "dot.radiowaves.left.and.right").font(.subheadline.weight(.medium)).foregroundColor(.green)
            }
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("Search road, camera, location, or session ID", text: $searchText)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("Search sessions")
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: 420)
                .background(Color.gray.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.gray.opacity(0.28), lineWidth: 1))
                Spacer()
                Picker("Session status", selection: $filter) { ForEach(filters, id: \.self) { Text($0) } }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
            }
            HStack(spacing: 18) {
                summary("\(sessionCoordinator.sessions.count)", "All sessions")
                summary("\(sessionCoordinator.sessions.filter { $0.status == "active" }.count)", "Active")
                summary("\(sessionCoordinator.sessions.filter { $0.status == "scheduled" }.count)", "Scheduled")
                summary("\(sessionCoordinator.sessions.filter { $0.status == "ended" }.count)", "Completed")
                Spacer()
                Text("\(filteredSessions.count) shown").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 20)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredSessions) { session in
                    Button { selectedSession = session } label: { SessionRow(session: session) }
                        .buttonStyle(.plain)
                    if session.id != filteredSessions.last?.id { Divider().padding(.leading, 28) }
                }
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(28)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(searchText.isEmpty ? "No \(filter.lowercased()) sessions" : "No matching sessions", systemImage: searchText.isEmpty ? "calendar.badge.clock" : "magnifyingglass", description: Text(searchText.isEmpty ? "Sessions created on the web dashboard appear here." : "Try another road, camera, location, or session ID."))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func summary(_ value: String, _ label: String) -> some View { VStack(alignment: .leading, spacing: 1) { Text(value).font(.headline.monospacedDigit()); Text(label).font(.caption).foregroundColor(.secondary) } }
}

@MainActor private struct SessionRow: View {
    let session: RemoteAutoSession
    private var statusColor: Color { ["active": .green, "ended": .purple, "scheduled": .orange][session.status.lowercased()] ?? .secondary }
    private var detail: RemoteAutoSessionDetail? { session.detail }
    private var formattedWindow: String { let start = SessionDateParser.parse(session.startTime); let end = session.endTime.flatMap(SessionDateParser.parse); let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: "Asia/Manila"); formatter.dateFormat = "MMM d, h:mm a"; guard let start else { return session.startTime }; return "\(formatter.string(from: start)) - \(end.map { formatter.string(from: $0) } ?? "Open")" }
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: session.status == "active" ? "record.circle.fill" : "clock").font(.title3).foregroundColor(statusColor).frame(width: 26)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(session.roadName ?? session.schedule?.roadName ?? "Unknown road").font(.headline); Text(session.sessionCode).font(.caption.monospaced()).foregroundColor(.secondary) }
                HStack(spacing: 14) { label("video.fill", session.cameraName); label("mappin.and.ellipse", [session.barangay, session.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")); label("clock", formattedWindow) }
            }
            Spacer()
            if let detail { HStack(spacing: 14) { result("PCU", String(format: "%.1f", detail.totalPcu ?? 0)); result("LOS", detail.los ?? "-") } }
            Text(session.status.uppercased()).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(statusColor.opacity(0.16), in: Capsule()).foregroundColor(statusColor)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.horizontal, 18).padding(.vertical, 15).contentShape(Rectangle())
    }
    private func label(_ icon: String, _ text: String) -> some View { Label(text.isEmpty ? "Not specified" : text, systemImage: icon).font(.caption).foregroundColor(.secondary).lineLimit(1) }
    private func result(_ title: String, _ value: String) -> some View { VStack(alignment: .trailing, spacing: 1) { Text(value).font(.subheadline.bold().monospacedDigit()); Text(title).font(.caption2).foregroundColor(.secondary) } }
}

@MainActor private struct SessionDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: RemoteAutoSession
    private var statusColor: Color { ["active": .green, "ended": .purple, "scheduled": .orange][session.status.lowercased()] ?? .secondary }
    private var detail: RemoteAutoSessionDetail? { session.detail }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 3) { Text(session.roadName ?? session.schedule?.roadName ?? "Unknown road").font(.title2.bold()); Text(session.sessionCode).font(.caption.monospaced()).foregroundColor(.secondary) }; Spacer(); Text(session.status.uppercased()).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6).background(statusColor.opacity(0.16), in: Capsule()).foregroundColor(statusColor); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }.buttonStyle(.plain).foregroundColor(.secondary).accessibilityLabel("Close session details") }
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) { GridRow { field("Camera", session.cameraName, "video.fill"); field("Location", [session.barangay, session.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "), "mappin.and.ellipse") }; GridRow { field("Direction", session.direction ?? "Not specified", "arrow.left.arrow.right"); field("Road setup", "\(session.lanes ?? 1) lane(s)\(session.hasMedian == true ? ", median present" : "")", "signpost.right") } }
            if let detail { Divider(); HStack(spacing: 12) { metric("Vehicles", "\(detail.counts?.reduce(0, +) ?? 0)"); metric("PCU", String(format: "%.1f", detail.totalPcu ?? 0)); metric("V/C", String(format: "%.2f", detail.vcRatio ?? 0)); metric("LOS", detail.los ?? "-") } }
        }.padding(24).frame(width: 580)
    }
    private func field(_ title: String, _ value: String, _ icon: String) -> some View { VStack(alignment: .leading, spacing: 4) { Label(title, systemImage: icon).font(.caption).foregroundColor(.secondary); Text(value.isEmpty ? "Not specified" : value).font(.subheadline) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func metric(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 2) { Text(value).font(.headline.monospacedDigit()); Text(title).font(.caption).foregroundColor(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 9)) }
}

#Preview { SessionsView(sessionCoordinator: AutoSessionCoordinator()) }
