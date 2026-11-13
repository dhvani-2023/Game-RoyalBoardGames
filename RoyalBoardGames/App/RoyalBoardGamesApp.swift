import SwiftUI
import GameKit

/// App entry (Android `BoardGamesApp` + `MainActivity`): fonts, settings, audio warm-up, portrait lock
/// (Pool and Carrom unlock rotation with `AllowRotation`), music follows the app's visibility.
@main
struct RoyalBoardGamesApp: App {
    @UIApplicationDelegateAdaptor(GameAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.registerAll()
        AppSettings.load()
        PartyStore.ensureLoaded()
        AudioMixer.start()
        UiSound.warmUp()
        LegalConnectivity.shared.start()
        OrientationLock.shared.mask = .portrait
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            BoardGamesTheme(reduceMotion: AppSettings.data.reduceMotion) {
                AppRoot()
            }
            .statusBarHidden(false)
            .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: MusicPlayer.onForeground()
            case .background:
                MusicPlayer.onBackground()
                AudioSystem.shared.suspend()
            default: break
            }
        }
    }
}

extension Haptics {
    /// Warms up the feedback generators (no Android equivalent needed).
    @MainActor static func prepare() { GameKit.Haptics.prepare() }
}
