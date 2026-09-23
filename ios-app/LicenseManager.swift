import Combine
import Foundation
import Security

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    @Published private(set) var isActive = false
    @Published private(set) var expiresAt: Date?
    @Published private(set) var remainingDays = 0
    @Published private(set) var isBusy = false
    @Published var lastError: String?

    private let session: URLSession
    private let apiBaseURL: URL
    private let deviceID: String

    private init(session: URLSession = .shared) {
        self.session = session
        let configuredURL = Bundle.main.object(forInfoDictionaryKey: "LicenseAPIBaseURL") as? String
        self.apiBaseURL = URL(string: configuredURL ?? "https://wall-api.18ir.cn/api")!
        self.deviceID = Self.loadOrCreateDeviceID()
    }

    var statusText: String {
        guard isActive, let expiresAt else { return "未激活" }
        return "有效至 \(Self.displayDate.string(from: expiresAt))（剩余 \(remainingDays) 天）"
    }

    func redeem(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = "请输入卡密"
            return
        }

        isBusy = true
        defer { isBusy = false }

        do {
            let response = try await request(path: "license_redeem.php", body: [
                "license_key": key,
                "device_id": deviceID
            ])
            apply(response)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refresh() async {
        isBusy = true
        defer { isBusy = false }

        do {
            let response = try await request(path: "license_status.php", body: [
                "device_id": deviceID
            ])
            apply(response)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requireActive() async throws {
        do {
            let response = try await request(path: "license_status.php", body: [
                "device_id": deviceID
            ])
            apply(response)
            guard response.active else { throw LicenseError.notActive }
            lastError = nil
        } catch let error as LicenseError {
            throw error
        } catch {
            throw error
        }
    }

    private func request(path: String, body: [String: String]) async throws -> LicenseResponse {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.badResponse
        }

        if !(200..<300 ~= http.statusCode) {
            let message = (try? JSONDecoder().decode(LicenseErrorResponse.self, from: data))?.message
                ?? "授权服务器返回 HTTP \(http.statusCode)"
            throw LicenseError.server(message)
        }
        guard let decoded = try? JSONDecoder().decode(LicenseResponse.self, from: data), decoded.ok else {
            throw LicenseError.server("授权服务器返回无效数据")
        }
        return decoded
    }

    private func apply(_ response: LicenseResponse) {
        isActive = response.active
        remainingDays = max(0, Int(ceil(response.remainingSeconds / 86_400.0)))
        expiresAt = response.expiresAt.flatMap { Self.parseDate($0) }
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func parseDate(_ value: String) -> Date? {
        iso8601WithFractionalSeconds.date(from: value) ?? iso8601.date(from: value)
    }

    private static let displayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func loadOrCreateDeviceID() -> String {
        let service = "com.mutually.wallpaper.license"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device_id",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8),
           value.count == 32 {
            return value
        }

        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let attributes = query.merging([
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]) { _, new in new }
        SecItemAdd(attributes as CFDictionary, nil)
        return value
    }
}

private struct LicenseResponse: Decodable {
    let ok: Bool
    let active: Bool
    let expiresAt: String?
    let remainingSeconds: Double
    let message: String?

    enum CodingKeys: String, CodingKey {
        case ok, active, message
        case expiresAt = "expires_at"
        case remainingSeconds = "remaining_seconds"
    }
}

private struct LicenseErrorResponse: Decodable {
    let message: String?
}

private enum LicenseError: LocalizedError {
    case badResponse
    case notActive
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "授权服务器响应异常"
        case .notActive: return "当前设备没有有效卡密，请先兑换卡密"
        case .server(let message): return message
        }
    }
}
