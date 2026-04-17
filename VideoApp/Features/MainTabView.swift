//
//  MainTabView.swift
//  AIVideo
//
//  Main tab container view with native tab bar
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var toastManager = ToastManager.shared
    
    var body: some View {
        ZStack {
            TabView(selection: $appState.currentTab) {
                // Create Tab
                NavigationStack {
                    CreateView()
                }
                .tabItem {
                    Label("Create", systemImage: "sparkles")
                }
                .tag(VideoTab.create)
                
                // My Videos Tab
                NavigationStack {
                    HistoryListView()
                }
                .tabItem {
                    Label("My Videos", systemImage: "film.stack")
                }
                .tag(VideoTab.myVideos)
                
                // Profile Tab
                NavigationStack {
                    ProfileView()
                }
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(VideoTab.profile)
            }
            .tint(.white)
            .preferredColorScheme(.dark)
            .environmentObject(appState)
            .onChange(of: appState.currentTab) { _, newTab in
                let tabName: String
                switch newTab {
                case .create: tabName = "create"
                case .myVideos: tabName = "my_videos"
                case .profile: tabName = "profile"
                }
                Analytics.track(.tabSwitched(tab: tabName))
            }
            
            // Toast overlay - shown on top of everything
            ToastView()
        }
    }
}

// MARK: - Preview

#Preview {
    MainTabView()
        .environmentObject(AppState.shared)
}
