//
//  CameraListSidebar.swift
//  TrafficCounter
//

import SwiftUI

struct CameraListSidebar: View {
    @Binding var cameras: [Camera]
    @Binding var selectedCamera: Camera?
    @State private var showingDeleteAlert = false
    @State private var showingEditSheet = false
    @State private var cameraToDelete: Camera?
    @State private var cameraToEdit: Camera?
    @State private var editingCamera: Camera?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CAMERAS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 16)
            
            ForEach(cameras) { camera in
                HStack(spacing: 8) {
                    // Camera Icon
                    Image(systemName: "camera.fill")
                        .font(.system(size: 14))
                        .foregroundColor(selectedCamera?.id == camera.id ? .blue : .secondary)
                        .frame(width: 20)
                    
                    // Camera Name Button
                    Button(action: {
                        selectedCamera = camera
                    }) {
                        Text(camera.name)
                            .font(.body)
                            .foregroundColor(selectedCamera?.id == camera.id ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    
                    // Three dots button
                    Menu {
                        Button("Edit Camera Name") {
                            editingCamera = camera
                        }
                        
                        Button("Delete Camera", role: .destructive) {
                            cameraToDelete = camera
                            showingDeleteAlert = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedCamera?.id == camera.id ? Color.blue.opacity(0.1) : Color.clear)
                )
                .contextMenu {
                    Button("Edit Camera Name") {
                        editingCamera = camera
                    }
                    Button("Delete Camera", role: .destructive) {
                        cameraToDelete = camera
                        showingDeleteAlert = true
                    }
                }
            }
            
            Spacer()
        }
        .frame(width: 220)
        .background(Color.gray.opacity(0.05))
        .alert("Delete Camera?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let camera = cameraToDelete {
                    deleteCamera(camera)
                }
            }
        } message: {
            if let camera = cameraToDelete {
                Text("Are you sure you want to delete \"\(camera.name)\"? This action cannot be undone.")
            }
        }
        .sheet(item: $editingCamera) { camera in
            EditCameraSheet(
                cameraName: camera.name,
                onSave: { newName in
                    editCameraName(camera, newName: newName)
                }
            )
        }
    }
    
    func deleteCamera(_ camera: Camera) {
        cameras.removeAll { $0.id == camera.id }
        saveCamerasToStorage()
        
        if selectedCamera?.id == camera.id {
            selectedCamera = cameras.first
        }
    }
    
    func editCameraName(_ camera: Camera, newName: String) {
        if let index = cameras.firstIndex(where: { $0.id == camera.id }) {
            cameras[index].name = newName
            saveCamerasToStorage()
            
            if selectedCamera?.id == camera.id {
                selectedCamera = cameras[index]
            }
        }
    }
    
    func saveCamerasToStorage() {
        if let encoded = try? JSONEncoder().encode(cameras) {
            UserDefaults.standard.set(encoded, forKey: "savedCameras")
        }
    }
}

// MARK: - Edit Camera Sheet
struct EditCameraSheet: View {
    @Environment(\.dismiss) var dismiss
    let cameraName: String
    let onSave: (String) -> Void
    
    @State private var newName: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit Camera Name")
                        .font(.title)
                        .fontWeight(.semibold)
                    Text("Enter a new name for this camera")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: {
                    dismiss()
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
                    Text("CAMERA NAME")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    TextField("e.g., Main Gate Camera", text: $newName)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(10)
                        .onAppear {
                            newName = cameraName
                        }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            
            Spacer(minLength: 20)
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
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
                
                Button("Save") {
                    if !newName.isEmpty {
                        onSave(newName)
                        dismiss()
                    }
                }
                .font(.body)
                .fontWeight(.semibold)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(newName.isEmpty ? Color.gray.opacity(0.5) : Color.green.opacity(0.9))
                )
                .foregroundColor(.white)
                .buttonStyle(.plain)
                .disabled(newName.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(width: 400, height: 250)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}
