import Foundation
import Combine
import Security

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

@MainActor
final class WallpaperCatalogModel: ObservableObject {
    @Published private(set) var wallpapers: [RemoteWallpaper] = []
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
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
            errorMessage = nil
        } catch {
            errorMessage = "壁纸下载失败：\(error.localizedDescription)（设备标识：\(fingerprintSource) \(fingerprintHint)；授权请求：\(grantResult)）"
        }
    }

    private func resolveDownloadURL(for item: RemoteWallpaper) async throws -> URL {
        if let direct = item.downloadURL { return direct }

        let fingerprint = deviceFingerprint()
        // The no-ads build already skips the ad-grant flow. Calling the grant
        // endpoint here generates an encoded card_id that this API rejects.
        grantResult = "跳过（无广告模式）"

        var components = URLComponents(url: baseURL.appendingPathComponent("get_download_url.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "card_id", value: String(item.id)),
            URLQueryItem(name: "device_fp", value: fingerprint)
        ]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response, data: data)
        let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
        if let url = decoded.url ?? decoded.downloadURL ?? decoded.downURL ?? decoded.data?.url ?? decoded.data?.downloadURL ?? decoded.data?.downURL {
            return url
        }
        let serverError = decoded.error ?? decoded.message ?? decoded.data?.message ?? "服务端未返回下载地址"
        if serverError == "ad_unlock_required" {
            throw CatalogError.server("服务器未认可当前设备指纹；下载地址接口要求先完成有效授权")
        }
        throw CatalogError.server(serverError)
    }

    private func deviceFingerprint() -> String {
        let key = "com.mutually.wallpaper.device"
        for query in keychainQueries(service: key) {
            var result: CFTypeRef?
            if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
               let normalized = fingerprint(from: result) {
                fingerprintSource = "Keychain"
                fingerprintHint = String(normalized.prefix(8))
                UserDefaults.standard.set(normalized, forKey: key)
                return normalized
            }
        }

        if let existing = UserDefaults.standard.string(forKey: key),
           let normalized = normalizedFingerprint(existing) {
            fingerprintSource = "UserDefaults"
            fingerprintHint = String(normalized.prefix(8))
            saveFingerprintToKeychain(normalized, service: key)
            return normalized
        }

        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        fingerprintSource = "新生成"
        fingerprintHint = String(value.prefix(8))
        UserDefaults.standard.set(value, forKey: key)
        saveFingerprintToKeychain(value, service: key)
        return value
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
