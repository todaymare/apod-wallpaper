import Foundation

public enum WallpaperSource: String, CaseIterable, Codable, Sendable {
    case today
    case archive
    case favorites

    public var title: String {
        switch self {
        case .today: return "Today"
        case .archive: return "Archive"
        case .favorites: return "Favorites"
        }
    }
}

public enum UpdateInterval: Double, CaseIterable, Codable, Sendable {
    case hourly = 3600
    case everyThreeHours = 10800
    case everySixHours = 21600
    case everyTwelveHours = 43200
    case daily = 86400

    public var title: String {
        switch self {
        case .hourly: return "Every Hour"
        case .everyThreeHours: return "Every 3 Hours"
        case .everySixHours: return "Every 6 Hours"
        case .everyTwelveHours: return "Every 12 Hours"
        case .daily: return "Daily"
        }
    }
}

public enum NonImageBehavior: String, CaseIterable, Codable, Sendable {
    case automatic
    case skip
    case useThumbnail
    case keepCurrent

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .skip: return "Skip it"
        case .useThumbnail: return "Use thumbnail"
        case .keepCurrent: return "Keep current wallpaper"
        }
    }
}

public enum WallpaperPresentation: String, CaseIterable, Codable, Sendable {
    case fill
    case fit
    case center
    case stretch

    public var title: String {
        rawValue.capitalized
    }
}

public struct APODSettings: Equatable, Sendable {
    public var wallpaperSource: WallpaperSource
    public var updateInterval: UpdateInterval
    public var nonImageBehavior: NonImageBehavior
    public var preferHighestResolution: Bool
    public var wallpaperPresentation: WallpaperPresentation
    public var automaticUpdates: Bool

    public init(
        wallpaperSource: WallpaperSource = .archive,
        updateInterval: UpdateInterval = .hourly,
        nonImageBehavior: NonImageBehavior = .automatic,
        preferHighestResolution: Bool = true,
        wallpaperPresentation: WallpaperPresentation = .fill,
        automaticUpdates: Bool = true
    ) {
        self.wallpaperSource = wallpaperSource
        self.updateInterval = updateInterval
        self.nonImageBehavior = nonImageBehavior
        self.preferHighestResolution = preferHighestResolution
        self.wallpaperPresentation = wallpaperPresentation
        self.automaticUpdates = automaticUpdates
    }
}

public final class APODSettingsStore: @unchecked Sendable {
    private enum Key {
        static let source = "APODWallpaper.wallpaperSource"
        static let interval = "APODWallpaper.updateInterval"
        static let nonImageBehavior = "APODWallpaper.nonImageBehavior"
        static let preferHighestResolution = "APODWallpaper.preferHighestResolution"
        static let presentation = "APODWallpaper.presentation"
        static let automaticUpdates = "APODWallpaper.automaticUpdates"
        static let launchAtLogin = "APODWallpaper.launchAtLogin"
        static let onboardingComplete = "APODWallpaper.onboardingComplete"
        static let nasaAPIKey = "APODWallpaper.nasaAPIKey"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.source: WallpaperSource.archive.rawValue,
            Key.interval: UpdateInterval.hourly.rawValue,
            Key.nonImageBehavior: NonImageBehavior.automatic.rawValue,
            Key.preferHighestResolution: true,
            Key.presentation: WallpaperPresentation.fill.rawValue,
            Key.automaticUpdates: true,
            Key.launchAtLogin: false,
            Key.onboardingComplete: false
        ])
    }

    public func load() -> APODSettings {
        APODSettings(
            wallpaperSource: WallpaperSource(
                rawValue: defaults.string(forKey: Key.source) ?? ""
            ) ?? .archive,
            updateInterval: UpdateInterval(
                rawValue: defaults.double(forKey: Key.interval)
            ) ?? .hourly,
            nonImageBehavior: NonImageBehavior(
                rawValue: defaults.string(forKey: Key.nonImageBehavior) ?? ""
            ) ?? .automatic,
            preferHighestResolution: defaults.bool(forKey: Key.preferHighestResolution),
            wallpaperPresentation: WallpaperPresentation(
                rawValue: defaults.string(forKey: Key.presentation) ?? ""
            ) ?? .fill,
            automaticUpdates: defaults.bool(forKey: Key.automaticUpdates),
        )
    }

    public func save(_ settings: APODSettings) {
        defaults.set(settings.wallpaperSource.rawValue, forKey: Key.source)
        defaults.set(settings.updateInterval.rawValue, forKey: Key.interval)
        defaults.set(settings.nonImageBehavior.rawValue, forKey: Key.nonImageBehavior)
        defaults.set(settings.preferHighestResolution, forKey: Key.preferHighestResolution)
        defaults.set(settings.wallpaperPresentation.rawValue, forKey: Key.presentation)
        defaults.set(settings.automaticUpdates, forKey: Key.automaticUpdates)
    }

    public var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    public var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboardingComplete) }
        set { defaults.set(newValue, forKey: Key.onboardingComplete) }
    }

    public var nasaAPIKey: String? {
        get { defaults.string(forKey: Key.nasaAPIKey) }
        set { defaults.set(newValue, forKey: Key.nasaAPIKey) }
    }
}
