import Foundation
import Testing

@testable import cmux

struct GhosttyDockCLIInstallerTests {
    @Test func defaultDestinationIsGdock() {
        #expect(CmuxCLIPathInstaller.defaultCLIDestinationPath == "/usr/local/bin/gdock")
        #expect(CmuxCLIPathInstaller.compatibilityCLIDestinationPath == "/usr/local/bin/cmux")
        #expect(CmuxCLIPathInstaller.bundledCLIResourceRelativePath == "bin/gdock")
    }

    @Test func installerDefaultInstanceUsesGdockDestination() {
        let installer = CmuxCLIPathInstaller()
        #expect(installer.destinationPath == "/usr/local/bin/gdock")
    }
}
