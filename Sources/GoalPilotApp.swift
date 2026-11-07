import SwiftUI

@main
struct GoalPilotApp: App {
    @StateObject private var data = DataStore()
    @StateObject private var subs = SubscriptionManager()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(data)
                .environmentObject(subs)
                .task { await subs.load(); await data.replan() }
                .onChange(of: phase) { _, new in
                    if new == .active { Task { await subs.refresh(); await data.replan() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var subs: SubscriptionManager
    var body: some View {
        if !subs.loaded { ProgressView() }
        else if subs.isSubscribed || subs.testBypass { MainTabs() }
        else { PaywallView() }
    }
}

struct MainTabs: View {
    @StateObject private var data = DataStore()

    var body: some View {
        TabView {
            TodayView()
                .tabItem {
                    Label("Today", systemImage: "checklist")
                }

            GoalsView()
                .tabItem {
                    Label("Goals", systemImage: "target")
                }

            DisruptionsView()
                .tabItem {
                    Label("Life Events", systemImage: "exclamationmark.triangle")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .environmentObject(data)
    }
}
