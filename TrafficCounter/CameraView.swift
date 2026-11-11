//
//  CameraView.swift
//  TrafficCounter
//

import SwiftUI
import Combine

struct CameraView: View {
    @StateObject private var cameraHandler = PythonCameraHandler()
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
    @State private var cameraPollingTimer: Timer?
    
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
    @ObservedObject var sessionCoordinator: AutoSessionCoordinator
    
    @Binding var activeSchedule: [String: Any]?
    @Binding var scheduledSessionCode: String
    @Binding var shouldMaintainFeed: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Add Button and Start Session Button
            HStack {
                Text("Camera View")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
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
            
            // A single workspace surface keeps the camera list, preview, and
            // live information visually continuous in both appearances.
            HStack(alignment: .top, spacing: 16) {
                CameraListSidebar(cameras: $cameras, selectedCamera: $selectedCamera)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                if let selectedCamera = selectedCamera {
                    CameraFeedView(
                        cameraHandler: cameraHandler,
                        sessionCoordinator: sessionCoordinator,
                        selectedCamera: .constant(selectedCamera),
                        activeSchedule: $activeSchedule,          // <--- ADD THIS
                        scheduledSessionCode: $scheduledSessionCode, // <--- ADD THIS
                        shouldMaintainFeed: $shouldMaintainFeed,
                        userId: userId,
                        userName: userName
                    )
                    .id(selectedCamera.id)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
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
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Force the camera state to true so the feed starts when the app opens
            AppState.shared.isCameraEnabled = true
            
            // Initial load
            loadCameras()
            if cameras.isEmpty == false && selectedCamera == nil {
                selectedCamera = cameras.first
            }
            
            fetchCamerasFromSupabase()
            
            // Keep one cancellable poller while this screen is visible.
            cameraPollingTimer?.invalidate()
            cameraPollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                fetchCamerasFromSupabase()
            }
        }
        .onDisappear {
            cameraPollingTimer?.invalidate()
            cameraPollingTimer = nil
        }
        .onChange(of: sessionCoordinator.activeSession?.cameraId) { _, cameraID in
            guard let cameraID,
                  let assigned = cameras.first(where: { $0.remoteId == cameraID }) else { return }
            selectCameraIfNeeded(assigned)
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
    }
    
    func fetchCamerasFromSupabase() {
        SupabaseManager.shared.fetchCameras { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let remoteCameras):
                    let localCameras = remoteCameras.map { remote in
                        let savedPassword = UserDefaults.standard.string(forKey: "password_\(remote.id)") ?? "admin"
                        
                        return Camera(
                            name: remote.name,
                            remoteId: remote.id,
                            ip: remote.ip_address ?? "",
                            username: "admin",
                            password: savedPassword
                        )
                    }
                    
                    // Only update the UI if the data actually changed (prevents video feed from restarting)
                    let hasChanged = localCameras.count != self.cameras.count ||
                                     zip(localCameras, self.cameras).contains(where: {
                                         $0.remoteId != $1.remoteId || $0.name != $1.name
                                     })
                    
                    if hasChanged {
                        self.cameras = localCameras
                        self.saveCamerasToStorage()
                        
                        // If the currently selected camera was deleted, reset it
                        if let selected = self.selectedCamera, !localCameras.contains(where: { $0.id == selected.id }) {
                            self.selectedCamera = localCameras.first
                        } else if self.selectedCamera == nil {
                            self.selectedCamera = localCameras.first
                        }
                    }

                    if let assignedID = self.sessionCoordinator.activeSession?.cameraId,
                       let assigned = localCameras.first(where: { $0.remoteId == assignedID }) {
                        self.selectCameraIfNeeded(assigned)
                    }
                    
                case .failure(let error):
                    print("❌ Failed to fetch cameras from Supabase: \(error.localizedDescription)")
                }
            }
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

    /// Remote camera polling creates fresh value objects. Do not replace the
    /// selected camera with an equivalent value: CameraFeedView is keyed by
    /// its UUID, and replacing it would tear down the RTSP process during an
    /// active session every time the website poll completes.
    private func selectCameraIfNeeded(_ candidate: Camera) {
        guard let current = selectedCamera else {
            selectedCamera = candidate
            return
        }
        let hasConnectionChange = current.remoteId != candidate.remoteId ||
            current.name != candidate.name ||
            current.ip != candidate.ip ||
            current.username != candidate.username ||
            current.password != candidate.password
        if hasConnectionChange {
            selectedCamera = candidate
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
        
        // 1. Save to Supabase first
        SupabaseManager.shared.saveCamera(name: newCameraName, ip: newCameraIP) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let savedCam):
                    print("✅ Successfully saved to Supabase! ID: \(savedCam.id)")
                    
                    // 1. Save the REAL password locally so the feed works
                    UserDefaults.standard.set(newCameraPassword, forKey: "password_\(savedCam.id)")
                    
                    // 2. Save locally for the UI
                    let newCamera = Camera(
                        name: newCameraName,
                        remoteId: savedCam.id,
                        ip: newCameraIP,
                        username: newCameraUsername,
                        password: newCameraPassword
                    )
                    cameras.append(newCamera)
                    saveCamerasToStorage()
                    
                    selectedCamera = newCamera
                    NotificationCenter.default.post(name: NSNotification.Name("RefreshCameraFeed"), object: nil)
                    clearCameraForm()
                    
                case .failure(let error):
                    print("❌ Failed to save to Supabase: \(error.localizedDescription)")
                    
                    // Show an alert on screen
                    let alert = NSAlert()
                    alert.messageText = "Database Error"
                    alert.informativeText = "Could not save camera to Supabase. Check the Xcode console for details."
                    alert.alertStyle = .critical
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
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
        // 1. Check if IP already exists
        if cameras.contains(where: { $0.ip == newCameraIP }) {
            connectionStatus = "This IP address is already in use by another camera."
            isConnectionSuccessful = false
            return
        }
        
        isTestingConnection = true
        connectionStatus = "Testing RTSP connection & credentials..."
        isConnectionSuccessful = false
        
        let rtspURL = "rtsp://\(newCameraUsername):\(newCameraPassword)@\(newCameraIP)/Streaming/Channels/101"
        
        // 2. We use /bin/bash to find ffmpeg, so it doesn't matter where it is installed
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        // We wrap the command in quotes. We use -timeout instead of -stimeout for modern ffmpeg.
        let command = "/opt/homebrew/bin/ffmpeg -rtsp_transport tcp -timeout 3000000 -i '\(rtspURL)' -frames:v 1 -f null - || /usr/local/bin/ffmpeg -rtsp_transport tcp -timeout 3000000 -i '\(rtspURL)' -frames:v 1 -f null -"
        
        task.arguments = ["-c", command]
        
        let pipe = Pipe()
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            isTestingConnection = false
            
            if task.terminationStatus == 0 {
                connectionStatus = "RTSP connection successful! Camera is reachable."
                isConnectionSuccessful = true
            } else {
                // If it fails, we print the error to the console so you can see WHY
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                print("FFmpeg Test Failed Output:\n\(output)")
                
                connectionStatus = "RTSP connection failed. Check username, password, and IP."
                isConnectionSuccessful = false
            }
        } catch {
            isTestingConnection = false
            connectionStatus = "Test failed: Could not run ffmpeg."
            isConnectionSuccessful = false
            print("Process error: \(error)")
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
                        .fill(Color.green.opacity(0.9))
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
    CameraView(
        userId: 1,
        userName: "Preview User",
        sessionCoordinator: AutoSessionCoordinator(),
        activeSchedule: .constant(nil),
        scheduledSessionCode: .constant(""),
        shouldMaintainFeed: .constant(false)
    )
}
