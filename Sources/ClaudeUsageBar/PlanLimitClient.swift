import Foundation
import Security
import UsageCore

enum PlanLimitError: LocalizedError {
    case noCredentials
    case keychainDenied
    case tokenExpired
    case unauthorized
    case http(Int)
    case unexpectedResponse
    case network(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials: return "Keychain'de Claude Code oturumu bulunamadı."
        case .keychainDenied: return "Keychain erişimine izin verilmedi."
        case .tokenExpired: return "Claude Code oturum token'ının süresi dolmuş; Claude Code'u bir kez açın."
        case .unauthorized: return "Yetkisiz (401). Claude Code'da yeniden giriş yapın."
        case .http(let code): return "Uç nokta hata döndürdü (HTTP \(code))."
        case .unexpectedResponse: return "Yanıt biçimi tanınmadı (uç nokta değişmiş olabilir)."
        case .network(let msg): return "Ağ hatası: \(msg)"
        }
    }
}

/// RESMİ OLMAYAN plan limiti istemcisi. Varsayılan olarak kapalıdır.
///
/// Claude Code'un `/usage` ekranında kullandığı belgelenmemiş uç noktayı çağırır.
/// Erişim token'ı yalnızca macOS Keychain'deki "Claude Code-credentials" öğesinden,
/// kullanıcı bu özelliği açtığında okunur; yalnızca bellekte tutulur, asla diske yazılmaz,
/// loglanmaz ve api.anthropic.com dışında hiçbir yere gönderilmez.
actor PlanLimitClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"

    private struct Credentials {
        var accessToken: String
        var expiresAt: Date?
    }

    private var credentials: Credentials?
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral // çerez/önbellek yok
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Bellekteki token'ı unut (özellik kapatıldığında).
    func forget() { credentials = nil }

    func fetch() async throws -> PlanLimits {
        var creds = try credentials ?? readKeychain()
        if let exp = creds.expiresAt, exp < Date() {
            // Claude Code token'ı yenilemiş olabilir; Keychain'i bir kez daha oku.
            creds = try readKeychain()
            if let exp2 = creds.expiresAt, exp2 < Date() { throw PlanLimitError.tokenExpired }
        }
        credentials = creds

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(creds.accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ClaudeUsageBar", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw PlanLimitError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw PlanLimitError.unexpectedResponse }
        switch http.statusCode {
        case 200: break
        case 401, 403:
            credentials = nil
            throw PlanLimitError.unauthorized
        default:
            throw PlanLimitError.http(http.statusCode)
        }
        guard let limits = PlanLimits.parse(data) else { throw PlanLimitError.unexpectedResponse }
        return limits
    }

    // MARK: - Keychain

    private func readKeychain() throws -> Credentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: throw PlanLimitError.noCredentials
        default: throw PlanLimitError.keychainDenied
        }
        guard let data = item as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw PlanLimitError.noCredentials
        }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        return Credentials(accessToken: token, expiresAt: expiresAt)
    }
}
