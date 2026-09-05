import ImageIO
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Process-wide logo memory. `NSCache` is thread-safe; lookup is nonisolated
/// so recycled TV cards can paint the last decode immediately.
private enum TeamLogoMemory {
    static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 200
        return c
    }()
}

actor TeamLogoCache {
    static let shared = TeamLogoCache()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(
            memoryCapacity: 4 * 1024 * 1024,
            diskCapacity: 50 * 1024 * 1024,
            diskPath: "team-logos"
        )
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    nonisolated static func cacheKey(url: URL, maxPixel: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixel.rounded()))"
    }

    nonisolated func cached(for url: URL, maxPixel: CGFloat) -> UIImage? {
        TeamLogoMemory.cache.object(forKey: Self.cacheKey(url: url, maxPixel: maxPixel) as NSString)
    }

    func image(for url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = Self.cacheKey(url: url, maxPixel: maxPixel)
        if let hit = TeamLogoMemory.cache.object(forKey: key as NSString) {
            return hit
        }
        do {
            let (data, _) = try await session.data(from: url)
            guard let img = Self.downsample(data: data, maxPixel: maxPixel) else { return nil }
            TeamLogoMemory.cache.setObject(img, forKey: key as NSString)
            return img
        } catch {
            return nil
        }
    }

    nonisolated static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let srcOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, srcOpts) else { return nil }
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maxPixel.rounded())),
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOpts as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

/// Cached, downsampled team mark. Replaces `AsyncImage` so LazyHStack recycle
/// does not re-decode ESPN 500×500 PNGs for 44–56 pt boxes.
struct TeamLogo<Fallback: View>: View {
    let url: URL?
    var size: CGFloat
    var fallback: Fallback
    @State private var image: UIImage?

    init(url: URL?, size: CGFloat, @ViewBuilder fallback: () -> Fallback) {
        self.url = url
        self.size = size
        self.fallback = fallback()
    }

    init(urlString: String?, size: CGFloat, @ViewBuilder fallback: () -> Fallback) {
        self.url = urlString.flatMap { URL(string: $0) }
        self.size = size
        self.fallback = fallback()
    }

    private var maxPixel: CGFloat { size * 2 }

    var body: some View {
        Group {
            if let img = image ?? syncCached {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .task(id: url?.absoluteString ?? "") {
            guard let url else { return }
            if image != nil || syncCached != nil { return }
            image = await TeamLogoCache.shared.image(for: url, maxPixel: maxPixel)
        }
    }

    private var syncCached: UIImage? {
        guard let url else { return nil }
        return TeamLogoCache.shared.cached(for: url, maxPixel: maxPixel)
    }
}
