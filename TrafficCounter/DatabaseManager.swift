//
//  DatabaseManager.swift
//  TrafficCounter
//

import Foundation
import PostgresClientKit

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private var connection: Connection?
    private var isConnected = false
    
    func connect() async throws {
        var configuration = ConnectionConfiguration()
        configuration.host = "192.168.110.131"  // James Abiera's Windows IP address
        configuration.port = 5432
        configuration.database = "vehisights_db"
        configuration.user = "postgres"  // or his PostgreSQL username
        configuration.credential = .scramSHA256(password: "abiera27")
        configuration.ssl = false
        
        connection = try Connection(configuration: configuration)
        // PostgresClientKit opens connection automatically on creation
        isConnected = true
        print("Connected to PostgreSQL")
    }
    
    func disconnect() {
        connection?.close()
        connection = nil
        isConnected = false
        print("Disconnected from PostgreSQL")
    }
    
    func saveSession(
        sessionCode: String,
        roadName: String,
        barangay: String,
        city: String,
        direction: String,
        lanes: Int,
        hasMedian: Bool,
        startTime: String,
        endTime: String,
        createdBy: Int
    ) async throws {
        guard let connection = connection, isConnected else {
            throw NSError(domain: "DatabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        let baseCapacityPerLane = hasMedian ? 650 : 720
        
        let text = """
        INSERT INTO sessions (
            session_code, road_name, barangay, city, 
            direction, lanes, has_median, start_time, end_time,
            created_by, created_at, updated_at, base_capacity_per_lane
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW(), NOW(), $11)
        """
        
        let statement = try connection.prepareStatement(text: text)
        
        let cursor = try statement.execute(parameterValues: [
            sessionCode,
            roadName,
            barangay,
            city,
            direction,
            lanes,
            hasMedian,
            startTime,
            endTime,
            createdBy,
            baseCapacityPerLane
        ])
        
        try cursor.close()
        print("✅ Session saved: \(sessionCode)")
    }
    
    func updateSessionDetails(
        sessionCode: String,
        endTime: Date,
        details: [String: Any]
    ) async throws {
        guard let connection = connection, isConnected else {
            throw NSError(domain: "DatabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        let detailsJSON = try JSONSerialization.data(withJSONObject: details)
        let detailsString = String(data: detailsJSON, encoding: .utf8) ?? "{}"
        
        let text = """
        UPDATE sessions 
        SET end_time = $1, 
            details = $2::jsonb, 
            updated_at = NOW()
        WHERE session_code = $3
        """
        
        let statement = try connection.prepareStatement(text: text)
        
        let formatter = ISO8601DateFormatter()
        let endTimeString = formatter.string(from: endTime)
        
        let cursor = try statement.execute(parameterValues: [
            endTimeString,
            detailsString,
            sessionCode
        ])
        
        try cursor.close()
        print("✅ Session updated with details: \(sessionCode)")
    }
    
    func authenticateUser(email: String, password: String) async throws -> Int {
        guard let connection = connection, isConnected else {
            throw NSError(domain: "DatabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not connected"])
        }
        
        let text = "SELECT id, name, email, password FROM users WHERE email = $1"
        let statement = try connection.prepareStatement(text: text)
        let cursor = try statement.execute(parameterValues: [email])
        
        var userId = 0
        var storedPassword = ""
        
        while let maybeRow = try cursor.next() {
            let row = try maybeRow.get()
            let columns = row.columns
            userId = try columns[0].int() ?? 0
            storedPassword = try columns[3].string() ?? ""
        }
        
        if userId == 0 {
            throw NSError(domain: "DatabaseManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        
        if storedPassword == password {
            print("✅ User authenticated: \(email)")
            return userId
        } else {
            throw NSError(domain: "DatabaseManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid password"])
        }
    }
}
