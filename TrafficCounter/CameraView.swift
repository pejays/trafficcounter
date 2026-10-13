//
//  CameraView.swift
//  TrafficCounter
//

import SwiftUI
import Combine

struct CameraView: View {
    @AppStorage("savedCameras") private var savedCamerasData: Data = Data()
    @State private var cameras: [Camera] = []
    @State private var selectedCamera: Camera?
    @State private var showingAddCameraSheet = false
    @State private var newCameraName = ""
    @State private var newCameraIP = ""
    @State private var newCameraUsername = "admin"
    @State private var newCameraPassword = ""
    @State private var isTestingConnection = false
    @State private var connectionStatus: String? = nil
    @State private var isConnectionSuccessful = false
    
    @State private var showingSessionModal = false
    @State private var stationRoad = ""
    @State private var barangay = ""
    @State private var city = ""
    @State private var directionFrom = ""
    @State private var directionTo = ""
    @State private var sessionDate = Date()
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var hasMedian = false
    @State private var numberOfLanes = 2
    
    let userId: Int
    let userName: String
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Add Button and Start Session Button
            HStack {
                Text("Camera View")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Start Session Button
//                Button(action: {
//                    showingSessionModal = true
//                }) {
//                    HStack(spacing: 8) {
//                        Image(systemName: "play.circle.fill")
//                            .font(.system(size: 14, weight: .medium))
//                        Text("Start Session")
//                            .font(.system(size: 14, weight: .medium))
//                    }
//                    .foregroundColor(.primary)
//                    .padding(.horizontal, 12)
//                    .padding(.vertical, 6)
//                    .background(
//                        Capsule()
//                            .fill(Color(.windowBackgroundColor).opacity(0.8))
//                    )
//                    .overlay(
//                        Capsule()
//                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
//                    )
//                }
//                .buttonStyle(.plain)
                
                // Add Camera Button
                Button(action: {
                    showingAddCameraSheet = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                        Text("Add Camera")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(.windowBackgroundColor).opacity(0.8))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            // Main Content: Sidebar + Feed
            HStack(spacing: 0) {
                // Left Sidebar - Camera List
                CameraListSidebar(cameras: $cameras, selectedCamera: $selectedCamera)
                
                Divider()
                
                // Right Side - Camera Feed
                if let selectedCamera = selectedCamera {
                    CameraFeedView(selectedCamera: .constant(selectedCamera), userId: userId, userName: userName)
                        .id(selectedCamera.id)  // Keep this - it's fine
                } else {
                    VStack {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("Select a camera or tap + to add one")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            loadCameras()
            if cameras.isEmpty == false && selectedCamera == nil {
                selectedCamera = cameras.first
            }
        }
        .sheet(isPresented: $showingAddCameraSheet) {
            AddCameraSheet(
                newCameraName: $newCameraName,
                newCameraIP: $newCameraIP,
                newCameraUsername: $newCameraUsername,
                newCameraPassword: $newCameraPassword,
                isTestingConnection: $isTestingConnection,
                connectionStatus: $connectionStatus,
                isConnectionSuccessful: $isConnectionSuccessful,
                onSave: {
                    saveCamera()
                    showingAddCameraSheet = false
                },
                onTest: {
                    testConnection()
                }
            )
        }
        .sheet(isPresented: $showingSessionModal) {
            SessionModalSheet(
                isPresented: $showingSessionModal,
                stationRoad: $stationRoad,
                barangay: $barangay,
                city: $city,
                directionFrom: $directionFrom,
                directionTo: $directionTo,
                sessionDate: $sessionDate,
                startTime: $startTime,
                endTime: $endTime,
                hasMedian: $hasMedian,
                numberOfLanes: $numberOfLanes,
                selectedCamera: $selectedCamera,
                cameras: cameras,
                onStartSession: { sessionCode in
                    // RESET FIELDS HERE
                    stationRoad = ""
                    barangay = ""
                    city = ""
                    directionFrom = ""
                    directionTo = ""
                    sessionDate = Date()
                    startTime = Date()
                    endTime = Date()
                    hasMedian = false
                    numberOfLanes = 2
                    selectedCamera = nil
                    showingSessionModal = false
                    print("Session started with code: \(sessionCode)")
                },
                userId: userId  // Move this after onStartSession
            )
        }
    }
    
    func loadCameras() {
        // Try to load from savedCamerasData first
        if savedCamerasData.count > 0,
           let decoded = try? JSONDecoder().decode([Camera].self, from: savedCamerasData) {
            cameras = decoded
            return
        }
        
        // Legacy: Load default camera from individual UserDefaults keys
        let defaults = UserDefaults.standard
        if let name = defaults.string(forKey: "saved_camera_name"),
           let ip = defaults.string(forKey: "saved_camera_ip"),
           let username = defaults.string(forKey: "saved_camera_username"),
           let password = defaults.string(forKey: "saved_camera_password") {
            cameras = [Camera(name: name, ip: ip, username: username, password: password)]
            saveCamerasToStorage()
        } else {
            cameras = []
        }
    }
    
    func saveCamerasToStorage() {
        if let encoded = try? JSONEncoder().encode(cameras) {
            savedCamerasData = encoded
        }
    }
    
    func saveCamera() {
        // Check for duplicate camera name
        if cameras.contains(where: { $0.name.lowercased() == newCameraName.lowercased() }) {
            let alert = NSAlert()
            alert.messageText = "Duplicate Camera Name"
            alert.informativeText = "A camera with the name '\(newCameraName)' already exists. Please use a unique name."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Check for duplicate IP address
        if cameras.contains(where: { $0.ip == newCameraIP }) {
            let alert = NSAlert()
            alert.messageText = "Duplicate IP Address"
            alert.informativeText = "A camera with the IP address '\(newCameraIP)' already exists. Please use a unique IP address."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        
        // Create and save the camera
        let newCamera = Camera(
            name: newCameraName,
            ip: newCameraIP,
            username: newCameraUsername,
            password: newCameraPassword
        )
        cameras.append(newCamera)
        saveCamerasToStorage()
        
        // Select the new camera
        selectedCamera = newCamera
        
        // Post notification to refresh feed
        NotificationCenter.default.post(name: NSNotification.Name("RefreshCameraFeed"), object: nil)
        
        clearCameraForm()
    }
    
    func clearCameraForm() {
        newCameraName = ""
        newCameraIP = ""
        newCameraUsername = "admin"
        newCameraPassword = ""
        connectionStatus = nil
        isConnectionSuccessful = false
    }
    
    func testConnection() {
        // Check if IP already exists
        if cameras.contains(where: { $0.ip == newCameraIP }) {
            connectionStatus = "This IP address is already in use by another camera."
            isConnectionSuccessful = false
            return
        }
        
        isTestingConnection = true
        connectionStatus = "Testing RTSP connection with provided credentials..."
        isConnectionSuccessful = false
        
        let rtspURL = "rtsp://\(newCameraUsername):\(newCameraPassword)@\(newCameraIP)/Streaming/Channels/101"
        
        DispatchQueue.global(qos: .background).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            task.arguments = [
                "-rtsp_transport", "tcp",
                "-i", rtspURL,
                "-frames:v", "1",
                "-f", "null",
                "-"
            ]
            
            let pipe = Pipe()
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    isTestingConnection = false
                    if task.terminationStatus == 0 {
                        connectionStatus = "RTSP connection successful! Camera is reachable with these credentials."
                        isConnectionSuccessful = true
                    } else {
                        connectionStatus = "RTSP connection failed. Check username, password, and IP address."
                        isConnectionSuccessful = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isTestingConnection = false
                    connectionStatus = "Connection test failed: \(error.localizedDescription)"
                    isConnectionSuccessful = false
                }
            }
        }
    }
}

// MARK: - Add Camera Sheet
struct AddCameraSheet: View {
    @Binding var newCameraName: String
    @Binding var newCameraIP: String
    @Binding var newCameraUsername: String
    @Binding var newCameraPassword: String
    @Binding var isTestingConnection: Bool
    @Binding var connectionStatus: String?
    @Binding var isConnectionSuccessful: Bool
    @Environment(\.dismiss) var dismiss
    
    @State private var showCloseAlert = false
    
    let onSave: () -> Void
    let onTest: () -> Void
    
    var hasInput: Bool {
        return !newCameraName.isEmpty || !newCameraIP.isEmpty ||
               newCameraUsername != "admin" || !newCameraPassword.isEmpty
    }
    
    var isTestConnectionValid: Bool {
        !newCameraName.isEmpty && !newCameraIP.isEmpty && !newCameraUsername.isEmpty && !newCameraPassword.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add Camera")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Enter your camera details to connect")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    if hasInput {
                        showCloseAlert = true
                    } else {
                        dismiss()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)
            
            Divider()
                .padding(.horizontal, 24)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Camera Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("e.g., Main Gate Camera", text: $newCameraName)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("IP Address")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    TextField("192.168.1.100", text: $newCameraIP)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                }
                
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        TextField("admin", text: $newCameraUsername)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        SecureField("••••••••", text: $newCameraPassword)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
                
                if let status = connectionStatus {
                    HStack {
                        Image(systemName: isConnectionSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(isConnectionSuccessful ? .green : .red)
                        Text(status)
                            .font(.caption)
                            .foregroundColor(isConnectionSuccessful ? .green : .red)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            Spacer(minLength: 20)
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Test Connection") {
                    onTest()
                }
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isTestConnectionValid ? Color.blue.opacity(0.9) : Color.gray.opacity(0.5))
                )
                .foregroundColor(.white)
                .buttonStyle(.plain)
                .disabled(!isTestConnectionValid)

                Button("Add Camera") {
                    onSave()
                    dismiss()
                }
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isConnectionSuccessful ? Color.green.opacity(0.9) : Color.gray.opacity(0.5))
                )
                .foregroundColor(isConnectionSuccessful ? .white : .secondary)
                .buttonStyle(.plain)
                .disabled(!isConnectionSuccessful)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 500, height: 450)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 20)
        )
        .alert("Discard Changes?", isPresented: $showCloseAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                clearForm()
                dismiss()
            }
        } message: {
            Text("You have entered camera details. If you close now, all your input will be lost.")
        }
    }
    
    func clearForm() {
        newCameraName = ""
        newCameraIP = ""
        newCameraUsername = "admin"
        newCameraPassword = ""
        connectionStatus = nil
        isConnectionSuccessful = false
    }
}

#Preview {
    CameraView(userId: 1, userName: "Preview User")
}
