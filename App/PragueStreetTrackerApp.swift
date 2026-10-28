import SwiftUI
import UIKit

@main
struct PragueStreetTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
        }
    }
}

/// Owns the tracking model so tracking resumes even when iOS relaunches the
/// app in the background after ending it mid-walk. No window (and no SwiftUI
/// view) exists then, so a model created by a view would never start.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) var viewModel: TrackingViewModel!

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        viewModel = TrackingViewModel(launchedForLocation: launchOptions?[.location] != nil)
        return true
    }
}
