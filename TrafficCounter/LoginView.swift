//
//  LoginView.swift
//  TrafficCounter
//
//  Created by Jhon Patrick Acedo on 5/27/26.
//


import SwiftUI

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isLoggedIn = false
    @State private var loggedInUserId: Int?
    @State private var loggedInUserName = ""
    
    var body: some View {
        Group {
            if isLoggedIn {
                ContentView(userId: loggedInUserId ?? 1, userName: loggedInUserName)
            } else {
                loginForm
            }
        }
    }
    
    var loginForm: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("VehiSights")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Sign in to continue")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            VStack(spacing: 16) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 40)
            
            if isLoading {
                ProgressView()
                    .padding()
            }
            
            Button(action: login) {
                Text("Sign In")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .padding(.horizontal, 40)
            .disabled(isLoading)
            
            Button("Create Account") {
                // Add registration view navigation here
            }
            .font(.caption)
            
            Spacer()
        }
        .padding(.top, 50)
        .alert("Login Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }
    
    func login() {
        isLoading = true
        
        Task {
            do {
                try await DatabaseManager.shared.connect()
                
                let userId = try await DatabaseManager.shared.authenticateUser(email: email, password: password)
                
                await DatabaseManager.shared.disconnect()
                
                if userId > 0 {
                    let userName = email.components(separatedBy: "@").first ?? "User"
                    await MainActor.run {
                        loggedInUserId = userId
                        loggedInUserName = userName
                        isLoggedIn = true
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        errorMessage = "Invalid email or password"
                        showError = true
                        isLoading = false
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}
