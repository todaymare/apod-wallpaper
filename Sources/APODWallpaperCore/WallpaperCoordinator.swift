import Foundation

public enum WallpaperCoordinatorError: Error, Equatable, LocalizedError, Sendable {
    case noArchiveCandidate
    case noFavorites
    case noUsableFavorite
    case unsupportedMediaType
    case missingImageURL

    public var errorDescription: String? {
        switch self {
        case .noArchiveCandidate:
            return "No usable APOD was found in the archive."
        case .noFavorites:
            return "No favorites yet."
        case .noUsableFavorite:
            return "Your favorites do not contain a usable image yet."
        case .unsupportedMediaType:
            return "This APOD media type cannot be used as a wallpaper."
        case .missingImageURL:
            return "This APOD does not provide an image URL."
        }
    }
}

@MainActor
public protocol WallpaperApplying: AnyObject, Sendable {
    func apply(imageURL: URL, presentation: WallpaperPresentation) throws
}

@MainActor
public final class WallpaperCoordinator {
    public private(set) var latestAPOD: APOD?
    public private(set) var currentImageURL: URL?
    public private(set) var lastError: Error?
    public private(set) var lastSuccessfulCheckAt: Date?
    public private(set) var emptyStateMessage: String?
    public private(set) var isUpdating = false

    public var wallpaperSource: WallpaperSource
    public var updateInterval: UpdateInterval
    public var nonImageBehavior: NonImageBehavior
    public var preferHighestResolution: Bool
    public var wallpaperPresentation: WallpaperPresentation
    public var automaticUpdates: Bool

    private let client: any APODFetching
    private let store: APODStore
    private let wallpaper: any WallpaperApplying
    private let imageDownloader: any ImageDownloading
    private var navigationCursorID: Int64?

    public init(
        client: any APODFetching,
        store: APODStore,
        wallpaper: any WallpaperApplying,
        imageDownloader: any ImageDownloading = URLSessionImageDownloader(),
        settings: APODSettings = APODSettings()
    ) {
        self.client = client
        self.store = store
        self.wallpaper = wallpaper
        self.imageDownloader = imageDownloader
        self.wallpaperSource = settings.wallpaperSource
        self.updateInterval = settings.updateInterval
        self.nonImageBehavior = settings.nonImageBehavior
        self.preferHighestResolution = settings.preferHighestResolution
        self.wallpaperPresentation = settings.wallpaperPresentation
        self.automaticUpdates = settings.automaticUpdates
        self.navigationCursorID = store.latestNavigationEntry()?.id

        if let navigationEntry = store.latestNavigationEntry(),
           let record = store.record(for: navigationEntry.date) {
            self.latestAPOD = record.apod
            self.currentImageURL = store.cachedImageURL(for: record.apod.date)
        }
    }

    public var settings: APODSettings {
        APODSettings(
            wallpaperSource: wallpaperSource,
            updateInterval: updateInterval,
            nonImageBehavior: nonImageBehavior,
            preferHighestResolution: preferHighestResolution,
            wallpaperPresentation: wallpaperPresentation,
            automaticUpdates: automaticUpdates
        )
    }

    public var currentRecord: APODRecord? {
        guard let latestAPOD else {
            return nil
        }
        return store.record(for: latestAPOD.date)
    }

    public var isCurrentFavorite: Bool {
        currentRecord?.isFavorite ?? false
    }
    public func isFavorite(date: String) -> Bool {
        store.record(for: date)?.isFavorite ?? false
    }

    public func reapplyCurrent() async {
        guard let latestAPOD else {
            return
        }
        do {
            _ = try await display(latestAPOD, recordHistory: false)
        } catch {
            lastError = error
        }
    }


    public func recentRecords() -> [APODRecord] {
        store.recentRecords()
    }

    public func favoriteRecords() -> [APODRecord] {
        store.favoriteRecords()
    }

    public func restoreCachedWallpaper() {
        guard let navigationEntry = store.latestNavigationEntry(),
              let record = store.record(for: navigationEntry.date),
              let imageURL = store.cachedImageURL(for: record.apod.date),
              record.apod.mediaType == .image || record.cachedImageSourceURL != nil else {
            return
        }

        navigationCursorID = navigationEntry.id
        latestAPOD = record.apod
        do {
            try wallpaper.apply(imageURL: imageURL, presentation: wallpaperPresentation)
            currentImageURL = imageURL
            emptyStateMessage = nil
        } catch {
            lastError = error
        }
    }

    public func refresh(force: Bool = false) async {
        guard !isUpdating else {
            return
        }

        isUpdating = true
        lastError = nil
        emptyStateMessage = nil
        defer { isUpdating = false }

        do {
            switch wallpaperSource {
            case .today:
                try await refreshToday(force: force)
            case .archive:
                try await refreshArchive()
            case .favorites:
                try await refreshFavorites()
            }
            lastSuccessfulCheckAt = Date()
        } catch {
            lastError = error
            if currentImageURL == nil {
                restoreCachedWallpaper()
            }
        }
    }

    public func nextWallpaper() async {
        guard !isUpdating else {
            return
        }
        if let navigationCursorID,
           let entry = store.navigationEntry(after: navigationCursorID) {
            await displayNavigationEntry(entry)
            return
        }
        await refresh(force: true)
    }

    public func previousWallpaper() async {
        guard let navigationCursorID,
              let entry = store.navigationEntry(before: navigationCursorID) else {
            return
        }
        await displayNavigationEntry(entry)
    }

    public func showAgain(date: String) async {
        guard let record = store.record(for: date) else {
            return
        }
        do {
            _ = try await displayHistorical(record, recordHistory: true)
        } catch {
            lastError = error
        }
    }

    public func setFavorite(for date: String, isFavorite: Bool) {
        do {
            try store.markFavorite(date: date, isFavorite: isFavorite)
        } catch {
            lastError = error
        }
    }

    @discardableResult
    public func toggleCurrentFavorite() -> Bool {
        guard let latestAPOD else {
            return false
        }
        let newValue = !isCurrentFavorite
        setFavorite(for: latestAPOD.date, isFavorite: newValue)
        return newValue
    }

    public func clearImageCache() {
        do {
            try store.clearImageCache()
            currentImageURL = nil
        } catch {
            lastError = error
        }
    }

    public func cacheSizeBytes() -> Int64 {
        store.cacheSizeBytes()
    }

    private func refreshToday(force: Bool) async throws {
        let apod = try await client.fetchLatest()
        try store.save(apod)

        if !force,
           apod.date == latestAPOD?.date,
           (currentImageURL != nil || effectiveNonImageBehavior(for: .today) == .keepCurrent) {
            latestAPOD = apod
            return
        }
        _ = try await display(apod, recordHistory: true)
    }

    private func refreshArchive() async throws {
        var candidates = try await client.fetchRandom(count: 20)
        if let latestAPOD,
           !candidates.contains(where: { $0.date == latestAPOD.date }) {
            candidates.append(latestAPOD)
        }
        let seenDates = store.seenDates()
        let currentDate = latestAPOD?.date
        let eligible = candidates.filter {
            $0.date != currentDate && canAttempt($0, for: .archive)
        }
        let unseen = eligible.filter { !seenDates.contains($0.date) }
        let orderedCandidates = unseen.shuffled() + eligible.filter {
            !unseen.contains($0)
        }.shuffled()

        guard !orderedCandidates.isEmpty else {
            throw WallpaperCoordinatorError.noArchiveCandidate
        }

        var lastFailure: Error?
        for apod in orderedCandidates {
            do {
                if try await display(apod, recordHistory: true) {
                    return
                }
            } catch {
                lastFailure = error
            }
        }
        throw lastFailure ?? WallpaperCoordinatorError.noArchiveCandidate
    }

    private func refreshFavorites() async throws {
        let records = favoriteRecords()
        guard !records.isEmpty else {
            emptyStateMessage = WallpaperCoordinatorError.noFavorites.localizedDescription
            throw WallpaperCoordinatorError.noFavorites
        }

        let currentDate = latestAPOD?.date
        let eligible = records.filter { canAttempt($0.apod, for: .favorites) }
        let candidates = (eligible.count > 1
            ? eligible.filter { $0.apod.date != currentDate }
            : eligible
        ).shuffled()
        guard !candidates.isEmpty else {
            emptyStateMessage = WallpaperCoordinatorError.noUsableFavorite.localizedDescription
            throw WallpaperCoordinatorError.noUsableFavorite
        }

        var lastFailure: Error?
        for record in candidates {
            do {
                if try await display(record.apod, recordHistory: true) {
                    return
                }
            } catch {
                lastFailure = error
            }
        }
        throw lastFailure ?? WallpaperCoordinatorError.noUsableFavorite
    }

    @discardableResult
    private func display(_ apod: APOD, recordHistory: Bool) async throws -> Bool {
        latestAPOD = apod
        try store.save(apod)

        guard let sourceURL = imageSourceURL(for: apod) else {
            switch effectiveNonImageBehavior(for: wallpaperSource) {
            case .keepCurrent:
                emptyStateMessage = "Today's APOD is not an image. Keeping the current wallpaper."
                return false
            case .skip:
                return false
            case .useThumbnail, .automatic:
                throw WallpaperCoordinatorError.missingImageURL
            }
        }

        let cachedRecord = store.record(for: apod.date)
        let imageURL: URL
        if cachedRecord?.cachedImageSourceURL == sourceURL,
           let cachedImageURL = store.cachedImageURL(for: apod.date) {
            imageURL = cachedImageURL
        } else {
            let data = try await imageDownloader.download(from: sourceURL)
            imageURL = try store.saveImageData(data, for: apod.date)
            try store.save(apod, imageSourceURL: sourceURL)
        }

        try wallpaper.apply(imageURL: imageURL, presentation: wallpaperPresentation)
        currentImageURL = imageURL
        emptyStateMessage = nil
        if recordHistory {
            navigationCursorID = try store.recordShown(apod).id
        }
        return true
    }

    @discardableResult
    private func displayHistorical(
        _ record: APODRecord,
        recordHistory: Bool
    ) async throws -> Bool {
        latestAPOD = record.apod
        let sourceURL: URL?
        if record.apod.mediaType == .image {
            sourceURL = preferredImageURL(for: record.apod)
        } else {
            sourceURL = record.cachedImageSourceURL
        }
        guard let sourceURL else {
            throw WallpaperCoordinatorError.missingImageURL
        }

        let imageURL: URL
        if record.cachedImageSourceURL == sourceURL,
           let cachedImageURL = store.cachedImageURL(for: record.apod.date) {
            imageURL = cachedImageURL
        } else {
            let data = try await imageDownloader.download(from: sourceURL)
            imageURL = try store.saveImageData(data, for: record.apod.date)
            try store.save(record.apod, imageSourceURL: sourceURL)
        }

        try wallpaper.apply(imageURL: imageURL, presentation: wallpaperPresentation)
        currentImageURL = imageURL
        emptyStateMessage = nil
        if recordHistory {
            navigationCursorID = try store.recordShown(record.apod).id
        }
        return true
    }

    private func displayNavigationEntry(_ entry: NavigationEntry) async {
        guard let record = store.record(for: entry.date) else {
            return
        }
        do {
            _ = try await displayHistorical(record, recordHistory: false)
            navigationCursorID = entry.id
        } catch {
            lastError = error
        }
    }

    private func canAttempt(_ apod: APOD, for source: WallpaperSource) -> Bool {
        switch apod.mediaType {
        case .image:
            return true
        case .video:
            return effectiveNonImageBehavior(for: source) == .useThumbnail
                && apod.thumbnailURL != nil
        case .unknown:
            return false
        }
    }


    private func effectiveNonImageBehavior(for source: WallpaperSource) -> NonImageBehavior {
        guard nonImageBehavior == .automatic else {
            return nonImageBehavior
        }
        return source == .today ? .keepCurrent : .skip
    }

    private func imageSourceURL(for apod: APOD) -> URL? {
        switch apod.mediaType {
        case .image:
            return preferredImageURL(for: apod)
        case .video:
            guard effectiveNonImageBehavior(for: wallpaperSource) == .useThumbnail else {
                return nil
            }
            return apod.thumbnailURL
        case .unknown:
            return nil
        }
    }

    private func preferredImageURL(for apod: APOD) -> URL {
        if preferHighestResolution, let hdURL = apod.hdURL {
            return hdURL
        }
        return apod.url
    }
}
