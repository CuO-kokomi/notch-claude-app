import SwiftUI

// 展开态玻璃质感的两套风格，右键菜单切换；持久化在 UserDefaults。
// 两套都是深色振动玻璃（白字内容才读得清）；区别在通透程度。
enum GlassStyle: String {
    case deep    // 厚玻璃：更暗更实，对比最好（像聚焦搜索 / 深色菜单）
    case sheer   // 薄玻璃：更通透，背后桌面透出更多色与光

    static let key = "glassStyle"
    static var current: GlassStyle {
        GlassStyle(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .deep
    }
}

// 面板外壳：用 NSVisualEffectView 的 behind-window 暗色振动模糊，真实把背后桌面虚化透上来。
// 原生 .glassEffect 天生偏亮、与白字内容冲突，这里不用它。
struct GlassPlate<S: Shape>: View {
    let shape: S
    var style: GlassStyle = .current

    var body: some View {
        VisualEffectBackground(material: style == .deep ? .hudWindow : .fullScreenUI)
            // 轻微加深，稳住白字对比；薄玻璃加得少，保留通透。
            .overlay(shape.fill(.black.opacity(style == .deep ? 0.20 : 0.08)))
            .clipShape(shape)
            .overlay(rim)
    }

    // 顶部高光边：上沿亮、下沿暗，模拟光从上方打在玻璃边缘。
    private var rim: some View {
        shape.stroke(
            LinearGradient(
                colors: [.white.opacity(0.28), .white.opacity(0.06), .white.opacity(0.02)],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: 1
        )
    }
}

// AppKit 振动模糊背景，behindWindow 采样桌面与其它窗口；深色外观，配白字内容。
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

// 组件卡片"浮片"：外壳玻璃之上的半透明亮色块（像控制中心的圆角片），不叠第二层模糊。
struct WidgetCardSurface: View {
    var style: GlassStyle = .current
    private let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        shape
            .fill(.white.opacity(style == .sheer ? 0.16 : 0.12))
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.06)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            )
    }
}
