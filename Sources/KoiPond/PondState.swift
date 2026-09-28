import AppKit
import AVFoundation
import Combine
import SwiftUI

final class PondState: ObservableObject {
    private let defaults: UserDefaults

    @Published var scene: PondScene { didSet { defaults.set(scene.rawValue, forKey: "KoiPond.scene") } }
    @Published var night: Bool { didSet { defaults.set(night, forKey: "KoiPond.night") } }
    /// Keeps the control bar on screen instead of tucking it away.
    @Published var toolbarPinned: Bool { didSet { defaults.set(toolbarPinned, forKey: "KoiPond.toolbarPinned") } }
    @Published var toolbarRevealed = true
    /// Interactive covers the desktop icons so the pond can take clicks; passthrough gives them back.
    @Published var interactive: Bool { didSet { defaults.set(interactive, forKey: "KoiPond.interactive") } }
    @Published private(set) var caption: Caption?
    /// Menu bar and Dock insets, so overlays never slide under them.
    @Published var safeTop: CGFloat = 25
    @Published var safeBottom: CGFloat = 0
    @Published var editorOpen = false
    // Read by the scenes only; publishing them would redraw the whole overlay on every tap.
    var counts: [PondScene: Int] = [:]

    // Fish editor
    @Published var customStrokes: [InkStroke] = []
    @Published var brushColor = Palette.vermilion
    @Published var brushWidth: CGFloat = 0.09
    @Published var newFishColor = Palette.editorBodies[0]

    private(set) var customFish: [KoiSpec] = []
    let fishAdded = PassthroughSubject<KoiSpec, Never>()
    let customFishReleased = PassthroughSubject<Void, Never>()
    static let maxCustomFish = 20

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scene = PondScene(rawValue: defaults.string(forKey: "KoiPond.scene") ?? "") ?? .pond
        night = defaults.bool(forKey: "KoiPond.night")
        toolbarPinned = defaults.bool(forKey: "KoiPond.toolbarPinned")
        interactive = defaults.object(forKey: "KoiPond.interactive") as? Bool ?? true
        if let data = defaults.data(forKey: "KoiPond.customFish"),
           let saved = try? JSONDecoder().decode([KoiSpec].self, from: data) {
            customFish = saved
        }
    }

    func bump(_ scene: PondScene) -> Int {
        let value = counts[scene, default: 0] + 1
        counts[scene] = value
        return value
    }

    var hasCustomFish: Bool { !customFish.isEmpty }

    struct Caption: Equatable {
        var id = UUID()
        var title: String
        var detail: String
    }

    private var captionTimer: Timer?

    func showCaption(_ title: String, _ detail: String, seconds: TimeInterval = 3.8) {
        caption = Caption(title: title, detail: detail)
        captionTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in self?.caption = nil }
        RunLoop.main.add(timer, forMode: .common)
        captionTimer = timer
    }

    func addCustomFish() {
        let spec = KoiSpec(body: newFishColor, mark: brushColor, scale: 1.0, speed: 0.95, pattern: .custom, strokes: customStrokes)
        customFish.append(spec)
        if customFish.count > Self.maxCustomFish { customFish.removeFirst(customFish.count - Self.maxCustomFish) }
        saveCustomFish()
        customStrokes = []
        editorOpen = false
        fishAdded.send(spec)
    }

    func releaseCustomFish() {
        customFish = []
        saveCustomFish()
        customFishReleased.send()
    }

    private func saveCustomFish() {
        if let data = try? JSONEncoder().encode(customFish) { defaults.set(data, forKey: "KoiPond.customFish") }
    }
}

final class MusicController: ObservableObject {
    @Published private(set) var isOn = false
    @Published private(set) var trackName = "尚未添加配乐"
    @Published private(set) var hasTrack = false
    /// Opening a file and waking the audio device can take seconds (iCloud, a sleeping Bluetooth
    /// speaker), so the player lives on its own queue and the main thread never waits on it.
    private let audioQueue = DispatchQueue(label: "KoiPond.audio", qos: .userInitiated)
    private var player: AVAudioPlayer?
    private var loading = false

    init() {
        if let savedPath = UserDefaults.standard.string(forKey: "KoiPond.musicPath") {
            load(URL(fileURLWithPath: savedPath), start: false)
        }
    }

    func addTrack() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "选择背景音乐"
        panel.prompt = "添加配乐"
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Not runModal: a modal session would freeze the pond until the panel closes.
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.load(url, start: true)
        }
    }

    func toggle() {
        guard hasTrack else { if !loading { addTrack() }; return }
        isOn.toggle()
        let on = isOn
        audioQueue.async { [weak self] in
            guard let player = self?.player else { return }
            if on { player.play() } else { player.pause() }
        }
    }

    private func load(_ url: URL, start: Bool) {
        loading = true
        audioQueue.async { [weak self] in
            guard let self else { return }
            // A saved track that has since been deleted is skipped quietly at launch.
            let missing = !FileManager.default.fileExists(atPath: url.path)
            let audio = missing ? nil : try? AVAudioPlayer(contentsOf: url)
            if let audio {
                audio.numberOfLoops = -1
                audio.volume = 0.28
                audio.prepareToPlay()
                self.player?.stop()
                self.player = audio
                if start { audio.play() }
            }
            DispatchQueue.main.async {
                self.loading = false
                if audio != nil {
                    self.hasTrack = true
                    self.trackName = url.deletingPathExtension().lastPathComponent
                    UserDefaults.standard.set(url.path, forKey: "KoiPond.musicPath")
                    self.isOn = start
                } else if !missing || start {
                    self.trackName = "这首音乐读不出来，换一首试试"
                    self.isOn = false
                }
            }
        }
    }
}
