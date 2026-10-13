//
//  ContentView.swift
//  TrafficCounter
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = "Dashboard"
    let userId: Int
    let userName: String
    
    var body: some View {
        NavigationSplitView {
            // SIDEBAR
            List(selection: $selectedTab) {
                Label("Dashboard", systemImage: "chart.bar.fill")
                    .tag("Dashboard")
                Label("Camera", systemImage: "video.fill")
                    .tag("Camera")
                Label("Sessions", systemImage: "clock.arrow.circlepath")
                    .tag("Sessions")
                Label("Reports", systemImage: "doc.text.fill")
                    .tag("Reports")
                Label("Settings", systemImage: "gear")
                    .tag("Settings")
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 180)
            .navigationTitle("Traffic Counter")
            
        } detail: {
            // MAIN CONTENT AREA
            switch selectedTab {
            case "Dashboard":
                Text("Dashboard View - Coming Soon")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case "Camera":
                CameraView(userId: userId, userName: userName)
            case "Sessions":
                SessionsView()
            case "Reports":
                Text("Reports View - Coming Soon")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case "Settings":
                Text("Settings View - Coming Soon")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            default:
                CameraView(userId: userId, userName: userName)
            }
        }
        .frame(minWidth: 900, minHeight: 700)
    }
}

#Preview {
    ContentView(userId: 1, userName: "Preview User")
}
