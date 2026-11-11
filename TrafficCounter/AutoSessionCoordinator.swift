import Foundation
import Combine

struct RemoteSchedule: Codable, Equatable {
    let id: Int
    let scheduleName: String?
    let cameraId: Int
    let roadName: String?
    let barangay: String?
    let city: String?
    let startDate: String?
    let endDate: String?
    let startTime: String?
    let endTime: String?
    let recurrence: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, barangay, city, recurrence
        case scheduleName = "schedule_name"
        case cameraId = "camera_id"
        case roadName = "road_name"
        case startDate = "start_date"
        case endDate = "end_date"
        case startTime = "start_time"
        case endTime = "end_time"
        case isActive = "is_active"
    }
}

struct RemoteSessionCamera: Codable, Equatable {
    let id: Int
    let name: String
    let ipAddress: String?
    let location: String?

    enum CodingKeys: String, CodingKey {
        case id, name, location
        case ipAddress = "ip_address"
    }
}

struct RemoteAutoSessionDetail: Codable, Equatable {
    let id: Int?
    let autoSessionId: Int?
    let totalPcu: Double?
    let vcRatio: Double?
    let los: String?
    let counts: [Int]?
    let pcuTotals: [Double]?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id, los, counts, source
        case autoSessionId = "auto_session_id"
        case totalPcu = "total_pcu"
        case vcRatio = "vc_ratio"
        case pcuTotals = "pcu_totals"
    }
}

struct RemoteAutoSession: Codable, Identifiable, Equatable {
    let id: Int
    let scheduleId: Int?
    let cameraId: Int?
    let sessionCode: String
    let cameraName: String
    let ipAddress: String
    let location: String
    let roadName: String?
    let barangay: String?
    let city: String?
    let direction: String?
    let lanes: Int?
    let hasMedian: Bool?
    let baseCapacityPerLane: Double?
    let startTime: String
    let endTime: String?
    let status: String
    let schedule: RemoteSchedule?
    let camera: RemoteSessionCamera?
    let detail: RemoteAutoSessionDetail?

    enum CodingKeys: String, CodingKey {
        case id, barangay, city, direction, lanes, status, schedule, camera, detail
        case scheduleId = "schedule_id"
        case cameraId = "camera_id"
        case sessionCode = "session_code"
        case cameraName = "camera_name"
        case ipAddress = "ip_address"
        case location
        case roadName = "road_name"
        case hasMedian = "has_median"
        case baseCapacityPerLane = "base_capacity_per_lane"
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

struct SessionMetrics {
    let counts: [Int]
    let pcuTotals: [Double]
    let totalPcu: Double
    let vcRatio: Double
    let los: String
}

@MainActor
final class AutoSessionCoordinator: ObservableObject {
    @Published private(set) var sessions: [RemoteAutoSession] = []
    @Published private(set) var activeSession: RemoteAutoSession?
    @Published private(set) var lastError: String?

    private var pollTimer: Timer?
    private var isRefreshing = false
    private var isSendingCounts = false
    private var latestCounts = Array(repeating: 0, count: 8)
    private var lastSentCounts: [Int]?
    private var finalizedSessionIDs = Set<Int>()

    func start() {
        guard pollTimer == nil else { return }
        Task { await refresh() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var fetched = try await SupabaseManager.shared.fetchAutoSessions()
            let now = Date()

            // Activate the exact website-created auto_session when its window begins.
            for session in fetched where session.status == "scheduled" {
                guard let start = SessionDateParser.parse(session.startTime),
                      let endText = session.endTime,
                      let end = SessionDateParser.parse(endText),
                      now >= start, now < end else { continue }
                try await SupabaseManager.shared.activateAutoSession(session)
            }

            // Refresh after an activation so Sessions and Auto Records see one status.
            fetched = try await SupabaseManager.shared.fetchAutoSessions()

            if let running = fetched.first(where: { $0.status == "active" }),
               let endText = running.endTime,
               let end = SessionDateParser.parse(endText), now >= end {
                try await SupabaseManager.shared.completeAutoSession(running, counts: latestCounts)
                fetched = try await SupabaseManager.shared.fetchAutoSessions()
            }

            let previousActiveSession = activeSession
            let previousID = previousActiveSession?.id
            sessions = fetched
            let nextActiveSession = fetched.first(where: { session in
                guard session.status == "active",
                      let start = SessionDateParser.parse(session.startTime),
                      let endText = session.endTime,
                      let end = SessionDateParser.parse(endText) else { return false }
                return now >= start && now < end
            })

            // The website lifecycle may close the session before the desktop's
            // next poll. Persist the final desktop counter once even in that
            // order, so Auto Records never loses the last detected vehicles.
            if let previousActiveSession,
               previousActiveSession.id != nextActiveSession?.id,
               !finalizedSessionIDs.contains(previousActiveSession.id) {
                try await SupabaseManager.shared.updateLiveCounts(previousActiveSession, counts: latestCounts)
                finalizedSessionIDs.insert(previousActiveSession.id)
            }

            activeSession = nextActiveSession

            if previousID != activeSession?.id {
                latestCounts = activeSession?.detail?.counts ?? Array(repeating: 0, count: 8)
                lastSentCounts = nil
                if let activeSession { finalizedSessionIDs.remove(activeSession.id) }
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("Auto-session synchronization failed: \(error.localizedDescription)")
        }
    }

    func submitCounts(_ counts: [Int]) async {
        guard counts.count == 8,
              let session = activeSession,
              !isSendingCounts else { return }

        latestCounts = counts
        guard counts != lastSentCounts else { return }
        isSendingCounts = true
        defer { isSendingCounts = false }

        do {
            try await SupabaseManager.shared.updateLiveCounts(session, counts: counts)
            lastSentCounts = counts
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("Live-count upload failed: \(error.localizedDescription)")
        }
    }
}

enum SessionDateParser {
    static func parse(_ value: String) -> Date? {
        // Handles timestamps that already include a timezone.
        let iso = ISO8601DateFormatter()

        iso.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        if let date = iso.date(from: value) {
            return date
        }

        iso.formatOptions = [.withInternetDateTime]

        if let date = iso.date(from: value) {
            return date
        }

        /*
         Supabase may return PostgreSQL timestamp values without a timezone.

         Laravel stores automatic-session timestamps in UTC. Therefore:
         13:33 UTC = 21:33 or 9:33 PM in the Philippines.
        */
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSSSSS",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]

        for format in formats {
            formatter.dateFormat = format

            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
