import Foundation
import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

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
