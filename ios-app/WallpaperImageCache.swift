import CryptoKit
import SwiftUI
import UIKit

final class WallpaperImageCache {
    static let shared = WallpaperImageCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let diskDirectory: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskDirectory = caches.appendingPathComponent("WallpaperImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        memory.countLimit = 250
    }

    func image(for url: URL) async -> UIImage? {
        let key = url as NSURL
        if let cached = memory.object(forKey: key) {
            return cached
        }

        let fileURL = diskURL(for: url)
        if let data = try? Data(contentsOf: fileURL), let cached = UIImage(data: data) {
            memory.setObject(cached, forKey: key)
            return cached
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let downloaded = UIImage(data: data) else {
                return nil
            }
            try? data.write(to: fileURL, options: .atomic)
            memory.setObject(downloaded, forKey: key)
            return downloaded
        } catch {
            return nil
        }
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return diskDirectory.appendingPathComponent("\(digest).img")
    }
}

struct CachedWallpaperImage: View {
    let url: URL?

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
            } else {
                Color.secondary.opacity(0.15)
                    .overlay(Image(systemName: "photo"))
            }
        }
        .task(id: url) {
            guard let url else { return }
            isLoading = true
            image = await WallpaperImageCache.shared.image(for: url)
            isLoading = false
        }
    }
}
