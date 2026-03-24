import SwiftUI

@main
struct MBotControllerApp: App {

    @StateObject private var bleManager      = MBotBLEManager()
    @StateObject private var motionManager   = MotionManager()
    @StateObject private var locationManager = LocationManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(motionManager)
                .environmentObject(locationManager)
                .onAppear  { motionManager.start() }
                .onDisappear {
                    motionManager.stop()
                    locationManager.stop()
                    bleManager.stop()
                }
        }
    }
}
