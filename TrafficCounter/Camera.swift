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


struct Camera: Identifiable, Codable, Equatable, Hashable {
    let id = UUID()
    var name: String  // Changed from 'let' to 'var'
    var remoteId: Int? // <--- ADD THIS LINE
    let ip: String
    let username: String
    let password: String
    var isEnabled: Bool = true // 
    
    var rtspURL: String {
        return "rtsp://\(username):\(password)@\(ip)/Streaming/Channels/101"
    }
    
    static func == (lhs: Camera, rhs: Camera) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
