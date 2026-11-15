//
//  Camera.swift
//  TrafficCounter
//
//  Created by Jhon Patrick Acedo on 5/26/26.
//


//
//  CameraModel.swift
//  TrafficCounter
//

import Foundation

enum CameraStreamProfile: String, Codable, CaseIterable, Identifiable {
    case hikvision
    case tapo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hikvision: "Hikvision / compatible"
        case .tapo: "Tapo C210"
        }
    }

    var rtspPath: String {
        switch self {
        case .hikvision: "/Streaming/Channels/101"
        case .tapo: "/stream1"
        }
    }
}

struct Camera: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String  // Changed from 'let' to 'var'
    var remoteId: Int? // <--- ADD THIS LINE
    let ip: String
    let username: String
    let password: String
    var isEnabled: Bool = true // 
    var streamProfile: CameraStreamProfile = .hikvision

    init(
        id: UUID = UUID(),
        name: String,
        remoteId: Int? = nil,
        ip: String,
        username: String,
        password: String,
        isEnabled: Bool = true,
        streamProfile: CameraStreamProfile = .hikvision
    ) {
        self.id = id
        self.name = name
        self.remoteId = remoteId
        self.ip = ip
        self.username = username
        self.password = password
        self.isEnabled = isEnabled
        self.streamProfile = streamProfile
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, remoteId, ip, username, password, isEnabled, streamProfile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        remoteId = try container.decodeIfPresent(Int.self, forKey: .remoteId)
        ip = try container.decode(String.self, forKey: .ip)
        username = try container.decode(String.self, forKey: .username)
        password = try container.decode(String.self, forKey: .password)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        // Older saved cameras used Hikvision's path. Preserve that behavior.
        streamProfile = try container.decodeIfPresent(CameraStreamProfile.self, forKey: .streamProfile) ?? .hikvision
    }
    
    var rtspURL: String {
        let encodedUsername = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        let encodedPassword = password.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? password
        return "rtsp://\(encodedUsername):\(encodedPassword)@\(ip)\(streamProfile.rtspPath)"
    }
    
    static func == (lhs: Camera, rhs: Camera) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
