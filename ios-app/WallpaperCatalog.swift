import Foundation
import Combine

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

private struct UnlockGrantResponse: Decodable {
    let success: Bool?
    let ok: Bool?
    let code: Int?
    let message: String?
    let error: String?
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
            let fingerprint = deviceFingerprint()
            await requestFreeUnlock(for: item.id, fingerprint: fingerprint)
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
            errorMessage = "壁纸下载失败：\(error.localizedDescription)"
        }
    }

    private func resolveDownloadURL(for item: RemoteWallpaper) async throws -> URL {
        if let direct = item.downloadURL { return direct }

        let fingerprint = deviceFingerprint()

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
        throw CatalogError.server(decoded.error ?? decoded.message ?? decoded.data?.message ?? "服务端未返回下载地址")
    }

    private func deviceFingerprint() -> String {
        let key = "com.mutually.wallpaper.device"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            let normalized = existing.replacingOccurrences(of: "-", with: "").lowercased()
            if normalized.count == 32 {
                return normalized
            }
        }
        let value = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        UserDefaults.standard.set(value, forKey: key)
        return value
    }

    private func requestFreeUnlock(for id: Int, fingerprint: String) async {
        var components = URLComponents(url: baseURL.appendingPathComponent("free_unlock_grant.php"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "card_id", value: String(id)),
            URLQueryItem(name: "device_fp", value: fingerprint)
        ]
        guard let url = components.url else { return }
        guard let (data, response) = try? await session.data(from: url) else { return }
        guard (response as? HTTPURLResponse).map({ 200..<300 ~= $0.statusCode }) == true else { return }
        _ = try? JSONDecoder().decode(UnlockGrantResponse.self, from: data)
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
