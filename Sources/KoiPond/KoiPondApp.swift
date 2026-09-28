import AppKit
import Combine
import SpriteKit
import SwiftUI

@main
enum KoiPondMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

/// Debug switches, read from the environment. None of them are needed for normal use.
struct DebugOptions {
    let env = ProcessInfo.processInfo.environment
    var scene: PondScene? { env["KOI_SCENE"].flatMap { key in PondScene.allCases.first { $0.key == key } } }
    var snapshotPath: String? { env["KOI_SNAPSHOT"] }
    var snapshotDelay: TimeInterval { env["KOI_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 3 }
    var showStats: Bool { env["KOI_STATS"] == "1" }
    var fps: Int? { env["KOI_FPS"].flatMap(Int.init) }
    var night: Bool? { env["KOI_NIGHT"].map { $0 == "1" } }
    var openEditor: Bool { env["KOI_EDITOR"] == "1" }
    var showToolbar: Bool? { env["KOI_TOOLBAR"].map { $0 == "1" } }
    /// Normalised points (0...1, y from the top) to tap shortly after launch, e.g. "0.5,0.5;0.3,0.6".
    var taps: [CGPoint] { points(env["KOI_TAPS"]) }
    var pointer: CGPoint? { points(env["KOI_POINTER"]).first }
    /// Feeds synthetic clicks through the window to check what receives them, prints the verdict, quits.
    var selfTest: Bool { env["KOI_SELFTEST"] == "1" }
    /// Walks through every scene and toggle, prints main-thread stalls and frame pacing, quits.
    var tour: Bool { env["KOI_TOUR"] == "1" }
    /// Test runs stay invisible, click-through and keep their settings to themselves.
    var quiet: Bool { snapshotPath != nil || selfTest || tour }

    private func points(_ value: String?) -> [CGPoint] {
        (value ?? "").split(separator: ";").compactMap { pair in
            let xy = pair.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            return xy.count == 2 ? CGPoint(x: xy[0], y: xy[1]) : nil
        }
    }
}

final class PondPanel: NSPanel {
    // Only becomes key if a control really needs the keyboard, so clicking the pond never
    // pulls focus away from the app you're typing in.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PondSKView: SKView {
    var onTap: ((CGPoint) -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func scenePoint(_ event: NSEvent) -> CGPoint? {
        guard let scene else { return nil }
        return scene.convertPoint(fromView: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { onContextMenu?(event); return }
        if let p = scenePoint(event) { onTap?(p) }
    }

    override func mouseDragged(with event: NSEvent) {
        if let p = scenePoint(event) { onDrag?(p) }
    }

    override func rightMouseDown(with event: NSEvent) { onContextMenu?(event) }
}

/// Only takes clicks inside the regions the SwiftUI overlay reports; everything else falls
/// through to the pond underneath.
final class OverlayHostingView: NSHostingView<OverlayView> {
    var regions: [String: CGRect] = [:]

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func topLeftPoint(fromWindow point: CGPoint) -> CGPoint {
        let local = convert(point, from: nil)
        return isFlipped ? local : CGPoint(x: local.x, y: bounds.height - local.y)
    }

    func region(containing topLeft: CGPoint, inset: CGFloat = 0) -> String? {
        regions.first { $0.value.insetBy(dx: -inset, dy: -inset).contains(topLeft) }?.key
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let inWindow = superview.convert(point, to: nil)
        guard region(containing: topLeftPoint(fromWindow: inWindow)) != nil else { return nil }
        return super.hitTest(point)
    }
}

/// Hosts the fish editor; takes the first click so drawing starts on the first stroke.
final class EditorHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let debug = DebugOptions()
    private lazy var state = PondState(defaults: debug.quiet ? Self.scratchDefaults() : .standard)
    private let music = MusicController()

    /// A fresh, throwaway settings store for test runs.
    private static func scratchDefaults() -> UserDefaults {
        let name = "KoiPond.test"
        UserDefaults.standard.removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }

    private var panel: PondPanel!
    private var skView: PondSKView!
    private var overlay: OverlayHostingView!
    private var editorPanel: PondPanel?
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()
    private var ticker: Timer?

    // Pointer and toolbar bookkeeping, updated by the ticker.
    private var pointerOnPond = false
    private var lastMouse = CGPoint(x: -1, y: -1)
    private var windowLayers: [Int: Int] = [:]
    private var windowLayersCachedAt = Date.distantPast
    private var lastActivity = Date.distantPast
    private var hotZoneSince: Date?
    private var toolbarLastUsed = Date()
    private var toolbarShownUntil = Date().addingTimeInterval(4.5)
    private var hideRequested = false

    private var stage: StageScene? { skView.scene as? StageScene }
    private var pondTaps = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        StallWatchdog.shared.start(logToDisk: !debug.quiet)
        if !debug.quiet { replaceOlderInstances() }
        SpriteLibrary.shared.preloadAll(first: debug.scene ?? state.scene)
        if let scene = debug.scene { state.scene = scene }
        if let night = debug.night { state.night = night }

        buildWindow()
        buildStatusItem()
        applyInteractive()
        present(state.scene, animated: false)
        bindState()

        // Common modes, so the control bar keeps working while a menu is open.
        let ticker = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.tick() }
        ticker.tolerance = 0.01
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        center.addObserver(self, selector: #selector(occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: panel)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(screensChanged), name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        if !debug.quiet {
            state.showCaption(state.scene.rawValue, hint(for: state.scene) + "\n控制栏会自动收起，鼠标移到屏幕顶部中间就会出来", seconds: 6)
        }
        runDebugHooks()
    }

    /// A second copy would stack another full-screen pond on the desktop and double the work.
    private func replaceOlderInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return }
        for app in others { app.terminate() }
        // A copy that has hung never answers the polite request, and its frozen full-screen
        // window would keep the beachball on screen, so it gets force-quit shortly after.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            for app in others where !app.isTerminated { app.forceTerminate() }
        }
    }

    // MARK: Window

    /// Nil for a moment while displays are being reconnected or the lid closes.
    private var pondScreen: NSScreen? { NSScreen.screens.first ?? NSScreen.main }

    private func buildWindow() {
        let screen = pondScreen
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        panel = PondPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.setFrame(frame, display: false)

        let root = NSView(frame: CGRect(origin: .zero, size: frame.size))
        root.autoresizesSubviews = true

        skView = PondSKView(frame: root.bounds)
        skView.autoresizingMask = [.width, .height]
        skView.ignoresSiblingOrder = true
        skView.shouldCullNonVisibleNodes = true
        skView.preferredFramesPerSecond = debug.fps ?? 60
        if debug.showStats {
            skView.showsFPS = true
            skView.showsNodeCount = true
            skView.showsDrawCount = true
        }
        skView.onTap = { [weak self] p in
            self?.pondTaps += 1
            self?.lastActivity = Date()
            StallWatchdog.shared.during("点鱼塘") { self?.stage?.tap(at: p) }
        }
        skView.onDrag = { [weak self] p in
            self?.lastActivity = Date()
            self?.stage?.drag(to: p)
        }
        skView.onContextMenu = { [weak self] event in
            guard let self, let menu = self.statusItem.menu else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: self.skView)
        }
        root.addSubview(skView)

        let view = OverlayView(state: state, music: music,
                               onHitRegions: { [weak self] in self?.overlay?.regions = $0 },
                               onHideToolbar: { [weak self] in self?.hideToolbar() },
                               onRevealToolbar: { [weak self] in self?.revealToolbar(for: 2.5) })
        overlay = OverlayHostingView(rootView: view)
        overlay.frame = root.bounds
        overlay.autoresizingMask = [.width, .height]
        root.addSubview(overlay)

        panel.contentView = root
        if let screen { updateSafeArea(for: screen) }
        if debug.quiet {
            // Test runs render off-screen-ish: invisible and click-through, so they never get in the way.
            panel.alphaValue = 0
        }
        panel.orderFrontRegardless()
    }

    private func updateSafeArea(for screen: NSScreen) {
        // Only write when it changed: every write redraws the whole overlay, and this runs on each Space switch.
        let top = max(0, screen.frame.maxY - screen.visibleFrame.maxY)
        let bottom = max(0, screen.visibleFrame.minY - screen.frame.minY)
        if state.safeTop != top { state.safeTop = top }
        if state.safeBottom != bottom { state.safeBottom = bottom }
    }

    @objc private func screensChanged() {
        guard let panel else { return }
        StallWatchdog.shared.during("屏幕变化") { adjustToScreen(panel) }
    }

    private func adjustToScreen(_ panel: PondPanel) {
        guard let screen = pondScreen else { return }
        if panel.frame != screen.frame { panel.setFrame(screen.frame, display: true) }
        updateSafeArea(for: screen)
        panel.orderFrontRegardless()
    }

    @objc private func occlusionChanged() {
        // Covered by other windows: stop rendering entirely.
        skView.isPaused = !panel.occlusionState.contains(.visible) && !debug.tour
    }

    private func applyInteractive() {
        if state.interactive || debug.snapshotPath != nil && debug.showToolbar == true {
            // Finder draws the desktop icons in a window just above the desktop level and swallows
            // every click there, so the pond has to sit one level higher to receive them.
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.ignoresMouseEvents = false
        } else {
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            panel.ignoresMouseEvents = true
        }
        if debug.quiet { panel.ignoresMouseEvents = true }
        panel.orderFrontRegardless()
    }

    // MARK: Scenes

    private func makeStage(_ scene: PondScene, size: CGSize) -> StageScene {
        switch scene {
        case .pond: PondStage(state: state, size: size)
        case .dance: DanceStage(state: state, size: size)
        case .touch: TouchStage(state: state, size: size)
        }
    }

    private func present(_ scene: PondScene, animated: Bool) {
        StallWatchdog.shared.during("切换到\(scene.rawValue)") { presentNow(scene, animated: animated) }
    }

    private func presentNow(_ scene: PondScene, animated: Bool) {
        let size = skView.bounds.size
        let stage = makeStage(scene, size: CGSize(width: max(size.width, 1), height: max(size.height, 1)))
        stage.pointerSource = { [weak self] in self?.pointerInScene() }
        if animated {
            // Keep the new scene moving while it fades in; by default SpriteKit freezes it for the whole fade.
            let fade = SKTransition.crossFade(withDuration: 0.45)
            fade.pausesIncomingScene = false
            skView.presentScene(stage, transition: fade)
        } else {
            skView.presentScene(stage)
        }
    }

    private func hint(for scene: PondScene) -> String {
        switch scene {
        case .pond: "点水面撒鱼食 · 鼠标停一会儿鱼会游过来 · 戳一下鱼会惊散"
        case .dance: "点一下，牵手转一圈"
        case .touch: "点一下，看看反应"
        }
    }

    private func bindState() {
        state.$scene.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] scene in
            guard let self else { return }
            self.present(scene, animated: true)
            if scene != .pond { self.state.editorOpen = false }
            self.state.showCaption(scene.rawValue, self.hint(for: scene))
        }.store(in: &cancellables)

        state.$night.removeDuplicates().map { _ in () }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in StallWatchdog.shared.during("换昼夜") { self?.stage?.refresh() } }
            .store(in: &cancellables)

        state.$interactive.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] interactive in
            guard let self else { return }
            self.applyInteractive()
            if interactive {
                self.state.showCaption("互动模式", "鱼塘可以点了；桌面图标暂时点不到")
                self.revealToolbar(for: 3)
            } else {
                self.state.editorOpen = false
                self.state.showCaption("穿透模式", "桌面图标能用了；要再逗鱼，点菜单栏的小鱼切回互动", seconds: 5)
            }
        }.store(in: &cancellables)

        state.$editorOpen.removeDuplicates().receive(on: DispatchQueue.main).sink { [weak self] open in
            self?.toolbarLastUsed = Date()
            self?.showEditor(open)
        }.store(in: &cancellables)

        state.fishAdded.receive(on: DispatchQueue.main).sink { [weak self] spec in
            guard let self else { return }
            if let pond = self.stage as? PondStage { pond.introduce(spec) } else { self.state.scene = .pond }
            self.lastActivity = Date()
        }.store(in: &cancellables)

        state.customFishReleased.receive(on: DispatchQueue.main).sink { [weak self] in
            (self?.stage as? PondStage)?.releaseCustomFish()
        }.store(in: &cancellables)
    }

    // MARK: Pointer, toolbar and frame rate

    /// The cursor position in scene points, or nil when it isn't over visible pond water.
    private func pointerInScene() -> CGPoint? {
        if let fixed = debug.pointer {
            return CGPoint(x: fixed.x * skView.bounds.width, y: (1 - fixed.y) * skView.bounds.height)
        }
        guard pointerOnPond, let panel else { return nil }
        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        if overlay.region(containing: overlay.topLeftPoint(fromWindow: windowPoint), inset: 6) != nil { return nil }
        return skView.convert(windowPoint, from: nil)
    }

    /// True when the frontmost thing under the cursor is the pond itself (or the desktop icons
    /// sitting over it), not some other app's window.
    private func computePointerOnPond(_ mouse: CGPoint) -> Bool {
        guard panel.frame.contains(mouse) else { return false }
        let number = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
        if number == panel.windowNumber { return true }
        guard number > 0, let layer = windowLayer(number) else { return false }
        return layer <= Int(CGWindowLevelForKey(.desktopIconWindow))
    }

    /// A window's level hardly ever changes, so ask the WindowServer once per window every few seconds
    /// instead of on every mouse move.
    private func windowLayer(_ number: Int) -> Int? {
        let now = Date()
        if now.timeIntervalSince(windowLayersCachedAt) > 3 {
            windowLayers.removeAll()
            windowLayersCachedAt = now
        }
        if let layer = windowLayers[number] { return layer }
        guard let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(number)) as? [[String: Any]],
              let layer = info.first?[kCGWindowLayer as String] as? Int else { return nil }
        windowLayers[number] = layer
        return layer
    }

    // MARK: Fish editor

    /// The editor gets its own small window above ordinary app windows, so nothing lying over the
    /// pond (even an invisible window from a frozen app) can swallow the brush.
    private func showEditor(_ open: Bool) {
        guard open else { editorPanel?.orderOut(nil); return }
        let editor = editorPanel ?? makeEditorPanel()
        editorPanel = editor
        if let area = pondScreen?.visibleFrame {
            let size = editor.frame.size
            editor.setFrameOrigin(CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
        }
        editor.orderFrontRegardless()
    }

    private func makeEditorPanel() -> PondPanel {
        // Room around the card for its shadow.
        let host = EditorHostingView(rootView: AnyView(FishEditor(state: state).padding(36).environment(\.colorScheme, .dark)))
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let editor = PondPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        editor.level = .floating
        editor.isFloatingPanel = true
        editor.hidesOnDeactivate = false
        editor.becomesKeyOnlyIfNeeded = true
        editor.isOpaque = false
        editor.backgroundColor = .clear
        editor.hasShadow = false
        editor.isReleasedWhenClosed = false
        editor.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle, .fullScreenAuxiliary]
        editor.contentView = host
        if debug.quiet {
            editor.alphaValue = 0
            editor.ignoresMouseEvents = true
        }
        return editor
    }

    private func tick() {
        StallWatchdog.shared.during("指针和控制栏轮询") { tickNow() }
    }

    private func tickNow() {
        guard let panel, panel.occlusionState.contains(.visible) else { return }
        let now = Date()
        let mouse = NSEvent.mouseLocation
        let moved = mouse != lastMouse
        if moved {
            lastMouse = mouse
            pointerOnPond = computePointerOnPond(mouse)
            if pointerOnPond { lastActivity = now }
        }

        updateToolbar(mouse: mouse, now: now)

        // Full frame rate while you're playing with it; half when it's just ambience.
        if debug.fps == nil {
            let busy = now.timeIntervalSince(lastActivity) < 4 || state.editorOpen
            let fps = busy && !ProcessInfo.processInfo.isLowPowerModeEnabled ? 60 : 30
            if skView.preferredFramesPerSecond != fps { skView.preferredFramesPerSecond = fps }
        }
    }

    private func updateToolbar(mouse: CGPoint, now: Date) {
        if let forced = debug.showToolbar {
            if state.toolbarRevealed != forced { state.toolbarRevealed = forced }
            return
        }
        guard state.interactive else { return }
        let windowPoint = panel.convertPoint(fromScreen: mouse)
        let p = overlay.topLeftPoint(fromWindow: windowPoint)
        let width = overlay.bounds.width
        let overBar = pointerOnPond && overlay.region(containing: p, inset: 24) != nil
        let hotZone = pointerOnPond && p.y < state.safeTop + 40 && abs(p.x - width / 2) < max(260, (overlay.regions["toolbar"]?.width ?? 0) / 2 + 40)

        if overBar || state.editorOpen { toolbarLastUsed = now }

        if hideRequested {
            // Stay tucked away until the cursor leaves, or it would pop right back.
            if !hotZone && !overBar { hideRequested = false }
            return
        }

        var reveal = state.toolbarRevealed
        if state.toolbarPinned || state.editorOpen || now < toolbarShownUntil {
            reveal = true
        } else if hotZone || overBar {
            if hotZoneSince == nil { hotZoneSince = now }
            // A short dwell, so passing through on the way to the menu bar doesn't flash the bar.
            if now.timeIntervalSince(hotZoneSince!) > 0.15 { reveal = true; toolbarLastUsed = now }
        } else {
            hotZoneSince = nil
            if now.timeIntervalSince(toolbarLastUsed) > 1.4 { reveal = false }
        }
        if reveal != state.toolbarRevealed { state.toolbarRevealed = reveal }
    }

    private func revealToolbar(for seconds: TimeInterval) {
        hideRequested = false
        toolbarShownUntil = Date().addingTimeInterval(seconds)
        toolbarLastUsed = Date()
        state.toolbarRevealed = true
    }

    private func hideToolbar() {
        state.toolbarPinned = false
        toolbarShownUntil = .distantPast
        hideRequested = true
        state.toolbarRevealed = false
    }

    // MARK: Status menu

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "中秋赏鱼")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "中秋赏鱼"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        StallWatchdog.shared.during("打开菜单") { rebuild(menu) }
    }

    private func rebuild(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector, key: String = "", on: Bool = false, enabled: Bool = true, tag: Int = 0) {
            let it = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: key)
            it.target = self
            it.state = on ? .on : .off
            it.tag = tag
            menu.addItem(it)
        }
        item("互动模式（可以逗鱼）", #selector(setInteractive), on: state.interactive)
        item("穿透模式（桌面图标可用）", #selector(setPassthrough), on: !state.interactive)
        menu.addItem(.separator())
        for (i, scene) in PondScene.allCases.enumerated() {
            item(scene.rawValue, #selector(chooseScene(_:)), key: "\(i + 1)", on: state.scene == scene, tag: i)
        }
        menu.addItem(.separator())
        item("夜晚", #selector(toggleNight), on: state.night)
        item("画一条锦鲤…", #selector(openEditor))
        item("放走我画的锦鲤", #selector(releaseFish), enabled: state.hasCustomFish)
        menu.addItem(.separator())
        item(music.hasTrack ? (music.isOn ? "暂停配乐" : "播放配乐：\(music.trackName)") : "播放配乐", #selector(toggleMusic), on: music.isOn)
        item("添加本地配乐…", #selector(addMusic))
        menu.addItem(.separator())
        item("显示控制栏", #selector(showToolbar), enabled: state.interactive)
        item("控制栏常驻显示", #selector(togglePinned), on: state.toolbarPinned)
        menu.addItem(.separator())
        item("退出鱼塘", #selector(quit), key: "q")
    }

    @objc private func setInteractive() { state.interactive = true }
    @objc private func setPassthrough() { state.interactive = false }
    @objc private func chooseScene(_ sender: NSMenuItem) { state.scene = PondScene.allCases[sender.tag] }
    @objc private func toggleNight() { state.night.toggle(); if state.scene != .pond { state.scene = .pond } }
    @objc private func openEditor() {
        state.interactive = true
        state.scene = .pond
        state.editorOpen = true
    }
    @objc private func releaseFish() { state.releaseCustomFish() }
    @objc private func toggleMusic() { music.toggle() }
    @objc private func addMusic() { music.addTrack() }
    @objc private func showToolbar() { revealToolbar(for: 3) }
    @objc private func togglePinned() {
        state.toolbarPinned.toggle()
        if state.toolbarPinned { revealToolbar(for: 0) }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Debug hooks

    private func runDebugHooks() {
        if debug.openEditor {
            state.customStrokes = [InkStroke(points: [CGPoint(x: 0.15, y: 0.3), CGPoint(x: 0.35, y: 0.55), CGPoint(x: 0.55, y: 0.35)],
                                             color: Palette.vermilion, width: 0.16)]
            state.editorOpen = true
        }
        for (i, tap) in debug.taps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8 + Double(i) * 0.25) { [weak self] in
                guard let self, let stage = self.stage else { return }
                stage.tap(at: CGPoint(x: tap.x * stage.size.width, y: (1 - tap.y) * stage.size.height))
            }
        }
        if debug.selfTest { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.runSelfTest() } }
        if debug.tour { runTour() }
        if let path = debug.snapshotPath {
            DispatchQueue.main.asyncAfter(deadline: .now() + debug.snapshotDelay) { [weak self] in
                self?.writeSnapshot(to: path)
                NSApp.terminate(nil)
            }
        }
    }

    /// Steps through every scene and toggle, printing frame pacing and main-thread stalls for each.
    private func runTour() {
        FrameMeter.shared.enabled = true
        var steps: [(String, () -> Void)] = [("启动后", {})]
        for scene in PondScene.allCases where scene != state.scene {
            steps.append(("首次切到\(scene.rawValue)", { [unowned self] in state.scene = scene }))
        }
        steps += [
            ("回鱼塘", { [unowned self] in state.scene = .pond }),
            ("切夜晚", { [unowned self] in state.night.toggle() }),
            ("切白天", { [unowned self] in state.night.toggle() }),
            ("打开画锦鲤", { [unowned self] in state.editorOpen = true }),
            ("关掉画锦鲤", { [unowned self] in state.editorOpen = false }),
            ("收起控制栏", { [unowned self] in hideToolbar() }),
            ("唤出控制栏", { [unowned self] in revealToolbar(for: 1) }),
            ("重建菜单", { [unowned self] in if let menu = statusItem.menu { menuNeedsUpdate(menu) } }),
            ("连点水面", { [unowned self] in
                for i in 0..<5 { stage?.tap(at: CGPoint(x: skView.bounds.width * (0.3 + 0.1 * Double(i)), y: skView.bounds.height * 0.4)) }
            }),
        ]
        for scene in Array(PondScene.allCases.dropFirst()) + [.pond] {
            steps.append(("再切到\(scene.rawValue)", { [unowned self] in state.scene = scene }))
        }
        steps.append(("屏幕变化", { [unowned self] in screensChanged() }))
        steps.append(("空闲", {}))
        runTourStep(steps, index: 0)
    }

    private func runTourStep(_ steps: [(String, () -> Void)], index: Int) {
        guard index < steps.count else { NSApp.terminate(nil); return }
        let (label, action) = steps[index]
        lastActivity = Date()
        action()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.reportTourStep(label)
            self?.runTourStep(steps, index: index + 1)
        }
    }

    private func reportTourStep(_ label: String) {
        let frames = FrameMeter.shared.drain()
        let stalls = StallWatchdog.shared.drain()
        let seconds = frames.reduce(0, +) / 1000
        let fps = seconds > 0 ? Double(frames.count) / seconds : 0
        let worst = frames.max() ?? 0
        let dropped = frames.filter { $0 > 25 }.count
        var line = "\(label)\t\(Int(fps.rounded()))fps\t最慢一帧 \(Int(worst.rounded()))ms\t掉帧 \(dropped)"
        if !stalls.isEmpty { line += "\t主线程卡住 " + stalls.map { "\(Int($0.ms))ms@\($0.activity)" }.joined(separator: ", ") }
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    private func click(atTopLeft p: CGPoint) {
        let location = CGPoint(x: p.x, y: overlay.bounds.height - p.y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(event)
            }
        }
    }

    private func runSelfTest() {
        var lines: [String] = []
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { lines.append("\(ok ? "PASS" : "FAIL") \(name) \(detail)") }
        let w = overlay.bounds.width, h = overlay.bounds.height

        // Window stacking: the pond has to sit above Finder's desktop-icon window to get clicks.
        let finderIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        check("window level above desktop icons", panel.level.rawValue > finderIconLevel, "level=\(panel.level.rawValue) icons=\(finderIconLevel)")

        state.toolbarRevealed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
            let before = pondTaps
            click(atTopLeft: CGPoint(x: w * 0.5, y: h * 0.6))
            check("click on water reaches the pond", pondTaps == before + 1, "taps=\(pondTaps - before)")

            guard let bar = overlay.regions["toolbar"] else { check("toolbar reported its hit region", false); return finish() }
            check("toolbar reported its hit region", true, "\(bar.integral)")
            let beforeBar = pondTaps
            click(atTopLeft: CGPoint(x: bar.minX + 40, y: bar.midY))
            check("click on toolbar stays out of the pond", pondTaps == beforeBar)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                check("first scene pill switches scene", state.scene == .pond, "scene=\(state.scene.key)")
                // The pond adds buttons, so the bar is wider now.
                let bar = overlay.regions["toolbar"] ?? bar
                click(atTopLeft: CGPoint(x: bar.maxX - 18, y: bar.midY))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [self] in
                    check("hide button tucks the toolbar away", !state.toolbarRevealed && overlay.regions["toolbar"] == nil,
                          "revealed=\(state.toolbarRevealed) regions=\(overlay.regions.keys.sorted())")
                    let beforeHandle = pondTaps
                    if let handle = overlay.regions["handle"] {
                        click(atTopLeft: CGPoint(x: handle.midX, y: handle.midY))
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                            check("handle click brings the toolbar back", state.toolbarRevealed && pondTaps == beforeHandle)
                            checkEditor()
                        }
                    } else {
                        check("handle reported its hit region", false)
                        finish()
                    }
                }
            }
        }

        // The editor sits above ordinary app windows, and a stroke drawn in it is kept.
        func checkEditor() {
            state.customStrokes = []
            state.editorOpen = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                guard let editor = editorPanel, editor.isVisible else { check("editor window opens", false); return finish() }
                check("editor window sits above app windows", editor.level.rawValue > NSWindow.Level.normal.rawValue, "level=\(editor.level.rawValue)")
                // Across the middle of the canvas: 36pt shadow margin + 20pt padding + title row, then half the canvas.
                let y = editor.frame.height - (36 + 20 + 24 + 14 + 135)
                let xs = stride(from: editor.frame.width / 2 - 90, through: editor.frame.width / 2 + 90, by: 15).map { $0 }
                for (i, x) in xs.enumerated() {
                    let type: NSEvent.EventType = i == 0 ? .leftMouseDown : i == xs.count - 1 ? .leftMouseUp : .leftMouseDragged
                    if let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: editor.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        editor.sendEvent(event)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    check("a stroke drawn in the editor is kept", state.customStrokes.count == 1,
                          "strokes=\(state.customStrokes.count) points=\(state.customStrokes.first?.points.count ?? 0)")
                    state.editorOpen = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                        check("closing the editor hides its window", !editor.isVisible)
                        finish()
                    }
                }
            }
        }

        func finish() {
            FileHandle.standardError.write((lines.joined(separator: "\n") + "\n").data(using: .utf8)!)
            NSApp.terminate(nil)
        }
    }

    private func writeSnapshot(to path: String) {
        guard let scene = skView.scene, let texture = skView.texture(from: scene) else { NSLog("KoiPond: snapshot failed"); return }
        let base = texture.cgImage()
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        if let rep = overlay.bitmapImageRepForCachingDisplay(in: overlay.bounds) {
            overlay.cacheDisplay(in: overlay.bounds, to: rep)
            if let image = rep.cgImage { ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h)) }
        }
        if let editor = editorPanel, editor.isVisible, let host = editor.contentView,
           let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            let scale = CGFloat(w) / panel.frame.width
            let f = editor.frame.offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            if let image = rep.cgImage {
                ctx.draw(image, in: CGRect(x: f.minX * scale, y: f.minY * scale, width: f.width * scale, height: f.height * scale))
            }
        }
        guard let out = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
        let stats = "KoiPond snapshot \(path) \(w)x\(h) nodes=\(scene.children.count)"
        FileHandle.standardError.write((stats + "\n").data(using: .utf8)!)
    }
}
