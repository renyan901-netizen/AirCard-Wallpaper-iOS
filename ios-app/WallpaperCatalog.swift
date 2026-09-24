import Foundation
import Combine
import Security
import UIKit

struct RemoteWallpaper: Identifiable, Codable, Equatable {
    let id: Int
    let title: String
    let tag: String?
    let imageURLString: String?
    let downloadURLString: String?
    let thumbURLString: String?
    let isGIF: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, tag
        case imageURLString = "image_url"
        case downloadURLString = "down_url"
        case thumbURLString = "thumb_url"
        case isGIF = "is_gif"
    }

    var imageURL: URL? { URL(string: imageURLString ?? "") }
    var downloadURL: URL? { URL(string: downloadURLString ?? "") }
    var thumbURL: URL? {
        guard let raw = thumbURLString, !raw.isEmpty else { return imageURL }
        if raw.hasPrefix("/") { return URL(string: "https://wall-api.18ir.cn\(raw)") }
        return URL(string: raw)
    }

    var tags: [String] {
        guard let tag, let data = tag.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return tag.map { [$0] } ?? []
        }
        return values
    }
}

private struct WallpaperListResponse: Decodable {
    let data: [RemoteWallpaper]
}

private struct DownloadResponse: Decodable {
    let success: Bool?
    let ok: Bool?
    let code: Int?
    let message: String?
    let needPay: Bool?
    let url: URL?
    let downloadURL: URL?
    let downURL: URL?
    let data: DownloadPayload?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, ok, code, message, url, data, error
        case needPay = "need_pay"
        case downloadURL = "download_url"
        case downURL = "down_url"
    }
}

private struct DownloadPayload: Decodable {
    let success: Bool?
    let message: String?
    let url: URL?
    let downloadURL: URL?
    let downURL: URL?

    enum CodingKeys: String, CodingKey {
        case success, message, url
        case downloadURL = "download_url"
        case downURL = "down_url"
    }
}

private struct FingerprintCandidate {
    let value: String
    let source: String

    var hint: String { String(value.prefix(8)) }
}

@MainActor
final class WallpaperCatalogModel: ObservableObject {
    @Published private(set) var wallpapers: [RemoteWallpaper] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published var noticeMessage: String?
    @Published var searchText = ""
    @Published var selectedTag: String?
    @Published var downloadingID: Int?

    private let session: URLSession
    private let baseURL = URL(string: "https://wall-api.18ir.cn/api")!
    private var page = 1
    private var fingerprintSource = "未知"
    private var fingerprintHint = ""
    private var grantResult = "未执行"

    init(session: URLSession = .shared) {
        self.session = session
    }

    var tags: [String] {
        Array(Set(wallpapers.flatMap(\.tags))).sorted()
    }

    var filteredWallpapers: [RemoteWallpaper] {
        wallpapers.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.title.localizedCaseInsensitiveContains(searchText) ||
                item.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            let matchesTag = selectedTag == nil || item.tags.contains(selectedTag!)
            return matchesSearch && matchesTag
        }
    }

    func load(reset: Bool = false) async {
        guard !isLoading else { return }
        if reset { page = 1 }
        isLoading = true
        defer { isLoading = false }

        do {
            var components = URLComponents(url: baseURL.appendingPathComponent("get_wallpaper.php"), resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "search", value: searchText.isEmpty ? nil : searchText),
                URLQueryItem(name: "tag", value: selectedTag)
            ]
            let (data, response) = try await session.data(from: components.url!)
            try validate(response, data: data)
            let decoded = try JSONDecoder().decode(WallpaperListResponse.self, from: data)
            if reset { wallpapers = decoded.data }
            else { merge(decoded.data) }
            page += 1
            errorMessage = nil
        } catch {
            errorMessage = "壁纸列表加载失败：\(error.localizedDescription)"
        }
    }

    func download(_ item: RemoteWallpaper) async {
        guard downloadingID == nil else { return }
        downloadingID = item.id
        defer { downloadingID = nil }

        do {
            let url = try await resolveDownloadURL(for: item)
            let (data, response) = try await session.data(from: url)
            try validate(response, data: data)
            guard data.count > 4, data.starts(with: [0x50, 0x4B, 0x03, 0x04]) else {
                throw CatalogError.invalidPackage
            }

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let safeName = item.title.replacingOccurrences(of: "/", with: "-")
            let destination = docs.appendingPathComponent("\(safeName)-\(item.id).tendies")
            try data.write(to: destination, options: .atomic)
            await AppViewModel.shared?.importTendieFiles(urls: [destination])
            noticeMessage = "壁纸已加载到导入栏，请手动导入"
            errorMessage = nil
        } catch {
            errorMessage = "壁纸下载失败：\(error.localizedDescription)（设备标识：\(fingerprintSource) \(fingerprintHint)；授权请求：\(grantResult)）"
        }
    }

    private func resolveDownloadURL(for item: RemoteWallpaper) async throws -> URL {
        if let direct = item.downloadURL { return direct }

        var lastError = "服务端未返回下载地址"
        for candidate in deviceFingerprintCandidates() {
            fingerprintSource = candidate.source
            fingerprintHint = candidate.hint

            do {
                try await grantDownloadAuthorization(for: item.id, deviceFingerprint: candidate.value)
                grantResult = "成功（\(candidate.source)）"

                var components = URLComponents(url: baseURL.appendingPathComponent("get_download_url.php"), resolvingAgainstBaseURL: false)!
                components.queryItems = [
                    URLQueryItem(name: "card_id", value: String(item.id)),
                    URLQueryItem(name: "device_fp", value: candidate.value)
                ]
                let (data, response) = try await session.data(from: components.url!)
                try validate(response, data: data)
                let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
                if let url = decoded.url ?? decoded.downloadURL ?? decoded.downURL ?? decoded.data?.url ?? decoded.data?.downloadURL ?? decoded.data?.downURL {
                    return url
                }
                lastError = decoded.error ?? decoded.message ?? decoded.data?.message ?? "服务端未返回下载地址"
            } catch {
                lastError = error.localizedDescription
            }
        }

        if lastError.contains("ad_unlock_required") {
            throw CatalogError.server("服务器未认可当前设备指纹；下载地址接口要求先完成有效授权")
        }
        throw CatalogError.server(lastError)
    }

    private func grantDownloadAuthorization(for cardID: Int, deviceFingerprint: String) async throws {
        let timestamp = Int(Date().timeIntervalSince1970)
        let rawCardID = "\(cardID)|\(timestamp)"
        let encodedCardID = Data(rawCardID.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")

        var components = URLComponents(url: baseURL.appendingPathComponent("free_unlock_grant.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "card_id", value: encodedCardID),
            URLQueryItem(name: "device_fp", value: deviceFingerprint)
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response, data: data)

        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard object?["ok"] as? Bool == true else {
            let message = object?["error"] as? String ?? "授权请求失败"
            throw CatalogError.server(message)
        }
    }

    private func deviceFingerprintCandidates() -> [FingerprintCandidate] {
        let key = "com.mutually.wallpaper.device"
        var candidates: [FingerprintCandidate] = []

        func append(_ raw: String?, source: String) {
            guard let raw, let normalized = normalizedFingerprint(raw),
                  !candidates.contains(where: { $0.value == normalized }) else { return }
            candidates.append(FingerprintCandidate(value: normalized, source: source))
        }

        // Match the original wallpaper app's device identity first, then keep
        // the persisted Keychain/UserDefaults values as fallbacks.
        append(UIDevice.current.identifierForVendor?.uuidString, source: "IDFV")

        for query in keychainQueries(service: key) {
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let value = fingerprint(from: result) {
                append(value, source: "Keychain")
            }
        }

        if let existing = UserDefaults.standard.string(forKey: key),
           normalizedFingerprint(existing) != nil {
            append(existing, source: "UserDefaults")
        }

        if candidates.isEmpty {
            let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            UserDefaults.standard.set(value, forKey: key)
            saveFingerprintToKeychain(value, service: key)
            candidates.append(FingerprintCandidate(value: value, source: "新生成"))
        }
        return candidates
    }

    private func fingerprint(from result: CFTypeRef?) -> String? {
        if let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            return normalizedFingerprint(value)
        }
        if let value = result as? String {
            return normalizedFingerprint(value)
        }
        if let attributes = result as? [String: Any] {
            if let data = attributes[kSecValueData as String] as? Data,
               let value = String(data: data, encoding: .utf8) {
                return normalizedFingerprint(value)
            }
            if let generic = attributes[kSecAttrGeneric as String] as? Data,
               let value = String(data: generic, encoding: .utf8) {
                return normalizedFingerprint(value)
            }
        }
        if let matches = result as? [[String: Any]] {
            for match in matches {
                if let value = fingerprint(from: match as CFTypeRef?) {
                    return value
                }
            }
        }
        return nil
    }

    private func normalizedFingerprint(_ value: String) -> String? {
        let normalized = value.replacingOccurrences(of: "-", with: "").lowercased()
        return normalized.count == 32 && normalized.allSatisfy(\.isHexDigit) ? normalized : nil
    }

    private func keychainQueries(service: String) -> [[String: Any]] {
        [
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "device_fp",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.mutually.wallpaper",
                kSecAttrAccount as String: "device_fp",
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: "device_fp",
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ],
            [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrGeneric as String: Data("device_fp".utf8),
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
        ]
    }

    private func saveFingerprintToKeychain(_ value: String, service: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "device_fp"
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        if status == errSecDuplicateItem {
            SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
    }

    private func merge(_ newItems: [RemoteWallpaper]) {
        var byID = Dictionary(uniqueKeysWithValues: wallpapers.map { ($0.id, $0) })
        newItems.forEach { byID[$0.id] = $0 }
        wallpapers = byID.values.sorted { $0.id > $1.id }
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.badResponse
        }
        guard 200..<300 ~= http.statusCode else {
            throw CatalogError.http(status: http.statusCode, message: serverMessage(from: data))
        }
    }

    private func serverMessage(from data: Data?) -> String? {
        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return nil
        }
        return (dictionary["message"] as? String) ?? (dictionary["error"] as? String)
    }
}

private enum CatalogError: LocalizedError {
    case badResponse
    case http(status: Int, message: String?)
    case invalidPackage
    case server(String)

    var errorDescription: String? {
        switch self {
        case .badResponse: return "服务器响应异常"
        case .http(let status, let message):
            return message.map { "下载服务返回 HTTP \(status)：\($0)" } ?? "下载服务暂时不可用（HTTP \(status)），请稍后重试"
        case .invalidPackage: return "服务器返回的不是有效的 .tendies 文件"
        case .server(let message): return message
        }
    }
}
