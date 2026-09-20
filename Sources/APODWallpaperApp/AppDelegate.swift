import AppKit
import APODWallpaperCore
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore: APODSettingsStore
    private let coordinator: WallpaperCoordinator
    private let loginItemManager = LoginItemManager()
    private var statusItem: NSStatusItem!
    private var refreshTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var launchAtLoginError: Error?
    private var onboardingController: OnboardingWindowController?
    private var detailController: APODDetailWindowController?
    private var recentController: RecentWindowController?
    private var settingsController: SettingsWindowController?

    override init() {
        let settingsStore = APODSettingsStore()
        let settings = settingsStore.load()
        let store: APODStore
        do {
            store = try APODStore()
        } catch {
            fatalError("Could not initialize APOD storage: \(error.localizedDescription)")
        }

        self.settingsStore = settingsStore
        let apiKey = settingsStore.nasaAPIKey ?? "DEMO_KEY"
        self.coordinator = WallpaperCoordinator(
            client: NASAAPODClient(apiKey: apiKey),
            store: store,
            wallpaper: WorkspaceWallpaperApplier(),
            settings: settings
        )

        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: "APOD Wallpaper"
        )
        statusItem.button?.toolTip = "APOD Wallpaper"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator.restoreCachedWallpaper()
        rebuildMenu()

        guard settingsStore.onboardingComplete else {
            showOnboarding()
            return
        }
        startAutomaticUpdates()
        refresh(force: false)
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTask?.cancel()
    }

    @objc private func nextWallpaper(_ sender: Any?) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.nextWallpaper()
            rebuildMenu()
        }
    }

    @objc private func previousWallpaper(_ sender: Any?) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.previousWallpaper()
            rebuildMenu()
        }
    }

    @objc private func setWallpaperNow(_ sender: Any?) {
        if coordinator.latestAPOD == nil {
            refresh(force: true)
        } else {
            reapplyCurrent()
        }
    }
    @objc private func favoriteCurrent(_ sender: Any?) {
        _ = coordinator.toggleCurrentFavorite()
        rebuildMenu()
    }

    @objc private func openTodaysAPOD(_ sender: Any?) {
        guard let url = coordinator.latestAPOD?.pageURL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func readExplanation(_ sender: Any?) {
        guard let apod = coordinator.latestAPOD else { return }
        showDetails(apod: apod, imageURL: coordinator.currentImageURL)
    }

    @objc private func selectSource(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let source = WallpaperSource(rawValue: rawValue) else {
            return
        }
        coordinator.wallpaperSource = source
        persistSettings()
        startAutomaticUpdates()
        refresh(force: true)
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber,
              let interval = UpdateInterval(rawValue: value.doubleValue) else {
            return
        }
        coordinator.updateInterval = interval
        persistSettings()
        startAutomaticUpdates()
        rebuildMenu()
    }

    @objc private func selectNonImageBehavior(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let behavior = NonImageBehavior(rawValue: rawValue) else {
            return
        }
        coordinator.nonImageBehavior = behavior
        persistSettings()
        rebuildMenu()
    }

    @objc private func toggleAutomaticUpdates(_ sender: NSMenuItem) {
        coordinator.automaticUpdates.toggle()
        persistSettings()
        startAutomaticUpdates()
        rebuildMenu()
    }

    @objc private func selectPresentation(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let presentation = WallpaperPresentation(rawValue: rawValue) else {
            return
        }
        coordinator.wallpaperPresentation = presentation
        persistSettings()
        reapplyCurrent()
    }

    @objc private func toggleHighestResolution(_ sender: NSMenuItem) {
        coordinator.preferHighestResolution.toggle()
        persistSettings()
        reapplyCurrent()
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        launchAtLoginError = nil
        do {
            let enabled = !loginItemManager.isEnabled
            try loginItemManager.setEnabled(enabled)
            settingsStore.launchAtLogin = enabled
        } catch {
            launchAtLoginError = error
        }
        rebuildMenu()
    }

    @objc private func openRecent(_ sender: Any?) {
        recentController = RecentWindowController(
            coordinator: coordinator,
            showDetails: { [weak self] record in
                self?.showDetails(apod: record.apod, imageURL: record.cachedImagePath)
            }
        )
        recentController?.showWindow(nil)
    }

    @objc private func openSettings(_ sender: Any?) {
        settingsController = SettingsWindowController(
            settings: coordinator.settings,
            launchAtLogin: loginItemManager.isEnabled,
            cacheSizeBytes: coordinator.cacheSizeBytes(),
            onSettingsChanged: { [weak self] settings in
                self?.apply(settings: settings)
            },
            onLaunchAtLoginChanged: { [weak self] enabled in
                self?.setLaunchAtLogin(enabled)
            },
            onClearCache: { [weak self] in
                self?.coordinator.clearImageCache()
                self?.rebuildMenu()
            }
        )
        settingsController?.showWindow(nil)
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func refresh(force: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.refresh(force: force)
            rebuildMenu()
        }
    }

    private func reapplyCurrent() {
        guard coordinator.latestAPOD != nil else {
            rebuildMenu()
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await coordinator.reapplyCurrent()
            rebuildMenu()
        }
    }

    private func startAutomaticUpdates() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard coordinator.automaticUpdates else {
            return
        }
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: coordinator.updateInterval.rawValue,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(force: false)
            }
        }
    }

    private func apply(settings: APODSettings) {
        coordinator.wallpaperSource = settings.wallpaperSource
        coordinator.updateInterval = settings.updateInterval
        coordinator.nonImageBehavior = settings.nonImageBehavior
        coordinator.preferHighestResolution = settings.preferHighestResolution
        coordinator.wallpaperPresentation = settings.wallpaperPresentation
        coordinator.automaticUpdates = settings.automaticUpdates
        persistSettings()
        startAutomaticUpdates()
        rebuildMenu()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItemManager.setEnabled(enabled)
            settingsStore.launchAtLogin = enabled
        } catch {
            launchAtLoginError = error
        }
        rebuildMenu()
    }

    private func persistSettings() {
        settingsStore.save(coordinator.settings)
    }

    private func showOnboarding() {
        onboardingController = OnboardingWindowController(
            settings: coordinator.settings,
            launchAtLogin: settingsStore.launchAtLogin,
            onStart: { [weak self] settings, launchAtLogin in
                self?.finishOnboarding(settings: settings, launchAtLogin: launchAtLogin)
            }
        )
        onboardingController?.showWindow(nil)
    }

    private func finishOnboarding(settings: APODSettings, launchAtLogin: Bool) {
        settingsStore.onboardingComplete = true
        apply(settings: settings)
        if launchAtLogin {
            setLaunchAtLogin(true)
        }
        startAutomaticUpdates()
        refresh(force: true)
    }

    private func showDetails(apod: APOD, imageURL: URL?) {
        detailController = APODDetailWindowController(
            apod: apod,
            imageURL: imageURL,
            coordinator: coordinator
        )
        detailController?.showWindow(nil)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let heading = NSMenuItem(title: "APOD Wallpaper", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)

        if let apod = coordinator.latestAPOD {
            let title = NSMenuItem(title: apod.title, action: nil, keyEquivalent: "")
            title.isEnabled = false
            if let imageURL = coordinator.currentImageURL,
               let image = NSImage(contentsOf: imageURL) {
                image.size = NSSize(width: 80, height: 50)
                title.image = image
            }
            menu.addItem(title)

            let date = NSMenuItem(title: formattedDate(apod.date), action: nil, keyEquivalent: "")
            date.isEnabled = false
            menu.addItem(date)

            if let copyright = apod.copyright, !copyright.isEmpty {
                let credit = NSMenuItem(title: copyright, action: nil, keyEquivalent: "")
                credit.isEnabled = false
                menu.addItem(credit)
            }
        } else {
            let status = NSMenuItem(title: "No APOD loaded yet", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }

        if let emptyStateMessage = coordinator.emptyStateMessage {
            let status = NSMenuItem(title: emptyStateMessage, action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else if let error = coordinator.lastError {
            let status = NSMenuItem(
                title: "Could not reach NASA: \(error.localizedDescription)",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Set Wallpaper Now", action: #selector(setWallpaperNow(_:))))
        menu.addItem(menuItem("Next Wallpaper", action: #selector(nextWallpaper(_:))))
        menu.addItem(menuItem("Previous Wallpaper", action: #selector(previousWallpaper(_:))))

        let favoriteTitle = coordinator.isCurrentFavorite ? "Unfavorite" : "Favorite"
        let favoriteItem = menuItem(favoriteTitle, action: #selector(favoriteCurrent(_:)))
        favoriteItem.isEnabled = coordinator.latestAPOD != nil
        menu.addItem(favoriteItem)

        let viewItem = menuItem("View APOD", action: #selector(openTodaysAPOD(_:)))
        viewItem.isEnabled = coordinator.latestAPOD != nil
        menu.addItem(viewItem)
        let explanationItem = menuItem("Read Explanation", action: #selector(readExplanation(_:)))
        explanationItem.isEnabled = coordinator.latestAPOD != nil
        menu.addItem(explanationItem)

        menu.addItem(.separator())
        let sourceItem = NSMenuItem(title: "Wallpaper Source", action: nil, keyEquivalent: "")
        sourceItem.submenu = sourceMenu()
        menu.addItem(sourceItem)
        let intervalItem = NSMenuItem(title: "Update", action: nil, keyEquivalent: "")
        intervalItem.submenu = intervalMenu()
        menu.addItem(intervalItem)
        let automaticItem = menuItem(
            "Update Automatically",
            action: #selector(toggleAutomaticUpdates(_:))
        )
        automaticItem.state = coordinator.automaticUpdates ? .on : .off
        menu.addItem(automaticItem)

        menu.addItem(.separator())
        let recentItem = menuItem("Recent…", action: #selector(openRecent(_:)))
        menu.addItem(recentItem)
        let settingsItem = menuItem("Settings…", action: #selector(openSettings(_:)))
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        let loginItem = menuItem("Launch at Login", action: #selector(toggleLaunchAtLogin(_:)))
        loginItem.state = loginItemManager.isEnabled ? .on : .off
        loginItem.toolTip = launchAtLoginError?.localizedDescription
        menu.addItem(loginItem)
        menu.addItem(menuItem("Quit", action: #selector(quit(_:))))

        statusItem.menu = menu
    }

    private func sourceMenu() -> NSMenu {
        let menu = NSMenu()
        for source in WallpaperSource.allCases {
            let item = NSMenuItem(
                title: source.title,
                action: #selector(selectSource(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = source.rawValue
            item.state = coordinator.wallpaperSource == source ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func intervalMenu() -> NSMenu {
        let menu = NSMenu()
        for interval in UpdateInterval.allCases {
            let item = NSMenuItem(
                title: interval.title,
                action: #selector(selectInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = NSNumber(value: interval.rawValue)
            item.state = coordinator.updateInterval == interval ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let presentation = NSMenuItem(title: "Presentation", action: nil, keyEquivalent: "")
        presentation.submenu = presentationMenu()
        menu.addItem(presentation)
        let quality = menuItem(
            "Prefer highest resolution",
            action: #selector(toggleHighestResolution(_:))
        )
        quality.state = coordinator.preferHighestResolution ? .on : .off
        menu.addItem(quality)
        let nonImage = NSMenuItem(title: "Non-image APODs", action: nil, keyEquivalent: "")
        nonImage.submenu = nonImageMenu()
        menu.addItem(nonImage)
        return menu
    }

    private func nonImageMenu() -> NSMenu {
        let menu = NSMenu()
        for behavior in NonImageBehavior.allCases {
            let item = NSMenuItem(
                title: behavior.title,
                action: #selector(selectNonImageBehavior(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = behavior.rawValue
            item.state = coordinator.nonImageBehavior == behavior ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func presentationMenu() -> NSMenu {
        let menu = NSMenu()
        for presentation in WallpaperPresentation.allCases {
            let item = NSMenuItem(
                title: presentation.title,
                action: #selector(selectPresentation(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = presentation.rawValue
            item.state = coordinator.wallpaperPresentation == presentation ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func formattedDate(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: "\(value)T00:00:00Z") else {
            return value
        }
        return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
    }
}

@MainActor
private final class WorkspaceWallpaperApplier: WallpaperApplying, @unchecked Sendable {
    func apply(imageURL: URL, presentation: WallpaperPresentation) throws {
        var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
        switch presentation {
        case .fill:
            options[.imageScaling] = NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue)
            options[.allowClipping] = NSNumber(value: true)
        case .fit:
            options[.imageScaling] = NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue)
            options[.allowClipping] = NSNumber(value: false)
        case .center:
            options[.imageScaling] = NSNumber(value: NSImageScaling.scaleNone.rawValue)
        case .stretch:
            options[.imageScaling] = NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue)
        }

        for screen in NSScreen.screens {
            try NSWorkspace.shared.setDesktopImageURL(
                imageURL,
                for: screen,
                options: options
            )
        }
    }
}

private struct LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
