import Foundation

struct SupabaseCameraResponse: Codable {
    let id: Int
    let name: String
    let ip_address: String?
    let location: String?
    let status: String?
}

class SupabaseManager {
    static let shared = SupabaseManager()
    
    private let supabaseURL = "https://mcorimlkqkjdwyyjorob.supabase.co"
    private let supabaseKey = "sb_publishable_cK0gXe8h8-eChMBNci-vFA_M5l9KlSF"
    
    private var defaultHeaders: [String: String] {
        [
            "apikey": supabaseKey,
            "Authorization": "Bearer \(supabaseKey)",
            "Content-Type": "application/json"
        ]
    }
    
    // MARK: - Create
    func saveCamera(name: String, ip: String, completion: @escaping (Result<SupabaseCameraResponse, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/cameras") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.allHTTPHeaderFields = defaultHeaders
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        
        let cameraData: [String: Any] = [
            "name": name,
            "ip_address": ip,
            "location": "Main Road",
            "status": "online",
            "created_by": 1
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: cameraData, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), let data = data else {
                let errorMsg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                print("Supabase Save Error: \(errorMsg)")
                completion(.failure(NSError(domain: "Supabase", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to save camera."])))
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([SupabaseCameraResponse].self, from: data)
                if let savedCamera = decoded.first {
                    completion(.success(savedCamera))
                } else {
                    completion(.failure(NSError(domain: "Supabase", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data returned"])))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Read
    func fetchCameras(completion: @escaping (Result<[SupabaseCameraResponse], Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/cameras?select=*") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allHTTPHeaderFields = defaultHeaders
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode), let data = data else {
                let errorMsg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                print("Supabase Fetch Error: \(errorMsg)")
                completion(.failure(NSError(domain: "Supabase", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch cameras."])))
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode([SupabaseCameraResponse].self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - Update
    func updateCamera(id: Int, newName: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/cameras?id=eq.\(id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.allHTTPHeaderFields = defaultHeaders
        
        let updateData: [String: Any] = ["name": newName]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: updateData, options: [])
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                completion(.success(()))
            } else {
                let errorMsg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                print("Supabase Update Error: \(errorMsg)")
                completion(.failure(NSError(domain: "Supabase", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to update camera."])))
            }
        }.resume()
    }

    /// Keeps the camera availability shown by VehiSights in sync with the
    /// operator's Enable/Disable control in the desktop app.
    func updateCameraStatus(id: Int, isEnabled: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/cameras?id=eq.\(id)") else {
            completion(.failure(NSError(
                domain: "Supabase",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid camera status request."]
            )))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.allHTTPHeaderFields = defaultHeaders

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "status": isEnabled ? "online" : "offline"
            ])
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }

            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                let message = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                completion(.failure(NSError(
                    domain: "Supabase",
                    code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )))
                return
            }

            completion(.success(()))
        }.resume()
    }
    
    // MARK: - Delete
    func deleteCamera(id: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let url = URL(string: "\(supabaseURL)/rest/v1/cameras?id=eq.\(id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.allHTTPHeaderFields = defaultHeaders
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                completion(.success(()))
            } else {
                let errorMsg = String(data: data ?? Data(), encoding: .utf8) ?? "Unknown error"
                print("Supabase Delete Error: \(errorMsg)")
                completion(.failure(NSError(domain: "Supabase", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to delete camera."])))
            }
        }.resume()
    }
    
    // MARK: - Website-created automatic sessions

    func fetchAutoSessions() async throws -> [RemoteAutoSession] {
        let select = "*,schedule:schedules(*),camera:cameras(*),detail:auto_session_details(*)"
        let data = try await request(
            table: "auto_sessions",
            queryItems: [
                URLQueryItem(name: "select", value: select),
                URLQueryItem(name: "order", value: "start_time.desc")
            ]
        )
        return try JSONDecoder().decode([RemoteAutoSession].self, from: data)
    }

    func activateAutoSession(_ session: RemoteAutoSession) async throws {
        _ = try await request(
            table: "auto_sessions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.id)")],
            method: "PATCH",
            body: ["status": "active"]
        )

        let now = timestamp(Date())
        _ = try await request(
            table: "schedule_logs",
            queryItems: [
                URLQueryItem(name: "auto_session_id", value: "eq.\(session.id)"),
                URLQueryItem(name: "status", value: "eq.pending")
            ],
            method: "PATCH",
            body: ["status": "running", "started_at": now]
        )
    }

    func updateLiveCounts(_ session: RemoteAutoSession, counts: [Int]) async throws {
        let metrics = metrics(for: session, counts: counts)
        let body: [String: Any] = [
            "auto_session_id": session.id,
            "counts": metrics.counts,
            "pcu_totals": metrics.pcuTotals,
            "total_pcu": metrics.totalPcu,
            "vc_ratio": metrics.vcRatio,
            "los": metrics.los,
            "source": "auto",
            "updated_at": timestamp(Date())
        ]
        _ = try await request(
            table: "auto_session_details",
            queryItems: [URLQueryItem(name: "on_conflict", value: "auto_session_id")],
            method: "POST",
            body: body,
            prefer: "resolution=merge-duplicates,return=representation"
        )
    }

    func completeAutoSession(_ session: RemoteAutoSession, counts: [Int]) async throws {
        try await updateLiveCounts(session, counts: counts)
        let now = timestamp(Date())

        _ = try await request(
            table: "auto_sessions",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(session.id)")],
            method: "PATCH",
            body: ["status": "ended", "updated_at": now]
        )
        _ = try await request(
            table: "schedule_logs",
            queryItems: [URLQueryItem(name: "auto_session_id", value: "eq.\(session.id)")],
            method: "PATCH",
            body: ["status": "success", "completed_at": now]
        )

        if let cameraID = session.cameraId {
            _ = try await request(
                table: "cameras",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(cameraID)")],
                method: "PATCH",
                body: ["last_detection_at": now]
            )
        }
        if let schedule = session.schedule, schedule.recurrence?.lowercased() == "once" {
            _ = try await request(
                table: "schedules",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(schedule.id)")],
                method: "PATCH",
                body: ["is_active": false, "updated_at": now]
            )
        }

        let result = metrics(for: session, counts: counts)
        var history: [String: Any] = [
            "auto_session_id": session.id,
            "road_name": session.roadName ?? session.location,
            "direction": session.direction ?? "",
            "hour_timestamp": session.startTime,
            "total_pcu": result.totalPcu,
            "vc_ratio": result.vcRatio,
            "los": result.los,
            "counts": result.counts,
            "source": "auto",
            "updated_at": now
        ]
        if let cameraID = session.cameraId { history["camera_id"] = cameraID }
        _ = try await request(
            table: "traffic_history",
            queryItems: [URLQueryItem(name: "on_conflict", value: "auto_session_id")],
            method: "POST",
            body: history,
            prefer: "resolution=merge-duplicates,return=minimal"
        )
    }

    private func metrics(for session: RemoteAutoSession, counts: [Int]) -> SessionMetrics {
        let normalized = Array((counts + Array(repeating: 0, count: 8)).prefix(8))
        let factors = [1.0, 1.5, 1.5, 2.5, 2.0, 3.0, 0.5, 0.7]
        let pcuTotals = zip(normalized, factors).map { Double($0.0) * $0.1 }
        let total = pcuTotals.reduce(0, +)
        let capacity = max(1.0, Double(session.lanes ?? 1) * (session.baseCapacityPerLane ?? 720.0))
        let ratio = (total / capacity * 100).rounded() / 100
        let los: String
        switch ratio {
        case ..<0.20: los = "A"
        case ..<0.45: los = "B"
        case ..<0.70: los = "C"
        case ..<0.85: los = "D"
        case ...1.00: los = "E"
        default: los = "F"
        }
        return SessionMetrics(counts: normalized, pcuTotals: pcuTotals, totalPcu: total, vcRatio: ratio, los: los)
    }

    private func request(
        table: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: [String: Any]? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        guard var components = URLComponents(string: "\(supabaseURL)/rest/v1/\(table)") else {
            throw NSError(domain: "Supabase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase URL."])
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw NSError(domain: "Supabase", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Supabase request."])
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.allHTTPHeaderFields = defaultHeaders
        if let prefer { urlRequest.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown Supabase error"
            throw NSError(domain: "Supabase", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
        return data
    }

    private func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
