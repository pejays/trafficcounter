//
//  CameraFeedView.swift
//  TrafficCounter
//

import SwiftUI
import Combine
import Foundation

struct CameraFeedView: View {
    @StateObject private var cameraHandler = PythonCameraHandler()
    @StateObject private var appState = AppState.shared
    @State private var sessionTime = Date()
    @Binding var selectedCamera: Camera?
    
    let userId: Int
    let userName: String
    
    let pcuFactors: [String: Double] = [
        "Private Car": 1.0,
        "Motorcycle": 0.5,
        "Jeepney": 1.5,
        "Bus/Minibus": 2.5,
        "Light Truck": 2.0,
        "Heavy Truck": 3.0,
        "Tricycle": 0.7,
        "UV": 1.5
    ]
    
    var totalPCU: Double {
        var total = 0.0
        for (vehicle, count) in appState.vehicleCounts {
            total += Double(count) * (pcuFactors[vehicle] ?? 0)
        }
        return total
    }
    
    func startSession() {
        appState.isSessionActive = true
        sessionTime = Date()
        for (key, _) in appState.vehicleCounts {
            appState.vehicleCounts[key] = 0
        }
        print("Session started")
    }
    
    func stopSession() {
        appState.isSessionActive = false
        print("Session stopped. Final counts: \(appState.vehicleCounts)")
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Camera Feed
            if appState.isCameraEnabled {
                if let frame = cameraHandler.currentFrame {
                    Image(nsImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 400)
                        .background(Color.black)
                        .overlay(
                            Group {
                                if !cameraHandler.isConnected {
                                    ProgressView()
                                        .scaleEffect(1.5)
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color.black.opacity(0.7))
                                }
                            }
                        )
                } else {
                    Rectangle()
                        .fill(Color.black)
                        .frame(height: 400)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                Text("Connecting to camera...")
                                    .foregroundColor(.white)
                                    .font(.caption)
                                    .padding(.top, 10)
                            }
                        )
                }
            } else {
                // Camera manually disabled - show simple placeholder, no spinner
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 400)
                    .overlay(
                        VStack {
                            Image(systemName: "video.slash.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("Camera Disabled")
                                .foregroundColor(.gray)
                                .font(.title2)
                                .padding(.top, 10)
                        }
                    )
            }
            
            // Camera Control Row - Modern Right Aligned
            HStack {
                Spacer()
                
                if appState.isSessionActive {
                    Text("Session Active: \(sessionTime, style: .timer)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                // Disable/Enable Camera Button
                Button(action: toggleCamera) {
                    HStack(spacing: 6) {
                        Image(systemName: appState.isCameraEnabled ? "video.slash" : "video")
                            .font(.system(size: 12))
                        Text(appState.isCameraEnabled ? "Disable Camera" : "Enable Camera")
                            .font(.system(size: 13, weight: .medium))
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
            .padding(.vertical, 8)
            
            // Camera Status
            HStack {
                Circle()
                    .fill(cameraHandler.isConnected ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                Text(cameraHandler.isConnected ? "Camera Connected" : "Camera Disconnected")
                    .font(.caption)
            }
            .padding(.bottom, 5)
            
            // Vehicle Counts Table
            ScrollView {
            }
        }
        .onAppear {
            print("CameraFeedView appeared for: \(selectedCamera?.name ?? "nil")")
            
            // Listen for refresh notification
            NotificationCenter.default.addObserver(forName: NSNotification.Name("RefreshCameraFeed"), object: nil, queue: .main) { _ in
                if let camera = selectedCamera {
                    cameraHandler.saveCameraToUserDefaults(
                        name: camera.name,
                        ip: camera.ip,
                        username: camera.username,
                        password: camera.password
                    )
                    cameraHandler.startCamera()
                }
            }
            
            if let camera = selectedCamera {
                cameraHandler.saveCameraToUserDefaults(
                    name: camera.name,
                    ip: camera.ip,
                    username: camera.username,
                    password: camera.password
                )
                cameraHandler.startCamera()
            }
        }
        .onDisappear {
            print("CameraFeedView disappeared")
            cameraHandler.stopCamera()
            NotificationCenter.default.removeObserver(self, name: NSNotification.Name("RefreshCameraFeed"), object: nil)
        }
    }
    
    func toggleCamera() {
        if appState.isCameraEnabled {
            cameraHandler.stopCamera()
            appState.isCameraEnabled = false
        } else {
            cameraHandler.startCamera()
            appState.isCameraEnabled = true
        }
    }
}

// MARK: - Session Modal Sheet
struct SessionModalSheet: View {
    @Binding var isPresented: Bool
    @Binding var stationRoad: String
    @Binding var barangay: String
    @Binding var city: String
    @Binding var directionFrom: String
    @Binding var directionTo: String
    @Binding var sessionDate: Date
    @Binding var startTime: Date
    @Binding var endTime: Date
    @Binding var hasMedian: Bool
    @Binding var numberOfLanes: Int
    @Binding var selectedCamera: Camera?
    
    @State private var showDatePicker = false
    @State private var showMedianPicker = false
    @State private var showCameraPicker = false
    @State private var showStartTimePicker = false
    @State private var showEndTimePicker = false
    @State private var lanesText = "2"
    @State private var showCancelAlert = false
    
    @State private var showConfirmationAlert = false
    
    var isNumberOfLanesValid: Bool {
        let intValue = Int(lanesText) ?? 0
        return intValue >= 1 && intValue <= 10 && !lanesText.isEmpty
    }
    
    let cameras: [Camera]
    let onStartSession: (String) -> Void
    let userId: Int
    
    var isFormValid: Bool {
        !stationRoad.isEmpty &&
        !barangay.isEmpty &&
        !city.isEmpty &&
        !directionFrom.isEmpty &&
        !directionTo.isEmpty &&
        selectedCamera != nil &&
        isNumberOfLanesValid
    }
    
    var hasAnyInput: Bool {
        !stationRoad.isEmpty || !barangay.isEmpty || !city.isEmpty ||
        !directionFrom.isEmpty || !directionTo.isEmpty ||
        selectedCamera != nil ||
        sessionDate != Date() ||
        startTime != Date() ||
        endTime != Date() ||
        hasMedian != false ||
        numberOfLanes != 2
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Session")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Enter session details to start counting")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    if hasAnyInput {
                        showCancelAlert = true
                    } else {
                        isPresented = false
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
            
            // Form Fields
            ScrollView {
                VStack(spacing: 20) {
                    // Station / Road Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("STATION / ROAD NAME")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        TextField("e.g., DusUno Intersection", text: $stationRoad)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Barangay & Municipality
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("BARANGAY")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextField("o.g.,Poblacion", text: $barangay)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("CITY/MUNICIPALITY")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextField("e.g., Sto. Tomas", text: $city)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Direction From & To
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DIRECTION FROM")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextField("From:", text: $directionFrom)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DIRECTION TO")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            TextField("To:", text: $directionTo)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Date, Start Time, End Time
                    HStack(spacing: 16) {
                        // Date
                        VStack(alignment: .leading, spacing: 8) {
                            Text("DATE")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(formattedDate(sessionDate))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .onTapGesture {
                                showDatePicker.toggle()
                            }
                            .popover(isPresented: $showDatePicker) {
                                DatePicker("Select Date", selection: $sessionDate, displayedComponents: .date)
                                    .datePickerStyle(.graphical)
                                    .padding()
                                    .frame(width: 300)
                                    .background(.regularMaterial)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Start Time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("START TIME")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(formattedTime(startTime))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .onTapGesture {
                                        showStartTimePicker.toggle()
                                    }
                                
                                Spacer()
                                
                                Stepper("") {
                                    startTime = Calendar.current.date(byAdding: .minute, value: 15, to: startTime) ?? startTime
                                } onDecrement: {
                                    startTime = Calendar.current.date(byAdding: .minute, value: -15, to: startTime) ?? startTime
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .popover(isPresented: $showStartTimePicker) {
                                VStack {
                                    DatePicker("", selection: $startTime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.stepperField)
                                        .labelsHidden()
                                        .padding()
                                        .frame(width: 200)
                                }
                                .background(.regularMaterial)
                            }
                        }
                        .frame(maxWidth: .infinity)

                        // End Time
                        VStack(alignment: .leading, spacing: 8) {
                            Text("END TIME")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(formattedTime(endTime))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .onTapGesture {
                                        showEndTimePicker.toggle()
                                    }
                                
                                Spacer()
                                
                                Stepper("") {
                                    endTime = Calendar.current.date(byAdding: .minute, value: 15, to: endTime) ?? endTime
                                } onDecrement: {
                                    endTime = Calendar.current.date(byAdding: .minute, value: -15, to: endTime) ?? endTime
                                }
                                .labelsHidden()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .popover(isPresented: $showEndTimePicker) {
                                VStack {
                                    DatePicker("", selection: $endTime, displayedComponents: .hourAndMinute)
                                        .datePickerStyle(.stepperField)
                                        .labelsHidden()
                                        .padding()
                                        .frame(width: 200)
                                }
                                .background(.regularMaterial)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Has Median, Number of Lanes & Camera Selection
                    HStack(alignment: .top, spacing: 16) {
                        // Has Median
                        VStack(alignment: .leading, spacing: 8) {
                            Text("HAS MEDIAN?")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(hasMedian ? "With median (650 PCU/lane/hr)" : "No median (720 PCU/lane/hr)")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 14)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .onTapGesture {
                                showMedianPicker.toggle()
                            }
                            .popover(isPresented: $showMedianPicker) {
                                VStack(spacing: 0) {
                                    Button("No median (720 PCU/lane/hr)") {
                                        hasMedian = false
                                        showMedianPicker = false
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.clear)
                                    
                                    Divider()
                                    
                                    Button("With median (650 PCU/lane/hr)") {
                                        hasMedian = true
                                        showMedianPicker = false
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.clear)
                                }
                                .frame(width: 280)
                                .padding(.vertical, 4)
                                .background(.regularMaterial)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Number of Lanes
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NUMBER OF LANES")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("", text: $lanesText)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.leading)
                                    .onChange(of: lanesText) { newValue in
                                        let filtered = newValue.filter { "0123456789".contains($0) }
                                        if filtered != newValue {
                                            lanesText = filtered
                                        }
                                        if let intValue = Int(filtered), intValue >= 1, intValue <= 10 {
                                            numberOfLanes = intValue
                                            lanesText = filtered
                                        } else if filtered.isEmpty {
                                            numberOfLanes = 1
                                            lanesText = "1"
                                        }
                                    }
                                
                                Spacer()
                                
                                Stepper("", value: $numberOfLanes, in: 1...10)
                                    .labelsHidden()
                                    .onChange(of: numberOfLanes) { newValue in
                                        lanesText = "\(newValue)"
                                    }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(isNumberOfLanesValid ? Color.gray.opacity(0.1) : Color.red.opacity(0.2))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isNumberOfLanesValid ? Color.clear : Color.red, lineWidth: 1)
                            )
                            
                            if !isNumberOfLanesValid {
                                Text("Please enter a number between 1 and 10")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Camera Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("SELECT CAMERA")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(selectedCamera?.name ?? "Select a camera")
                                    .font(.body)
                                    .foregroundColor(selectedCamera != nil ? .primary : .secondary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 15)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                            .onTapGesture {
                                showCameraPicker.toggle()
                            }
                            .popover(isPresented: $showCameraPicker) {
                                VStack(spacing: 0) {
                                    Button("Select a camera") {
                                        selectedCamera = nil
                                        showCameraPicker = false
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.clear)
                                    
                                    if !cameras.isEmpty {
                                        Divider()
                                    }
                                    
                                    ForEach(cameras) { camera in
                                        Button(camera.name) {
                                            selectedCamera = camera
                                            showCameraPicker = false
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 10)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.clear)
                                        
                                        if camera.id != cameras.last?.id {
                                            Divider()
                                        }
                                    }
                                }
                                .frame(width: 250)
                                .padding(.vertical, 4)
                                .background(.regularMaterial)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .alert("Discard Changes?", isPresented: $showCancelAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Discard", role: .destructive) {
                        isPresented = false
                    }
                } message: {
                    Text("You have unsaved changes. Are you sure you want to discard them?")
                }
            }
            .frame(maxHeight: 500)
            
            Spacer(minLength: 10)
    
            // Action Buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    if hasAnyInput {
                        showCancelAlert = true
                    } else {
                        isPresented = false
                    }
                }
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.5))
                )
                .foregroundColor(.white)
                .buttonStyle(.plain)

                Button("Start Session") {
                    showConfirmationAlert = true
                }
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(isFormValid ? Color.green.opacity(0.9) : Color.gray.opacity(0.5))
                )
                .foregroundColor(.white)
                .buttonStyle(.plain)
                .disabled(!isFormValid)
                .alert("Confirm Session Details", isPresented: $showConfirmationAlert) {
                    Button("Cancel", role: .cancel) { }
                    Button("Start", role: .none) {
                        Task {
                            do {
                                try await DatabaseManager.shared.connect()
                                
                                let formatter = DateFormatter()
                                formatter.dateFormat = "yyyyMMddHHmmss"
                                let sessionCode = "S-\(formatter.string(from: Date()))"
                                
                                // Format dates for Asia/Manila timezone
                                let timeFormatter = DateFormatter()
                                timeFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                timeFormatter.timeZone = TimeZone(identifier: "Asia/Manila")
                                
                                let startDateTime = Calendar.current.date(
                                    bySettingHour: Calendar.current.component(.hour, from: startTime),
                                    minute: Calendar.current.component(.minute, from: startTime),
                                    second: 0,
                                    of: sessionDate
                                ) ?? startTime
                                
                                let endDateTime = Calendar.current.date(
                                    bySettingHour: Calendar.current.component(.hour, from: endTime),
                                    minute: Calendar.current.component(.minute, from: endTime),
                                    second: 0,
                                    of: sessionDate
                                ) ?? endTime
                                
                                let startTimeString = timeFormatter.string(from: startDateTime)
                                let endTimeString = timeFormatter.string(from: endDateTime)
                                
                                try await DatabaseManager.shared.saveSession(
                                    sessionCode: sessionCode,
                                    roadName: stationRoad,
                                    barangay: barangay,
                                    city: city,
                                    direction: "\(directionFrom) to \(directionTo)",
                                    lanes: numberOfLanes,
                                    hasMedian: hasMedian,
                                    startTime: startTimeString,
                                    endTime: endTimeString,
                                    createdBy: userId
                                )
                                
                                await DatabaseManager.shared.disconnect()
                                
                                await MainActor.run {
                                    onStartSession(sessionCode)
                                    isPresented = false
                                }
                            } catch {
                                await MainActor.run {
                                    print("❌ Failed to save session: \(error)")
                                }
                            }
                        }
                    }
                } message: {
                    Text("Please review your session details:\n\n📍 Station: \(stationRoad)\n📍 Barangay: \(barangay)\n📍 City: \(city)\n📍 Direction: \(directionFrom) → \(directionTo)\n📍 Camera: \(selectedCamera?.name ?? "None")\n📍 Lanes: \(numberOfLanes)\n📍 Median: \(hasMedian ? "Yes" : "No")\n📍 Time: \(formattedTime(startTime)) - \(formattedTime(endTime))\n\nAre these correct?")
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 750, height: 600)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
    
    func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }

    func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}
