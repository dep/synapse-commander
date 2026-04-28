import SwiftUI
import Sparkle

final class UpdaterViewModel: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published var updateAvailable: Bool = false
    @Published var latestVersion: String = ""

    private var controller: SPUStandardUpdaterController!

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }

    func checkInBackground() {
        controller.updater.checkForUpdateInformation()
    }

    func installNow() {
        controller.updater.checkForUpdates()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        DispatchQueue.main.async {
            self.latestVersion = item.displayVersionString
            self.updateAvailable = true
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        DispatchQueue.main.async {
            self.updateAvailable = false
        }
    }
}

struct UpdateBanner: View {
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        if updater.updateAvailable {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.white)
                Text("Version \(updater.latestVersion) is available")
                    .foregroundColor(.white)
                Spacer()
                Button("Install & Restart") { updater.installNow() }
                    .buttonStyle(.borderedProminent)
                Button("Later") { updater.updateAvailable = false }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.85))
        }
    }
}
