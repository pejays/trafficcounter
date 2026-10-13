//
//  PythonCameraHandler.swift
//  TrafficCounter
//

import Foundation
import SwiftUI
import Combine

class PythonCameraHandler: NSObject, ObservableObject {
    @Published var currentFrame: NSImage?
    @Published var isConnected = false
    @Published var currentCameraName: String = ""
    private var isStarting = false
    
    private var process: Process?
    private var frameTimer: Timer?
    private var session: URLSession?
    private var isServerReady = false
    
    func startCamera() {
        guard !isStarting else {
            print("Already starting, skipping...")
            return
        }
        isStarting = true
        defer { isStarting = false }
        
        print("Starting Python RTSP handler...")
        
        // Kill any existing process on port 8888 first
        let killPortTask = Process()
        killPortTask.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killPortTask.arguments = ["-f", "rtsp_capture.py"]
        try? killPortTask.run()
        killPortTask.waitUntilExit()
        
        // Also kill via lsof
        let killLsofTask = Process()
        killLsofTask.executableURL = URL(fileURLWithPath: "/bin/bash")
        killLsofTask.arguments = ["-c", "lsof -ti:8888 | xargs kill -9 2>/dev/null"]
        try? killLsofTask.run()
        
        // Wait for port to be freed
        Thread.sleep(forTimeInterval: 0.5)
        
        let scriptPath = NSHomeDirectory() + "/Documents/TrafficCounter/TrafficCounter/python/rtsp_capture.py"
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process?.arguments = [scriptPath]
        
        do {
            try process?.run()
            print("Python script started")
            
            session = URLSession.shared
            
            // Load saved camera settings
            loadSavedCameraSettings()
            
            // Wait for server to be ready
            checkServerReady()
            
        } catch {
            print("Failed to start Python: \(error)")
        }
    }
    
    func loadSavedCameraSettings() {
        let defaults = UserDefaults.standard
        if let cameraName = defaults.string(forKey: "saved_camera_name"),
           let cameraIP = defaults.string(forKey: "saved_camera_ip"),
           let username = defaults.string(forKey: "saved_camera_username"),
           let password = defaults.string(forKey: "saved_camera_password") {
            
            currentCameraName = cameraName
            print("Loaded saved camera: \(cameraName) at \(cameraIP)")
            
            // Update Python script with saved settings
            updateCameraSettings(ip: cameraIP, username: username, password: password)
        }
    }
    
    func updateCameraSettings(ip: String, username: String, password: String) {
        guard let url = URL(string: "http://localhost:8888/update?ip=\(ip)&username=\(username)&password=\(password)") else { return }
        
        let task = session?.dataTask(with: url) { data, response, error in
            if let data = data {
                print("Camera settings updated: \(String(data: data, encoding: .utf8) ?? "")")
            }
        }
        task?.resume()
    }
    
    func checkServerReady() {
        guard let url = URL(string: "http://localhost:8888/frame") else { return }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        
        let task = session?.dataTask(with: request) { data, response, error in
            if error == nil {
                DispatchQueue.main.async {
                    self.isServerReady = true
                    self.isConnected = true
                    self.frameTimer = Timer.scheduledTimer(timeInterval: 0.033, target: self, selector: #selector(self.fetchFrame), userInfo: nil, repeats: true)
                    print("Camera connected via Python HTTP")
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkServerReady()
                }
            }
        }
        task?.resume()
    }
    
    @objc func fetchFrame() {
        guard isServerReady else { return }
        guard let url = URL(string: "http://localhost:8888/frame") else { return }
        
        let task = session?.dataTask(with: url) { data, response, error in
            if let data = data, error == nil {
                if let image = NSImage(data: data) {
                    DispatchQueue.main.async {
                        self.currentFrame = image
                    }
                }
            }
        }
        task?.resume()
    }
    
    func saveCameraToUserDefaults(name: String, ip: String, username: String, password: String) {
        let defaults = UserDefaults.standard
        defaults.set(name, forKey: "saved_camera_name")
        defaults.set(ip, forKey: "saved_camera_ip")
        defaults.set(username, forKey: "saved_camera_username")
        defaults.set(password, forKey: "saved_camera_password")
        
        currentCameraName = name
        
        // Also write to JSON file for Python script
        let settings = ["ip": ip, "username": username, "password": password]
        if let jsonData = try? JSONSerialization.data(withJSONObject: settings),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let filePath = "/tmp/camera_settings.json"
            try? jsonString.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        
        // Update Python script with new settings
        updateCameraSettings(ip: ip, username: username, password: password)
    }
    
    func stopCamera() {
        frameTimer?.invalidate()
        frameTimer = nil
        session?.finishTasksAndInvalidate()
        session = nil
        process?.terminate()
        process = nil
        isServerReady = false
        DispatchQueue.main.async {
            self.isConnected = false
        }
        print("Python camera stopped")
    }
    
    func refreshCameraFeed() {
        print("Refreshing camera feed...")
        stopCamera()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startCamera()
        }
    }
}
