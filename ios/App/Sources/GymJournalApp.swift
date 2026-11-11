import SwiftUI
import UIKit

/// Модель создаётся вместе с приложением, а не с первым экраном: часы могут разбудить приложение
/// в фоне, когда экрана ещё нет, и их действия должны дойти до таблицы.
final class AppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel.make()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        model.start()
        return true
    }
}

@main
struct GymJournalApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(delegate.model)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                delegate.model.wake()
            case .background:
                delegate.model.enteredBackground()
            default:
                break
            }
        }
    }
}
