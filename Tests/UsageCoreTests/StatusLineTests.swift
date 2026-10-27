import Foundation
import Testing
@testable import UsageCore

/// code.claude.com/docs/en/statusline sayfasındaki örnek girdiden (ilgili alanlar).
let docExampleJSON = #"""
{
  "session_id": "abc123",
  "model": { "id": "claude-opus-5-5", "display_name": "Opus" },
  "context_window": { "used_percentage": 8 },
  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 },
    "spend_limit": { "used_percentage": 62.8, "resets_at": 1740787200 }
  }
}
"""#

@Suite struct StatusLineLimitsTests {
    @Test func parsesDocumentedSchema() throws {
        let now = Date(timeIntervalSince1970: 1_738_420_000)
        let l = try #require(StatusLineLimits.parse(Data(docExampleJSON.utf8), capturedAt: now))
        #expect(l.fiveHour == RateLimitWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)))
        #expect(l.sevenDay == RateLimitWindow(usedPercentage: 41.2, resetsAt: Date(timeIntervalSince1970: 1_738_857_600)))
        #expect(l.capturedAt == now)
    }

    @Test func windowsMayBeIndependentlyAbsent() throws {
        let json = #"{"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1738857600}}}"#
        let l = try #require(StatusLineLimits.parse(Data(json.utf8), capturedAt: Date()))
        #expect(l.fiveHour == nil)
        #expect(l.sevenDay?.usedPercentage == 5)
    }

    @Test func apiKeyLoginWithoutRateLimitsYieldsNil() {
        // API anahtarıyla girişte rate_limits hiç gelmez; yalnızca spend_limit de yeterli değil.
        #expect(StatusLineLimits.parse(Data(#"{"model":{"id":"x"}}"#.utf8), capturedAt: Date()) == nil)
        #expect(StatusLineLimits.parse(Data(#"{"rate_limits":{"spend_limit":{"used_percentage":1}}}"#.utf8), capturedAt: Date()) == nil)
        #expect(StatusLineLimits.parse(Data("bozuk".utf8), capturedAt: Date()) == nil)
    }

    @Test func staleAndExpired() {
        let t0 = Date(timeIntervalSince1970: 1_738_420_000)
        let w = RateLimitWindow(usedPercentage: 50, resetsAt: t0.addingTimeInterval(3600))
        let l = StatusLineLimits(fiveHour: w, sevenDay: nil, capturedAt: t0)
        #expect(!l.isStale(at: t0.addingTimeInterval(14 * 60)))
        #expect(l.isStale(at: t0.addingTimeInterval(16 * 60)))
        #expect(!w.isExpired(at: t0.addingTimeInterval(3599)))
        #expect(w.isExpired(at: t0.addingTimeInterval(3600)))
    }
}

/// Kurulu script'i gerçek bash ile çalıştırır (HOME geçici dizine yönlendirilir).
@Suite struct StatusLineScriptTests {
    private func setup() throws -> (home: URL, installer: StatusLineInstaller) {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("slhome-\(UUID().uuidString)")
        let inst = StatusLineInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            supportDir: home.appendingPathComponent(".claude-usage-bar"))
        try inst.install(confirmedWrapping: false)
        return (home, inst)
    }

    private func run(_ inst: StatusLineInstaller, home: URL, input: String) throws -> (out: String, code: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [inst.scriptURL.path]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stdout = Pipe()
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = FileHandle.nullDevice
        try p.run()
        stdin.fileHandleForWriting.write(Data(input.utf8))
        try stdin.fileHandleForWriting.close()
        p.waitUntilExit()
        let out = String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (out, p.terminationStatus)
    }

    @Test func writesLimitsAtomicallyAndPrintsSummary() throws {
        let (home, inst) = try setup()
        let r = try run(inst, home: home, input: docExampleJSON)
        #expect(r.code == 0)
        #expect(r.out == "5s %24 · 7g %41\n")
        let written = try String(contentsOf: inst.limitsURL, encoding: .utf8)
        #expect(written == docExampleJSON)
        let perms = try FileManager.default.attributesOfItem(atPath: inst.limitsURL.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        // geçici dosya kalmamalı
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: inst.supportDir.path).filter { $0.hasPrefix(".limits") }
        #expect(leftovers.isEmpty)
    }

    @Test func inputWithoutRateLimitsDoesNotOverwrite() throws {
        let (home, inst) = try setup()
        _ = try run(inst, home: home, input: docExampleJSON)
        let r = try run(inst, home: home, input: #"{"model":{"id":"x"}}"#)
        #expect(r.code == 0)
        #expect(r.out == "")
        #expect(try String(contentsOf: inst.limitsURL, encoding: .utf8) == docExampleJSON)
    }

    @Test func silentWhenDirectoryIsMissing() throws {
        let (home, inst) = try setup()
        let script = try Data(contentsOf: inst.scriptURL)
        let other = home.appendingPathComponent("elsewhere.sh")
        try script.write(to: other)
        try FileManager.default.removeItem(at: inst.supportDir)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [other.path]
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        p.standardInput = stdin; p.standardOutput = stdout; p.standardError = stderr
        try p.run()
        stdin.fileHandleForWriting.write(Data(docExampleJSON.utf8))
        try stdin.fileHandleForWriting.close()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        #expect(String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) == "5s %24 · 7g %41\n")
        #expect(stderr.fileHandleForReading.readDataToEndOfFile().isEmpty)
    }

    @Test func wrapsExistingCommandAndPreservesItsOutput() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("slhome-\(UUID().uuidString)")
        let inst = StatusLineInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            supportDir: home.appendingPathComponent(".claude-usage-bar"))
        try FileManager.default.createDirectory(at: inst.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Mevcut status line girdideki modeli basıyor.
        let existing = #"{"statusLine":{"type":"command","command":"grep -o '\"display_name\": \"[A-Za-z]*\"'","padding":2}}"#
        try Data(existing.utf8).write(to: inst.settingsURL)
        try inst.install(confirmedWrapping: true)

        let r = try run(inst, home: home, input: docExampleJSON)
        #expect(r.out == "\"display_name\": \"Opus\"\n")
        #expect(FileManager.default.fileExists(atPath: inst.limitsURL.path))
    }
}

@Suite struct StatusLineInstallerTests {
    private func make(settings: String?) throws -> StatusLineInstaller {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("slinst-\(UUID().uuidString)")
        let inst = StatusLineInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            supportDir: home.appendingPathComponent(".claude-usage-bar"))
        if let settings {
            try FileManager.default.createDirectory(at: inst.settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(settings.utf8).write(to: inst.settingsURL)
        }
        return inst
    }

    private func settings(_ inst: StatusLineInstaller) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: inst.settingsURL)) as! [String: Any]
    }

    @Test func freshInstallKeepsOtherKeysAndUninstallRemovesKey() throws {
        let inst = try make(settings: #"{"model":"opus","theme":"dark"}"#)
        #expect(try inst.status() == .notInstalled(existingCommand: nil))
        try inst.install(confirmedWrapping: false)

        var s = try settings(inst)
        #expect(s["model"] as? String == "opus")
        #expect(s["theme"] as? String == "dark")
        let sl = try #require(s["statusLine"] as? [String: Any])
        #expect(sl["type"] as? String == "command")
        #expect(sl["command"] as? String == inst.command)
        #expect(try inst.status() == .installed(wrapping: nil))
        #expect(FileManager.default.isExecutableFile(atPath: inst.scriptURL.path))

        try inst.install(confirmedWrapping: false) // tekrar kurmak zararsız
        #expect(try inst.status() == .installed(wrapping: nil))

        try inst.uninstall()
        s = try settings(inst)
        #expect(s["statusLine"] == nil)
        #expect(s["model"] as? String == "opus")
        #expect(!FileManager.default.fileExists(atPath: inst.scriptURL.path))
    }

    @Test func worksWithoutSettingsFile() throws {
        let inst = try make(settings: nil)
        try inst.install(confirmedWrapping: false)
        #expect(try inst.status() == .installed(wrapping: nil))
    }

    @Test func existingStatusLineRequiresConfirmationThenIsRestored() throws {
        let original = #"{"statusLine":{"type":"command","command":"~/my-status.sh","padding":2,"refreshInterval":5}}"#
        let inst = try make(settings: original)
        #expect(try inst.status() == .notInstalled(existingCommand: "~/my-status.sh"))

        #expect(throws: StatusLineInstaller.InstallError.needsConfirmation(existingCommand: "~/my-status.sh")) {
            try inst.install(confirmedWrapping: false)
        }
        // Onaysız denemede settings.json değişmemeli
        #expect(try String(contentsOf: inst.settingsURL, encoding: .utf8) == original)

        try inst.install(confirmedWrapping: true)
        let sl = try #require(try settings(inst)["statusLine"] as? [String: Any])
        #expect(sl["command"] as? String == inst.command)
        #expect(sl["padding"] as? Int == 2)          // diğer alanlar korunur
        #expect(sl["refreshInterval"] as? Int == 5)
        #expect(try inst.status() == .installed(wrapping: "~/my-status.sh"))
        #expect(FileManager.default.fileExists(atPath: inst.supportDir.appendingPathComponent("settings.backup.json").path))

        try inst.uninstall()
        let restored = try #require(try settings(inst)["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == "~/my-status.sh")
        #expect(restored["padding"] as? Int == 2)
        #expect(restored["refreshInterval"] as? Int == 5)
    }

    @Test func invalidSettingsAreNeverOverwritten() throws {
        let broken = #"{"model": "opus",, }"#
        let inst = try make(settings: broken)
        #expect(throws: StatusLineInstaller.InstallError.invalidSettings) {
            try inst.install(confirmedWrapping: true)
        }
        #expect(try String(contentsOf: inst.settingsURL, encoding: .utf8) == broken)
    }

    @Test func uninstallLeavesManuallyChangedStatusLineAlone() throws {
        let inst = try make(settings: #"{}"#)
        try inst.install(confirmedWrapping: false)
        let manual = #"{"statusLine":{"type":"command","command":"echo elle"}}"#
        try Data(manual.utf8).write(to: inst.settingsURL)
        try inst.uninstall()
        #expect(try String(contentsOf: inst.settingsURL, encoding: .utf8) == manual)
    }
}
