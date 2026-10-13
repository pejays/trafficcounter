//
//  SessionsView.swift
//  TrafficCounter
//

import SwiftUI

struct SessionsView: View {
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var toDate = Date()
    @State private var selectedCamera: Camera?
    @State private var hasMedian: Bool?
    @State private var numberOfLanes: Int?
    @State private var startTime: Date?
    @State private var endTime: Date?
    
    // Sample sessions data
    @State private var sessions: [SessionItem] = []
    
    var filteredSessions: [SessionItem] {
        var filtered = sessions
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.stationRoad.localizedCaseInsensitiveContains(searchText) ||
                $0.barangay.localizedCaseInsensitiveContains(searchText) ||
                $0.directionFrom.localizedCaseInsensitiveContains(searchText) ||
                $0.directionTo.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Date range filter
        filtered = filtered.filter {
            $0.date >= fromDate && $0.date <= toDate
        }
        
        // Camera filter
        if let camera = selectedCamera {
            filtered = filtered.filter { $0.cameraName == camera.name }
        }
        
        // Has median filter
        if let median = hasMedian {
            filtered = filtered.filter { $0.hasMedian == median }
        }
        
        // Number of lanes filter
        if let lanes = numberOfLanes {
            filtered = filtered.filter { $0.numberOfLanes == lanes }
        }
        
        // Time filters
        if let start = startTime {
            filtered = filtered.filter { $0.startTime >= start }
        }
        if let end = endTime {
            filtered = filtered.filter { $0.endTime <= end }
        }
        
        return filtered.sorted { $0.date > $1.date }
    }
    
    var hasActiveFilters: Bool {
        fromDate != Calendar.current.date(byAdding: .day, value: -30, to: Date()) ||
        toDate != Date() ||
        selectedCamera != nil ||
        hasMedian != nil ||
        numberOfLanes != nil ||
        startTime != nil ||
        endTime != nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Title and Search Bar
            HStack {
                Text("Sessions")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search by station, barangay, direction...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .frame(width: 300)
                
                // Filter Button
                Button(action: {
                    showingFilters.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 14))
                        Text("Filter")
                            .font(.system(size: 14, weight: .medium))
                        if hasActiveFilters {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingFilters) {
                    FilterPopover(
                        fromDate: $fromDate,
                        toDate: $toDate,
                        selectedCamera: $selectedCamera,
                        hasMedian: $hasMedian,
                        numberOfLanes: $numberOfLanes,
                        startTime: $startTime,
                        endTime: $endTime,
                        cameras: sampleCameras,
                        onClear: {
                            fromDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
                            toDate = Date()
                            selectedCamera = nil
                            hasMedian = nil
                            numberOfLanes = nil
                            startTime = nil
                            endTime = nil
                        }
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 12)
            
            Divider()
            
            // Sessions List
            ScrollView {
                if filteredSessions.isEmpty {
                    VStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                            .padding(.top, 100)
                        Text("No sessions found")
                            .font(.title3)
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                        Text("Start a session to see recorded counts")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(filteredSessions) { session in
                            SessionCard(session: session)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter Popover
struct FilterPopover: View {
    @Binding var fromDate: Date
    @Binding var toDate: Date
    @Binding var selectedCamera: Camera?
    @Binding var hasMedian: Bool?
    @Binding var numberOfLanes: Int?
    @Binding var startTime: Date?
    @Binding var endTime: Date?
    
    let cameras: [Camera]
    let onClear: () -> Void
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    onClear()
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                )
                .foregroundColor(.blue)
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
            
            Divider()
            
            // Date Range
            VStack(alignment: .leading, spacing: 8) {
                Text("DATE RANGE")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                HStack {
                    DatePicker("From", selection: $fromDate, displayedComponents: .date)
                        .labelsHidden()
                    Text("to")
                    DatePicker("To", selection: $toDate, displayedComponents: .date)
                        .labelsHidden()
                }
            }
            
            Divider()
            
            // Camera
            VStack(alignment: .leading, spacing: 8) {
                Text("CAMERA")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $selectedCamera) {
                    Text("All Cameras").tag(nil as Camera?)
                    ForEach(cameras) { camera in
                        Text(camera.name).tag(camera as Camera?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Divider()
            
            // Has Median
            VStack(alignment: .leading, spacing: 8) {
                Text("HAS MEDIAN?")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $hasMedian) {
                    Text("All").tag(nil as Bool?)
                    Text("Yes").tag(true as Bool?)
                    Text("No").tag(false as Bool?)
                }
                .pickerStyle(.segmented)
            }
            
            Divider()
            
            // Number of Lanes
            VStack(alignment: .leading, spacing: 8) {
                Text("NUMBER OF LANES")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                HStack {
                    Stepper("", value: Binding(
                        get: { numberOfLanes ?? 2 },
                        set: { numberOfLanes = $0 }
                    ), in: 1...10)
                    .labelsHidden()
                    
                    Text("\(numberOfLanes ?? 2) lanes")
                        .font(.body)
                }
                
                if numberOfLanes != nil {
                    Button("Clear") {
                        numberOfLanes = nil
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.gray.opacity(0.2))
                    )
                    .foregroundColor(.blue)
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            // Time Range
            VStack(alignment: .leading, spacing: 8) {
                Text("TIME RANGE")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                HStack {
                    DatePicker("Start", selection: Binding(
                        get: { startTime ?? Date() },
                        set: { startTime = $0 }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    
                    Text("to")
                    
                    DatePicker("End", selection: Binding(
                        get: { endTime ?? Date() },
                        set: { endTime = $0 }
                    ), displayedComponents: .hourAndMinute)
                    .labelsHidden()
                }
            }
            
            Spacer(minLength: 20)
            
            Button("Apply Filters") {
                dismiss()
            }
            .font(.body)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(Color.blue)
            )
            .foregroundColor(.white)
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(width: 320)
        .background(.regularMaterial)
    }
}

// MARK: - Session Card
struct SessionCard: View {
    let session: SessionItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.stationRoad)
                        .font(.headline)
                    Text("\(session.barangay), \(session.city)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text("\(Int(session.totalPCU)) PCU")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(pcuColor(session.totalPCU))
                
                Text(session.los)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(losColor(session.los))
                    .cornerRadius(6)
            }
            
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(formatDate(session.date))
                    .font(.caption)
                
                Image(systemName: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                Text("\(session.startTimeString) - \(session.endTimeString)")
                    .font(.caption)
            }
            
            HStack {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("From: \(session.directionFrom) → To: \(session.directionTo)")
                    .font(.caption)
            }
            
            HStack(spacing: 16) {
                VehicleBadge(icon: "car", count: session.vehicleCounts["Private Car"] ?? 0)
                VehicleBadge(icon: "motorcycle", count: session.vehicleCounts["Motorcycle"] ?? 0)
                VehicleBadge(icon: "bus", count: session.vehicleCounts["Jeepney"] ?? 0)
                VehicleBadge(icon: "truck", count: (session.vehicleCounts["Light Truck"] ?? 0) + (session.vehicleCounts["Heavy Truck"] ?? 0))
            }
            
            Divider()
            
            HStack {
                Button("View Report") {
                    // Show detail view
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.blue)
                
                Spacer()
                
                Button("Export") {
                    // Export session
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundColor(.green)
            }
        }
        .padding(16)
        .background(Color.gray.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }
    
    func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    func pcuColor(_ pcu: Double) -> Color {
        if pcu < 200 { return .green }
        if pcu < 400 { return .yellow }
        if pcu < 600 { return .orange }
        return .red
    }
    
    func losColor(_ los: String) -> Color {
        switch los {
        case "A", "B": return .green
        case "C": return .yellow
        case "D": return .orange
        case "E", "F": return .red
        default: return .gray
        }
    }
}

// MARK: - Vehicle Badge
struct VehicleBadge: View {
    let icon: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text("\(count)")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.secondary)
    }
}

// MARK: - Models
struct SessionItem: Identifiable {
    let id = UUID()
    let stationRoad: String
    let barangay: String
    let city: String
    let directionFrom: String
    let directionTo: String
    let date: Date
    let startTime: Date
    let endTime: Date
    let startTimeString: String
    let endTimeString: String
    let hasMedian: Bool
    let numberOfLanes: Int
    let cameraName: String
    let vehicleCounts: [String: Int]
    let totalPCU: Double
    let los: String
}

// MARK: - Sample Data
let sampleCameras: [Camera] = [
    Camera(name: "Main Gate", ip: "192.168.1.64", username: "admin", password: "password"),
    Camera(name: "South Gate", ip: "192.168.1.65", username: "admin", password: "password")
]

#Preview {
    SessionsView()
}
