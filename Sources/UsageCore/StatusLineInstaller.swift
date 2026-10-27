import Foundation

/// Claude Code'un `statusLine` ayarına, `rate_limits` verisini oturum başına `limits/<session_id>.json`a
/// yazan köprü script'ini bağlar.
///
/// - Mevcut bir `statusLine` varsa onay olmadan dokunmaz. Onay verilirse eski ayarı saklar ve
///   script eski komutu aynı girdiyle çalıştırıp çıktısını aynen basar (sarmalayıcı).
/// - `settings.json`ta yalnızca `statusLine` anahtarı değişir; değişiklikten önce yedek alınır.
public struct StatusLineInstaller {
    public enum Status: Equatable {
        case notInstalled(existingCommand: String?)
        case installed(wrapping: String?)
    }

    public enum InstallError: LocalizedError, Equatable {
        /// Mevcut bir status line var; kullanıcı onayı gerekiyor.
        case needsConfirmation(existingCommand: String)
        case invalidSettings

        public var errorDescription: String? {
            switch self {
            case .needsConfirmation(let cmd): return "Mevcut bir status line ayarı var: \(cmd)"
            case .invalidSettings: return "~/.claude/settings.json geçerli JSON değil; dokunulmadı."
            }
        }
    }

    public let settingsURL: URL
    public let supportDir: URL

    public init(settingsURL: URL, supportDir: URL) {
        self.settingsURL = settingsURL
        self.supportDir = supportDir
    }

    public static var `default`: StatusLineInstaller {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return StatusLineInstaller(
            settingsURL: home.appendingPathComponent(".claude/settings.json"),
            supportDir: home.appendingPathComponent(".claude-usage-bar"))
    }

    public var scriptURL: URL { supportDir.appendingPathComponent("statusline.sh") }
    /// Her Claude Code oturumu kendi dosyasına yazar; böylece boşta kalan bir oturumun eski verisi
    /// etkin oturumun güncel verisini ezemez. Uygulama dosyaları `StatusLineLimits.merge` ile birleştirir.
    public var limitsDir: URL { supportDir.appendingPathComponent("limits", isDirectory: true) }
    /// İlk sürümün tek dosyası; artık kullanılmıyor, kurulumda/kaldırmada silinir.
    var legacyLimitsURL: URL { supportDir.appendingPathComponent("limits.json") }
    var originalCommandURL: URL { supportDir.appendingPathComponent("original-command") }
    var originalStatusLineURL: URL { supportDir.appendingPathComponent("original-statusline.json") }
    var backupURL: URL { supportDir.appendingPathComponent("settings.backup.json") }

    /// settings.json'a yazılan komut. Boşluk içeren yollar için tırnaklanır.
    public var command: String { "/bin/bash '\(scriptURL.path)'" }

    public func isOurs(_ command: String?) -> Bool {
        command?.contains("/.claude-usage-bar/statusline.sh") ?? false
    }

    // MARK: - Durum

    public func status() throws -> Status {
        let existing = try readSettings()["statusLine"] as? [String: Any]
        let cmd = existing?["command"] as? String
        if isOurs(cmd) {
            let wrapped = try? String(contentsOf: originalCommandURL, encoding: .utf8)
            return .installed(wrapping: wrapped?.isEmpty == false ? wrapped : nil)
        }
        return .notInstalled(existingCommand: existing.map { describe($0) })
    }

    // MARK: - Kur

    /// - Parameter confirmedWrapping: mevcut bir status line'ı sarmalamak için kullanıcı onayı.
    public func install(confirmedWrapping: Bool) throws {
        var settings = try readSettings()
        let existing = settings["statusLine"] as? [String: Any]
        let existingCommand = existing?["command"] as? String

        try prepareSupportDir()
        try writeScript()
        try? FileManager.default.removeItem(at: legacyLimitsURL)

        if isOurs(existingCommand) { return } // zaten kurulu; script güncellendi

        if let existing {
            guard confirmedWrapping else {
                throw InstallError.needsConfirmation(existingCommand: describe(existing))
            }
            let data = try JSONSerialization.data(withJSONObject: existing, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: originalStatusLineURL, options: .atomic)
            if let existingCommand, existing["type"] as? String == "command" {
                try Data(existingCommand.utf8).write(to: originalCommandURL, options: .atomic)
            }
        } else {
            try? FileManager.default.removeItem(at: originalCommandURL)
            try? FileManager.default.removeItem(at: originalStatusLineURL)
        }

        if FileManager.default.fileExists(atPath: settingsURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: settingsURL, to: backupURL)
        }

        // padding, refreshInterval gibi diğer alanlar korunur.
        var statusLine = existing ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        try writeSettings(settings)
    }

    // MARK: - Kaldır

    public func uninstall() throws {
        var settings = try readSettings()
        let current = settings["statusLine"] as? [String: Any]
        if isOurs(current?["command"] as? String) {
            if let data = try? Data(contentsOf: originalStatusLineURL),
               let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings["statusLine"] = original
            } else {
                settings.removeValue(forKey: "statusLine")
            }
            try writeSettings(settings)
        }
        // Ayar elle değiştirilmişse settings.json'a dokunulmaz; yalnızca kendi dosyalarımız silinir.
        for url in [scriptURL, originalCommandURL, originalStatusLineURL, limitsDir, legacyLimitsURL] {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Yardımcılar

    private func describe(_ statusLine: [String: Any]) -> String {
        (statusLine["command"] as? String) ?? (statusLine["type"] as? String) ?? "(bilinmeyen)"
    }

    private func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x09 || $0 == 0x0D }) { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InstallError.invalidSettings
        }
        return obj
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        var data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        try data.write(to: settingsURL, options: .atomic)
    }

    public func prepareSupportDir() throws {
        for dir in [supportDir, limitsDir] {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
    }

    private func writeScript() throws {
        try Data(StatusLineScript.source.utf8).write(to: scriptURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }
}

/// `~/.claude-usage-bar/statusline.sh` içeriği. Bağımlılıksız bash (macOS'un bash 3.2'siyle uyumlu).
public enum StatusLineScript {
    public static let source = #"""
    #!/bin/bash
    # Claude Usage Bar — status line köprüsü.
    # Claude Code'un status line JSON'unu stdin'den okur; "rate_limits" içeriyorsa
    # ~/.claude-usage-bar/limits/<session_id>.json dosyasına atomik yazar (geçici dosya + mv).
    # Oturum başına ayrı dosya: boşta kalan bir oturumun eski verisi güncel veriyi ezemez.
    # Hiçbir hatada çıktı bozulmaz ve script her zaman 0 ile çıkar.
    dir="$HOME/.claude-usage-bar"
    input=$(cat 2>/dev/null)

    case "$input" in
      *'"rate_limits"'*)
        sid=unknown
        re='"session_id"[[:space:]]*:[[:space:]]*"([A-Za-z0-9_-]+)"'
        [[ $input =~ $re ]] && sid="${BASH_REMATCH[1]}"
        umask 077
        [ -d "$dir/limits" ] || mkdir -p "$dir/limits" 2>/dev/null
        tmp="$dir/limits/.$sid.json.$$"
        { printf '%s' "$input" > "$tmp" && mv -f "$tmp" "$dir/limits/$sid.json"; } 2>/dev/null \
          || rm -f "$tmp" 2>/dev/null
        ;;
    esac

    # Önceden bir status line varsa onu aynı girdiyle çalıştır ve çıktısını aynen bas.
    if [ -s "$dir/original-command" ]; then
      orig=$(cat "$dir/original-command" 2>/dev/null)
      printf '%s' "$input" | /bin/sh -c "$orig" 2>/dev/null
      exit 0
    fi

    pct() {
      re="\"$1\"[[:space:]]*:[[:space:]]*\{[^}]*\"used_percentage\"[[:space:]]*:[[:space:]]*([0-9.]+)"
      [[ $input =~ $re ]] && printf '%.0f' "${BASH_REMATCH[1]}" 2>/dev/null
    }
    five=$(pct five_hour)
    week=$(pct seven_day)
    out=""
    [ -n "$five" ] && out="5s %$five"
    [ -n "$week" ] && out="${out:+$out · }7g %$week"
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0

    """#
}
