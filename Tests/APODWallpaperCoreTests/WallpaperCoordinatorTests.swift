import Foundation
import XCTest
@testable import APODWallpaperCore

@MainActor
final class WallpaperCoordinatorTests: XCTestCase {
    func testTodayUsesHighestResolutionAndRecordsSeenState() async throws {
        let directory = try temporaryDirectory()
        let apod = makeAPOD(
            date: "2026-08-27",
            mediaType: .image,
            hdURL: URL(string: "https://example.com/hd.jpg")
        )
        let store = try APODStore(directoryURL: directory)
        let downloader = RecordingDownloader(data: validImageData)
        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: apod, random: []),
            store: store,
            wallpaper: wallpaper,
            imageDownloader: downloader,
            settings: APODSettings(wallpaperSource: .today)
        )

        await coordinator.refresh()

        XCTAssertEqual(downloader.requestedURLs, [apod.hdURL!])
        XCTAssertEqual(wallpaper.appliedURLs, [store.imageURL(for: apod.date)])
        XCTAssertEqual(store.record(for: apod.date)?.showCount, 1)
        XCTAssertEqual(store.seenDates(), [apod.date])
    }

    func testTodayDoesNotRepeatCurrentAPODOnPeriodicChecks() async throws {
        let directory = try temporaryDirectory()
        let apod = makeAPOD(date: "2026-08-27", mediaType: .image)
        let store = try APODStore(directoryURL: directory)
        let downloader = RecordingDownloader(data: validImageData)
        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: apod, random: []),
            store: store,
            wallpaper: wallpaper,
            imageDownloader: downloader,
            settings: APODSettings(wallpaperSource: .today)
        )

        await coordinator.refresh()
        await coordinator.refresh()

        XCTAssertEqual(downloader.requestedURLs.count, 1)
        XCTAssertEqual(wallpaper.appliedURLs.count, 1)
        XCTAssertEqual(store.record(for: apod.date)?.showCount, 1)
    }

    func testSQLitePersistsFavoritesSeenStateAndRecentMetadata() throws {
        let directory = try temporaryDirectory()
        let apod = makeAPOD(date: "2026-05-20", mediaType: .image)
        let shownAt = Date(timeIntervalSince1970: 1234)
        let store = try APODStore(directoryURL: directory)

        try store.save(apod, imageSourceURL: apod.url)
        _ = try store.recordShown(apod, at: shownAt)
        try store.markFavorite(date: apod.date, isFavorite: true)

        let reopenedStore = try APODStore(directoryURL: directory)
        let record = reopenedStore.record(for: apod.date)
        XCTAssertEqual(record?.isFavorite, true)
        XCTAssertEqual(record?.firstShownAt, shownAt)
        XCTAssertEqual(record?.lastShownAt, shownAt)
        XCTAssertEqual(record?.showCount, 1)
        XCTAssertEqual(reopenedStore.recentRecords().map { $0.apod.date }, [apod.date])
        XCTAssertEqual(reopenedStore.favoriteRecords().map { $0.apod.date }, [apod.date])
    }

    func testArchivePrefersUnseenAPODAndExcludesCurrentDate() async throws {
        let directory = try temporaryDirectory()
        let seen = makeAPOD(date: "2026-05-20", mediaType: .image)
        let unseen = makeAPOD(date: "2026-05-21", mediaType: .image)
        let store = try APODStore(directoryURL: directory)
        try store.save(seen, imageSourceURL: seen.url)
        _ = try store.recordShown(seen)

        let downloader = RecordingDownloader(data: validImageData)
        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: unseen, random: [seen, unseen]),
            store: store,
            wallpaper: wallpaper,
            imageDownloader: downloader,
            settings: APODSettings(wallpaperSource: .archive)
        )

        await coordinator.refresh()

        XCTAssertEqual(coordinator.latestAPOD?.date, unseen.date)
        XCTAssertEqual(wallpaper.appliedURLs, [store.imageURL(for: unseen.date)])
        XCTAssertEqual(store.seenDates(), Set([seen.date, unseen.date]))
    }

    func testFavoritesSourceRedownloadsEvictedFavorite() async throws {
        let directory = try temporaryDirectory()
        let favorite = makeAPOD(date: "2026-05-20", mediaType: .image)
        let store = try APODStore(directoryURL: directory)
        try store.save(favorite, imageSourceURL: favorite.url)
        try store.markFavorite(date: favorite.date, isFavorite: true)
        let downloader = RecordingDownloader(data: validImageData)
        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: favorite, random: []),
            store: store,
            wallpaper: wallpaper,
            imageDownloader: downloader,
            settings: APODSettings(wallpaperSource: .favorites)
        )

        await coordinator.refresh()

        XCTAssertEqual(downloader.requestedURLs, [favorite.url])
        XCTAssertEqual(wallpaper.appliedURLs, [store.imageURL(for: favorite.date)])
    }

    func testTodayVideoKeepsCurrentWallpaperByDefault() async throws {
        let directory = try temporaryDirectory()
        let video = makeAPOD(
            date: "2026-08-27",
            mediaType: .video,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg")
        )
        let downloader = RecordingDownloader(data: validImageData)
        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: video, random: []),
            store: try APODStore(directoryURL: directory),
            wallpaper: wallpaper,
            imageDownloader: downloader,
            settings: APODSettings(wallpaperSource: .today)
        )

        await coordinator.refresh()

        XCTAssertTrue(downloader.requestedURLs.isEmpty)
        XCTAssertTrue(wallpaper.appliedURLs.isEmpty)
        XCTAssertEqual(coordinator.emptyStateMessage, "Today's APOD is not an image. Keeping the current wallpaper.")
    }

    func testArchiveSkipsVideoAndChoosesImage() async throws {
        let directory = try temporaryDirectory()
        let video = makeAPOD(
            date: "2026-05-20",
            mediaType: .video,
            thumbnailURL: URL(string: "https://example.com/thumb.jpg")
        )
        let image = makeAPOD(date: "2026-05-21", mediaType: .image)
        let store = try APODStore(directoryURL: directory)
        let downloader = RecordingDownloader(data: validImageData)
        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: image, random: [video, image]),
            store: store,
            wallpaper: wallpaper,
            imageDownloader: downloader,
            settings: APODSettings(wallpaperSource: .archive)
        )

        await coordinator.refresh()

        XCTAssertEqual(coordinator.latestAPOD?.date, image.date)
        XCTAssertEqual(downloader.requestedURLs, [image.url])
    }

    func testPreviousAndNextUseNavigationHistoryWithoutNewEvents() async throws {
        let directory = try temporaryDirectory()
        let first = makeAPOD(date: "2026-05-20", mediaType: .image)
        let second = makeAPOD(date: "2026-05-21", mediaType: .image)
        let store = try APODStore(directoryURL: directory)
        try store.save(first, imageSourceURL: first.url)
        _ = try store.saveImageData(validImageData, for: first.date)
        _ = try store.recordShown(first)
        try store.save(second, imageSourceURL: second.url)
        _ = try store.saveImageData(validImageData, for: second.date)
        _ = try store.recordShown(second)

        let wallpaper = RecordingWallpaper()
        let coordinator = WallpaperCoordinator(
            client: StubClient(latest: second, random: []),
            store: store,
            wallpaper: wallpaper,
            settings: APODSettings(wallpaperSource: .archive)
        )

        await coordinator.previousWallpaper()
        XCTAssertEqual(coordinator.latestAPOD?.date, first.date)
        await coordinator.nextWallpaper()
        XCTAssertEqual(coordinator.latestAPOD?.date, second.date)
        XCTAssertEqual(store.recentRecords().first?.showCount, 1)
    }

    func testInvalidImageDataNeverEntersCache() throws {
        let directory = try temporaryDirectory()
        let store = try APODStore(directoryURL: directory)

        XCTAssertThrowsError(try store.saveImageData(Data([1, 2, 3]), for: "2026-08-27")) { error in
            XCTAssertEqual(error as? APODStoreError, .invalidImageData)
        }
        XCTAssertNil(store.cachedImageURL(for: "2026-08-27"))
    }

    func testSettingsRoundTrip() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = APODSettingsStore(defaults: defaults)
        let settings = APODSettings(
            wallpaperSource: .favorites,
            updateInterval: .everySixHours,
            nonImageBehavior: .useThumbnail,
            preferHighestResolution: false,
            wallpaperPresentation: .center,
            automaticUpdates: false
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    private func makeAPOD(
        date: String,
        mediaType: APODMediaType,
        hdURL: URL? = nil,
        thumbnailURL: URL? = nil
    ) -> APOD {
        APOD(
            date: date,
            title: "APOD \(date)",
            explanation: "A test APOD.",
            mediaType: mediaType,
            url: URL(string: "https://example.com/\(date).jpg")!,
            hdURL: hdURL,
            thumbnailURL: thumbnailURL
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private var validImageData: Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
    }
}

private struct StubClient: APODFetching {
    let latest: APOD
    let random: [APOD]

    func fetchLatest() async throws -> APOD {
        latest
    }

    func fetch(date: String) async throws -> APOD {
        random.first(where: { $0.date == date }) ?? latest
    }

    func fetchRandom(count: Int) async throws -> [APOD] {
        Array(random.prefix(count))
    }
}

private final class RecordingDownloader: ImageDownloading, @unchecked Sendable {
    let data: Data
    private(set) var requestedURLs: [URL] = []

    init(data: Data) {
        self.data = data
    }

    func download(from url: URL) async throws -> Data {
        requestedURLs.append(url)
        return data
    }
}

@MainActor
private final class RecordingWallpaper: WallpaperApplying {
    private(set) var appliedURLs: [URL] = []

    func apply(imageURL: URL, presentation: WallpaperPresentation) throws {
        appliedURLs.append(imageURL)
    }
}
