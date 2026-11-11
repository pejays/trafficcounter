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
    @Published var vehicleCounts: [String: Int] = [:]
    @Published var currentCameraName: String = ""
    @Published var lastError: String?
    
    private var isStarting = false
    private var pendingLineUpdate: Double? = nil
    private var pendingAngleUpdate: Double? = nil
    
    private var process: Process?
    private var frameTimer: Timer?
    private var session: URLSession?
    private var isServerReady = false
    private var isFetchingFrame = false
    private var isFetchingCounts = false
    private var cameraRequested = false
    private var readinessAttempts = 0
    // The Python helper adapts its production rate to available CPU. Poll at
    // the 30 FPS ceiling so Swift renders every frame the helper can provide.
    private let previewFrameInterval: TimeInterval = 1.0 / 30.0
    private let processQueue = DispatchQueue(label: "TrafficCounter.camera-process", qos: .userInitiated)
    
    func startCamera() {
        guard !isStarting, process?.isRunning != true else { return }
        isStarting = true
        cameraRequested = true
        lastError = nil
        
        print("Starting Python RTSP handler...")
        
        let sourceScriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("python/rtsp_capture.py")
        let scriptURL = Bundle.main.url(forResource: "rtsp_capture", withExtension: "py") ?? sourceScriptURL
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            isStarting = false
            lastError = "The local camera service could not be found. Rebuild the desktop app from Traffic_Counter_Realtime."
            return
        }

        // Remove only a stale copy of this project's helper. The former global
        // pkill and force-kill-on-port could disrupt unrelated local services.
        processQueue.async { [weak self] in
            let staleProcess = Process()
            staleProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            staleProcess.arguments = ["-f", scriptURL.path]
            try? staleProcess.run()
            staleProcess.waitUntilExit()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self?.launchCameraService(scriptURL: scriptURL)
            }
        }
    }

    private func launchCameraService(scriptURL: URL) {
        defer { isStarting = false }
        guard cameraRequested, process?.isRunning != true else { return }

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 1
        configuration.timeoutIntervalForResource = 3
        session = URLSession(configuration: configuration)

        let cameraProcess = Process()
        cameraProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        cameraProcess.arguments = [scriptURL.path]
        cameraProcess.terminationHandler = { [weak self] terminatedProcess in
            guard terminatedProcess.terminationStatus != 0 else { return }
            DispatchQueue.main.async {
                guard self?.process === terminatedProcess else { return }
                self?.lastError = "The local camera service stopped unexpectedly."
                self?.isConnected = false
            }
        }

        do {
            try cameraProcess.run()
            process = cameraProcess
            print("Python script started")
            loadSavedCameraSettings()
            checkServerReady()
        } catch {
            lastError = "Unable to start the local camera service."
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
            updateCameraSettings(ip: cameraIP, username: username, password: password)
        }
    }
    
    func updateCameraSettings(ip: String, username: String, password: String) {
        var components = URLComponents(string: "http://127.0.0.1:8888/update")
        components?.queryItems = [
            URLQueryItem(name: "ip", value: ip),
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password)
        ]
        guard let url = components?.url else { return }
        session?.dataTask(with: url) { data, response, error in
            if let data = data {
                print("Camera settings updated: \(String(data: data, encoding: .utf8) ?? "")")
            }
        }.resume()
    }
    
    func checkServerReady() {
        guard let url = URL(string: "http://127.0.0.1:8888/health") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 0.5
        
        let task = session?.dataTask(with: request) { data, response, error in
            let streamIsReady = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
            if error == nil, streamIsReady {
                DispatchQueue.main.async {
                    self.readinessAttempts = 0
                    self.lastError = nil
                    self.isServerReady = true
                    self.isConnected = true
                    
                    // Apply pending updates instantly on connect
                    if let pendingPos = self.pendingLineUpdate {
                        self.updateCountingLine(position: pendingPos)
                    }
                    if let pendingAngle = self.pendingAngleUpdate {
                        self.updateCountingAngle(angle: pendingAngle)
                    }
                    
                    self.frameTimer = Timer.scheduledTimer(timeInterval: self.previewFrameInterval, target: self, selector: #selector(self.fetchFrame), userInfo: nil, repeats: true)
                    print("Camera connected via Python HTTP")
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.readinessAttempts += 1
                    if self.readinessAttempts == 10 {
                        self.lastError = "Camera stream is unreachable. Connect to the camera's network, or use a camera address reachable from this Wi-Fi."
                    }
                    self.checkServerReady()
                }
            }
        }
        task?.resume()
    }
    
    @objc func fetchFrame() {
        guard isServerReady, let session else { return }
        
        guard !isFetchingFrame,
              let frameUrl = URL(string: "http://127.0.0.1:8888/frame") else { return }
        isFetchingFrame = true
        session.dataTask(with: frameUrl) { [weak self] data, _, _ in
            DispatchQueue.main.async { self?.isFetchingFrame = false }
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async { self?.currentFrame = image }
            }
        }.resume()
        
        guard !isFetchingCounts,
              let countsUrl = URL(string: "http://127.0.0.1:8888/counts") else { return }
        isFetchingCounts = true
        session.dataTask(with: countsUrl) { [weak self] data, _, _ in
            DispatchQueue.main.async { self?.isFetchingCounts = false }
            if let data = data {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Int] {
                    DispatchQueue.main.async { self?.vehicleCounts = json }
                }
            }
        }.resume()
    }
    
    func saveCameraToUserDefaults(name: String, ip: String, username: String, password: String) {
        let defaults = UserDefaults.standard
        defaults.set(name, forKey: "saved_camera_name")
        defaults.set(ip, forKey: "saved_camera_ip")
        defaults.set(username, forKey: "saved_camera_username")
        defaults.set(password, forKey: "saved_camera_password")
        
        currentCameraName = name
        
        let settings = ["ip": ip, "username": username, "password": password]
        if let jsonData = try? JSONSerialization.data(withJSONObject: settings),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let filePath = "/tmp/camera_settings.json"
            try? jsonString.write(toFile: filePath, atomically: true, encoding: .utf8)
        }
        
        updateCameraSettings(ip: ip, username: username, password: password)
    }
    
    func updateCountingLine(position: Double) {
        pendingLineUpdate = position
        guard let url = URL(string: "http://127.0.0.1:8888/update_line?y=\(position)") else { return }
        URLSession.shared.dataTask(with: url).resume()
    }
    
    func updateCountingAngle(angle: Double) {
        pendingAngleUpdate = angle
        guard let url = URL(string: "http://127.0.0.1:8888/update_angle?a=\(angle)") else { return }
        URLSession.shared.dataTask(with: url).resume()
    }
    
    func stopCamera() {
        cameraRequested = false
        frameTimer?.invalidate()
        frameTimer = nil
        session?.invalidateAndCancel()
        session = nil
        process?.terminate()
        process = nil
        isServerReady = false
        isFetchingFrame = false
        isFetchingCounts = false
        DispatchQueue.main.async { self.isConnected = false }
        print("Python camera stopped")
    }
    
    func refreshCameraFeed() {
        stopCamera()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.startCamera()
        }
    }
    
    func toggleCounting(isActive: Bool) {
        // We will send a signal to Python to either count or pause
        let activeStr = isActive ? "1" : "0"
        guard let url = URL(string: "http://127.0.0.1:8888/toggle_counting?active=\(activeStr)") else { return }
        URLSession.shared.dataTask(with: url).resume()
    }

    func resetCounts() {
        guard let url = URL(string: "http://127.0.0.1:8888/reset_counts") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] _, response, _ in
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return }
            DispatchQueue.main.async {
                self?.vehicleCounts = [
                    "private car": 0, "jeepney": 0, "uv": 0, "bus-minibus": 0,
                    "light truck": 0, "heavy truck": 0, "motorcycle": 0, "tricycle": 0
                ]
            }
        }.resume()
    }
}
