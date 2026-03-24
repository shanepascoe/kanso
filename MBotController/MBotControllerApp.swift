import SwiftUI

@main
struct MBotControllerApp: App {

    @StateObject private var bleManager      = MBotBLEManager()
    @StateObject private var motionManager   = MotionManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var scriptEngine    = ScriptEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bleManager)
                .environmentObject(motionManager)
                .environmentObject(locationManager)
                .environmentObject(scriptEngine)
                .onAppear  { motionManager.start() }
                .onDisappear {
                    motionManager.stop()
                    locationManager.stop()
                    bleManager.stop()
                }
        }
    }
}
