//
//  CameraListSidebar.swift
//  TrafficCounter
//

import SwiftUI

struct CameraListSidebar: View {
    @Binding var cameras: [Camera]
    @Binding var selectedCamera: Camera?
    
    @State private var activeMenuCamera: UUID? = nil
    @State private var showingDeleteAlert = false
    @State private var cameraToDelete: Camera?
    @State private var editingCamera: Camera?
    @State private var editingLineCamera: Camera?
    
    @State private var hoveringCameraId: UUID?
    
    var body: some View {
        Group {
            VStack(alignment: .leading, spacing: 8) {
                Text("CAMERAS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(cameras) { camera in
                            ZStack(alignment: .topTrailing) {
                                HStack(spacing: 8) {
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(selectedCamera?.id == camera.id ? .blue : .secondary)
                                        .frame(width: 20)
                                    
                                    Button(action: {
                                        selectedCamera = camera
                                        activeMenuCamera = nil
                                    }) {
                                        Text(camera.name)
                                            .font(.body)
                                            .foregroundColor(selectedCamera?.id == camera.id ? .primary : .secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        withAnimation {
                                            activeMenuCamera = (activeMenuCamera == camera.id) ? nil : camera.id
                                        }
                                    }) {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Rectangle()
                                        .fill(selectedCamera?.id == camera.id ? Color.blue.opacity(0.15) :
                                              (hoveringCameraId == camera.id ? Color.gray.opacity(0.1) : Color.clear))
                                )
                                .onHover { isHovering in
                                    hoveringCameraId = isHovering ? camera.id : nil
                                }
                                .contextMenu {
                                    Button("Edit Counting Line") { editingLineCamera = camera }
                                    Button("Edit Camera Name") { editingCamera = camera }
                                    Button("Delete Camera", role: .destructive) {
                                        cameraToDelete = camera
                                        showingDeleteAlert = true
                                    }
                                }

                                if activeMenuCamera == camera.id {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Button("Edit Counting Line") {
                                            editingLineCamera = camera
                                            activeMenuCamera = nil
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .buttonStyle(.plain)
                                        
                                        Button("Edit Camera Name") {
                                            editingCamera = camera
                                            activeMenuCamera = nil
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .buttonStyle(.plain)
                                        
                                        Divider()
                                        
                                        Button("Delete Camera") {
                                            cameraToDelete = camera
                                            showingDeleteAlert = true
                                            activeMenuCamera = nil
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .foregroundColor(.red)
                                        .buttonStyle(.plain)
                                    }
                                    .frame(width: 160)
                                    .background(.regularMaterial)
                                    .cornerRadius(8)
                                    .shadow(radius: 5)
                                    .padding(.top, 30)
                                    .padding(.trailing, 10)
                                    .zIndex(1)
                                }
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.horizontal, 8)
                }
                
                Spacer()
            }
        }
        .frame(width: 220)
        .background(Color.clear)
        .onTapGesture {
            if activeMenuCamera != nil { activeMenuCamera = nil }
        }
        .alert("Delete Camera?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let camera = cameraToDelete { deleteCamera(camera) }
            }
        } message: {
            if let camera = cameraToDelete {
                Text("Are you sure you want to delete \"\(camera.name)\"? This action cannot be undone.")
            }
        }
        .sheet(item: $editingCamera) { camera in
            EditCameraSheet(
                cameraName: camera.name,
                onSave: { newName in editCameraName(camera, newName: newName) }
            )
        }
        .sheet(item: $editingLineCamera) { camera in
            EditLineSheet(camera: camera)
        }
    }
    
    func deleteCamera(_ camera: Camera) {
        if let remoteId = camera.remoteId {
            SupabaseManager.shared.deleteCamera(id: remoteId) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(): print("✅ Deleted from Supabase successfully")
                    case .failure(let error): print("❌ Failed to delete: \(error.localizedDescription)")
                    }
                    self.removeCameraLocally(camera)
                }
            }
        } else {
            removeCameraLocally(camera)
        }
    }
    
    private func removeCameraLocally(_ camera: Camera) {
        cameras.removeAll { $0.id == camera.id }
        saveCamerasToStorage()
        if selectedCamera?.id == camera.id { selectedCamera = cameras.first }
    }
    
    func editCameraName(_ camera: Camera, newName: String) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            if let remoteId = camera.remoteId {
                SupabaseManager.shared.updateCamera(id: remoteId, newName: newName) { result in
                    DispatchQueue.main.async {
                        self.updateLocalCameraName(index: index, newName: newName)
                    }
                }
            } else {
                updateLocalCameraName(index: index, newName: newName)
            }
        }
    }
    
    private func updateLocalCameraName(index: Int, newName: String) {
        cameras[index].name = newName
        saveCamerasToStorage()
        if selectedCamera?.id == cameras[index].id { selectedCamera = cameras[index] }
    }
    
    func saveCamerasToStorage() {
        if let encoded = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(encoded, forKey: "savedCameras")
        }
    }
}

// MARK: - Edit Camera Name Sheet
struct EditCameraSheet: View {
    @Environment(\.dismiss) var dismiss
    let cameraName: String
    let onSave: (String) -> Void
    @State private var newName: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Camera Name").font(.title).fontWeight(.semibold)
                    Text("Enter a new name for this camera").font(.callout).foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.secondary)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 20)
            
            Divider().padding(.horizontal, 24)
            
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CAMERA NAME").font(.caption).fontWeight(.medium).foregroundColor(.secondary)
                    TextField("e.g., Main Gate Camera", text: $newName)
                        .textFieldStyle(.plain).padding(12).background(Color.gray.opacity(0.1)).cornerRadius(10)
                        .onAppear { newName = cameraName }
                }
            }
            .padding(.horizontal, 24).padding(.top, 24)
            
            Spacer(minLength: 20)
            
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(.body).fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Capsule().fill(Color.gray.opacity(0.5))).foregroundColor(.white).buttonStyle(.plain)
                
                Button("Save") {
                    if !newName.isEmpty { onSave(newName); dismiss() }
                }
                .font(.body).fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
                .background(Capsule().fill(newName.isEmpty ? Color.gray.opacity(0.5) : Color.green.opacity(0.9)))
                .foregroundColor(.white).buttonStyle(.plain).disabled(newName.isEmpty)
            }
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
        .frame(width: 400, height: 250).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Edit Counting Line Sheet
struct EditLineSheet: View {
    @Environment(\.dismiss) var dismiss
    let camera: Camera
    
    @State private var linePosition: Double
    @State private var lineAngle: Double
    
    init(camera: Camera) {
        self.camera = camera
        let savedPos = UserDefaults.standard.double(forKey: "line_position_\(camera.ip)")
        _linePosition = State(initialValue: savedPos == 0 ? 0.7 : savedPos)
        
        let savedAngle = UserDefaults.standard.double(forKey: "line_angle_\(camera.ip)")
        _lineAngle = State(initialValue: savedAngle)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Adjust Counting Line")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Move the sliders to position and rotate the red line. Vehicles crossing above and to the left of this line will be counted.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading) // Changed to leading
                .fixedSize(horizontal: false, vertical: true) // Allows text to wrap properly
            
            // 1. Position Slider
            VStack(alignment: .leading, spacing: 8) {
                Text("Position: \(Int(linePosition * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $linePosition, in: 0.1...0.9, onEditingChanged: { _ in
                    PythonCameraHandler().updateCountingLine(position: linePosition)
                })
            }
            
            // 2. Rotation Slider
            VStack(alignment: .leading, spacing: 8) {
                Text("Rotation: \(Int(lineAngle))°")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Slider(value: $lineAngle, in: -90...90, onEditingChanged: { _ in
                    PythonCameraHandler().updateCountingAngle(angle: lineAngle)
                })
            }
            
            // Buttons aligned to the right
            HStack(spacing: 12) {
                Spacer() // Pushes buttons to the right
                
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(8)
                
                Button("Save") {
                    UserDefaults.standard.set(linePosition, forKey: "line_position_\(camera.ip)")
                    UserDefaults.standard.set(lineAngle, forKey: "line_angle_\(camera.ip)")
                    
                    let handler = PythonCameraHandler()
                    handler.updateCountingLine(position: linePosition)
                    handler.updateCountingAngle(angle: lineAngle)
                    
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.top, 10)
        }
        .padding(24)
        .frame(width: 380) // Slightly widened to accommodate left-aligned text nicely
    }
}
