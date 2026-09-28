import AppKit
import SwiftUI

/// Everything drawn over the pond: the auto-hiding control bar and the scene caption. The fish
/// editor has its own window (see `AppDelegate.showEditor`). The hosting view only takes clicks inside the rectangles these views report, so the
/// rest of the screen stays the pond.
struct OverlayView: View {
    static let space = "overlay"
    @ObservedObject var state: PondState
    @ObservedObject var music: MusicController
    var onHitRegions: ([String: CGRect]) -> Void
    var onHideToolbar: () -> Void
    var onRevealToolbar: () -> Void

    var body: some View {
        ZStack {
            Color.clear

            VStack(spacing: 0) {
                if state.interactive {
                    ZStack(alignment: .top) {
                        if state.toolbarRevealed {
                            ControlBar(state: state, music: music, onHide: onHideToolbar)
                                .hitRegion("toolbar")
                                .transition(.move(edge: .top).combined(with: .opacity))
                        } else {
                            ToolbarHandle(reveal: onRevealToolbar)
                                .hitRegion("handle")
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, state.safeTop + 8)
                }
                Spacer(minLength: 0)
                if let caption = state.caption, !state.editorOpen {
                    CaptionCard(caption: caption)
                        .id(caption.id)
                        .transition(.opacity.combined(with: .offset(y: 8)))
                        .padding(.bottom, state.safeBottom + 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: Self.space)
        .onPreferenceChange(HitRegionKey.self) { onHitRegions($0) }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: state.toolbarRevealed)
        .animation(.easeInOut(duration: 0.35), value: state.caption)
        .animation(.easeInOut(duration: 0.2), value: state.interactive)
        .environment(\.colorScheme, .dark)
    }
}

struct HitRegionKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func hitRegion(_ name: String) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: HitRegionKey.self, value: [name: proxy.frame(in: .named(OverlayView.space))])
        })
    }
}

private let gold = Color(red: 0.98, green: 0.82, blue: 0.5)
private let barFill = Color(red: 0.05, green: 0.09, blue: 0.09).opacity(0.62)

// MARK: Control bar

private struct ControlBar: View {
    @ObservedObject var state: PondState
    @ObservedObject var music: MusicController
    var onHide: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(PondScene.allCases) { scene in
                BarButton(title: scene.rawValue, active: state.scene == scene) { state.scene = scene }
            }
            separator
            if state.scene == .pond {
                BarButton(symbol: state.night ? "moon.stars.fill" : "sun.max.fill", title: state.night ? "夜" : "昼",
                          help: state.night ? "切到白天" : "切到夜晚") { state.night.toggle() }
                BarButton(symbol: "paintbrush.pointed.fill", title: "画锦鲤", active: state.editorOpen,
                          help: "画一条自己的锦鲤放进池塘") { state.editorOpen.toggle() }
            }
            if state.scene == .pond { separator }
            BarButton(symbol: music.isOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                      help: music.hasTrack ? (music.isOn ? "暂停配乐：\(music.trackName)" : "播放配乐：\(music.trackName)") : "还没有配乐，点一下选一首")
                { music.toggle() }
            BarButton(symbol: "music.note.list", help: "换一首本地配乐") { music.addTrack() }
            separator
            BarButton(symbol: "cursorarrow.rays", help: "切到穿透模式：鱼塘不再接收点击，桌面图标能用") { state.interactive = false }
            BarButton(symbol: state.toolbarPinned ? "pin.fill" : "pin", active: state.toolbarPinned,
                      help: state.toolbarPinned ? "取消常驻，鼠标离开后自动收起" : "让控制栏一直显示") { state.toolbarPinned.toggle() }
            BarButton(symbol: "chevron.up", help: "收起控制栏，鼠标移到屏幕顶部中间可再唤出") { onHide() }
        }
        .padding(5)
        .background(Capsule().fill(barFill))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .fixedSize()
    }

    private var separator: some View {
        Rectangle().fill(Color.white.opacity(0.16)).frame(width: 1, height: 16).padding(.horizontal, 3)
    }
}

private struct BarButton: View {
    var symbol: String?
    var title: String?
    var active = false
    var help: String?
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)) }
                if let title { Text(title).font(.system(size: 12.5, weight: .medium)) }
            }
            .padding(.horizontal, title == nil ? 9 : 11)
            .frame(minWidth: 30, minHeight: 28)
            .foregroundStyle(active ? Color.black.opacity(0.82) : Color.white.opacity(0.92))
            .background(Capsule().fill(active ? gold : Color.white.opacity(hover ? 0.15 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help ?? title ?? "")
        .accessibilityLabel(title ?? help ?? "")
    }
}

/// What's left of the bar when it's tucked away: a short, faint line at the top centre.
private struct ToolbarHandle: View {
    var reveal: () -> Void
    @State private var hover = false

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(hover ? 0.7 : 0.32))
            .frame(width: hover ? 56 : 40, height: 5)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .frame(width: 180, height: 22)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onTapGesture(perform: reveal)
            .animation(.easeOut(duration: 0.15), value: hover)
            .accessibilityElement()
            .accessibilityLabel("显示控制栏")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { reveal() }
    }
}

private struct CaptionCard: View {
    let caption: PondState.Caption

    var body: some View {
        VStack(spacing: 4) {
            Text(caption.title).font(.system(size: 19, weight: .semibold))
            if !caption.detail.isEmpty {
                Text(caption.detail).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.78))
            }
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Color.white)
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(barFill))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 3)
        .allowsHitTesting(false)
    }
}

// MARK: Fish editor

struct FishEditor: View {
    @ObservedObject var state: PondState
    @State private var live: [CGPoint] = []

    private let canvasSize = CGSize(width: 560, height: 270)
    /// The fish art spans x -62...40 and y -27...27 in fish units; centre it in the canvas.
    private let artCenter = CGPoint(x: -11, y: 0)
    private var unit: CGFloat { min(canvasSize.width / 108, canvasSize.height / 58) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("画一条锦鲤").font(.system(size: 17, weight: .semibold))
                Text("在鱼身上画花纹，放进池塘就会游起来").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Button { state.editorOpen = false } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 24, height: 24)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }

            canvas
                .frame(width: canvasSize.width, height: canvasSize.height)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(
                    LinearGradient(colors: [Color(red: 0.36, green: 0.66, blue: 0.58), Color(red: 0.2, green: 0.46, blue: 0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 22) {
                swatches("鱼身", Palette.editorBodies, selection: $state.newFishColor)
                swatches("墨色", Palette.editorInks, selection: $state.brushColor)
                HStack(spacing: 8) {
                    Text("笔粗").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
                    Slider(value: $state.brushWidth, in: 0.04...0.24).frame(width: 110)
                }
            }

            HStack(spacing: 8) {
                editorButton("撤销", symbol: "arrow.uturn.backward", enabled: !state.customStrokes.isEmpty) { state.customStrokes.removeLast() }
                editorButton("重画", symbol: "trash", enabled: !state.customStrokes.isEmpty) { state.customStrokes.removeAll() }
                Spacer()
                if state.customStrokes.isEmpty {
                    Text("先画几笔花纹").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.5))
                }
                Button { state.addCustomFish() } label: {
                    Label("放入池塘", systemImage: "drop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 16).frame(height: 32)
                        .foregroundStyle(Color.black.opacity(0.82))
                        .background(Capsule().fill(gold))
                        .opacity(state.customStrokes.isEmpty ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(state.customStrokes.isEmpty)
            }
        }
        .foregroundStyle(Color.white)
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(red: 0.06, green: 0.1, blue: 0.1).opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .fixedSize()
    }

    private var previewSpec: KoiSpec {
        var strokes = state.customStrokes
        if !live.isEmpty { strokes.append(InkStroke(points: live, color: state.brushColor, width: state.brushWidth)) }
        return KoiSpec(body: state.newFishColor, mark: state.brushColor, scale: 1, speed: 1, pattern: .custom, strokes: strokes)
    }

    private var canvas: some View {
        let spec = previewSpec
        return Canvas { ctx, size in
            let u = unit
            ctx.withCGContext { cg in
                cg.translateBy(x: size.width / 2, y: size.height / 2)
                cg.scaleBy(x: u, y: -u)
                cg.translateBy(x: -artCenter.x, y: -artCenter.y)
                cg.addPath(FishArt.tailPath)
                cg.setFillColor(spec.body.alpha(0.82).cgColor)
                cg.fillPath()
                FishArt.drawBody(spec, in: cg)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = normalized(value.location)
                if let last = live.last, hypot((p.x - last.x) * 66, (p.y - last.y) * 31) < 0.35 { return }
                live.append(p)
            }
            .onEnded { _ in
                if !live.isEmpty {
                    state.customStrokes.append(InkStroke(points: live, color: state.brushColor, width: state.brushWidth))
                }
                live = []
            })
    }

    /// View point → body-box coordinates (0...1, y down), the same space FishArt paints strokes in.
    private func normalized(_ v: CGPoint) -> CGPoint {
        let u = unit
        let fx = (v.x - canvasSize.width / 2) / u + artCenter.x
        let fy = (canvasSize.height / 2 - v.y) / u + artCenter.y
        let box = FishArt.bodyBox
        return CGPoint(x: (fx - box.minX) / box.width, y: (box.maxY - fy) / box.height)
    }

    private func swatches(_ title: String, _ colors: [RGBA], selection: Binding<RGBA>) -> some View {
        HStack(spacing: 7) {
            Text(title).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.7))
            ForEach(colors, id: \.self) { color in
                Button { selection.wrappedValue = color } label: {
                    Circle().fill(color.color)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(Color.white.opacity(selection.wrappedValue == color ? 0.95 : 0.25),
                                                       lineWidth: selection.wrappedValue == color ? 2 : 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func editorButton(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 12).frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}
