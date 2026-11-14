import Testing
import Foundation
@testable import macOSmonitor

/// Startup Apps and Services read launchd's property lists, its running and enabled state, and
/// each program's publisher.
struct LaunchScheduleTests {
    @Test func whenItRuns() {
        let cases: [([String: Any], LaunchScope, String)] = [
            (["KeepAlive": true, "RunAtLoad": true], .userAgent, "Kept running"),
            (["KeepAlive": ["SuccessfulExit": false]], .userAgent, "Kept running"),
            (["RunAtLoad": true], .userAgent, "At login"),
            (["RunAtLoad": true], .daemon, "At startup"),
            (["StartInterval": 3_600], .userAgent, "Every hour"),
            (["StartInterval": 7_200], .userAgent, "Every 2 hours"),
            (["StartInterval": 300], .userAgent, "Every 5 minutes"),
            (["StartInterval": 45], .userAgent, "Every 45 seconds"),
            (["StartCalendarInterval": ["Hour": 3]], .daemon, "On a schedule"),
            (["WatchPaths": ["/tmp/x"]], .userAgent, "When files change"),
            (["MachServices": ["x": true]], .daemon, "On demand"),
            ([:], .userAgent, "On demand"),
        ]
        for (plist, scope, expected) in cases {
            #expect(LaunchSchedule.describe(plist, scope: scope) == expected, "\(plist)")
        }
    }

    @Test func keepAliveFalseIsNotKeptRunning() {
        #expect(LaunchSchedule.describe(["KeepAlive": false, "RunAtLoad": true], scope: .userAgent) == "At login")
    }
}

struct LaunchItemParseTests {
    @Test func programArgumentsGiveTheCommand() throws {
        let item = try #require(LaunchItem.parse(
            ["Label": "homebrew.mxcl.container",
             "ProgramArguments": ["/opt/homebrew/opt/container/bin/container", "system", "start"],
             "KeepAlive": true],
            path: "/Users/u/Library/LaunchAgents/homebrew.mxcl.container.plist", scope: .userAgent))
        #expect(item.label == "homebrew.mxcl.container")
        #expect(item.program == "/opt/homebrew/opt/container/bin/container")
        #expect(item.commandLine == "/opt/homebrew/opt/container/bin/container system start")
        #expect(item.schedule == "Kept running")
        #expect(!item.disabledInFile)
        #expect(item.id == "/Users/u/Library/LaunchAgents/homebrew.mxcl.container.plist")
    }

    @Test func programWinsOverTheFirstArgument() throws {
        let item = try #require(LaunchItem.parse(
            ["Label": "x", "Program": "/usr/bin/real", "ProgramArguments": ["shown-name", "-v"], "Disabled": true],
            path: "/p.plist", scope: .daemon))
        #expect(item.program == "/usr/bin/real")
        #expect(item.commandLine == "/usr/bin/real -v")
        #expect(item.disabledInFile)
    }

    @Test func aFileWithoutALabelIsNotALaunchItem() {
        #expect(LaunchItem.parse(["ProgramArguments": ["/bin/true"]], path: "/p.plist", scope: .userAgent) == nil)
    }

    @Test func eachScopeHasItsLaunchdDomain() {
        #expect(LaunchScope.userAgent.domain(uid: 501) == "gui/501")
        #expect(LaunchScope.allUsersAgent.domain(uid: 501) == "gui/501")
        #expect(LaunchScope.daemon.domain(uid: 501) == "system")
        #expect(LaunchScope.appleDaemon.domain(uid: 501) == "system")
    }
}

struct LaunchctlParseTests {
    /// Shaped like `launchctl print system`: pid (0 when not running), last exit, label.
    private let print = """
        system = {
        \tservices = {
        \t\t     777      - \tcom.docker.vmnetd
        \t\t       0      - \tcom.docker.socket
        \t\t       0   (pe) \tcom.apple.lskdd
        \t\t       0     78 \tcom.example.crashy
        \t}
        \tunmanaged processes = {
        \t\t     123      - \tnot.a.service
        \t}
        }
        """

    @Test func servicesBlockGivesEachLabelsPID() {
        let services = LaunchctlOutput.services(print)
        #expect(services["com.docker.vmnetd"] == LaunchctlOutput.Service(pid: 777, lastExit: nil))
        #expect(services["com.docker.socket"] == LaunchctlOutput.Service(pid: nil, lastExit: nil))
        #expect(services["com.example.crashy"] == LaunchctlOutput.Service(pid: nil, lastExit: 78))
        #expect(services["not.a.service"] == nil)            // outside the services block
    }

    @Test func overridesSayEnabledOrDisabled() {
        let text = """
            disabled services = {
            \t\t"com.apple.screensharing" => disabled
            \t\t"homebrew.mxcl.caddy" => enabled
            \t}
            """
        #expect(LaunchctlOutput.overrides(text) == ["com.apple.screensharing": false, "homebrew.mxcl.caddy": true])
    }
}

struct LaunchPublisherTests {
    @Test func developerIDCertificatesNameTheirOrganisation() {
        #expect(CodePublisher.name(fromCertificateSummary: "Developer ID Application: Google LLC (EQHXZ8M8AV)") == "Google LLC")
        #expect(CodePublisher.name(fromCertificateSummary: "Apple Development: Peter Jones (YFCWDT9V2B)") == "Peter Jones")
        #expect(CodePublisher.name(fromCertificateSummary: "Software Signing") == "Apple")
        #expect(CodePublisher.name(fromCertificateSummary: "Some Other Cert") == "Some Other Cert")
    }

    @Test func realBinariesOnThisMac() throws {
        #expect(CodePublisher.publisher(ofProgramAt: "/usr/libexec/bootpd") == "Apple")
        #expect(CodePublisher.publisher(ofProgramAt: "/no/such/program") == "Program missing")
        let unsigned = FileManager.default.temporaryDirectory.appendingPathComponent("unsigned-\(UUID().uuidString)")
        try Data("#!/bin/sh\n".utf8).write(to: unsigned)
        defer { try? FileManager.default.removeItem(at: unsigned) }
        #expect(CodePublisher.publisher(ofProgramAt: unsigned.path) == "Unsigned")
    }
}

struct FileFactsTests {
    @Test func permissionsReadLikeLs() {
        #expect(FileFacts.permissionsText(0o644) == "-rw-r--r-- (644)")
        #expect(FileFacts.permissionsText(0o755) == "-rwxr-xr-x (755)")
        #expect(FileFacts.permissionsText(0o600) == "-rw------- (600)")
    }
}
