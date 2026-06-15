import SwiftUI

struct WidgetAddView: View {
    @ObservedObject var config: WidgetConfigurationManager
    @Binding var isAddMode: Bool

    // 2 列大图标块；列内项目多时由 ScrollView 滚动，不会撑高整页溢出面板。
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
    // 面板可视区约 2 行（2 列），超过 4 个就有内容滚出视口下方——据此显示滚动提示。
    private static let visibleCapacity = 4

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("组件管理")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Button(action: { isAddMode = false }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.green.opacity(0.72))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                // Left: available to add
                VStack(alignment: .leading, spacing: 4) {
                    Text("可添加")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                    if config.inactiveDescriptors.isEmpty {
                        Text("已全部添加")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.32))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollHintColumn(hasMore: config.inactiveDescriptors.count > Self.visibleCapacity) {
                            LazyVGrid(columns: columns, spacing: 6) {
                                ForEach(config.inactiveDescriptors) { desc in
                                    let disabled = config.activeWidgetIDs.count >= WidgetConfigurationManager.maxWidgets
                                    Button(action: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            config.add(desc.id)
                                        }
                                    }) {
                                        tile(icon: desc.iconName, name: desc.displayName, tint: .green)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(disabled)
                                    .opacity(disabled ? 0.4 : 1)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                // Right: active, click to remove
                VStack(alignment: .leading, spacing: 4) {
                    Text("已添加 \(config.activeWidgetIDs.count)/\(WidgetConfigurationManager.maxWidgets)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                    ScrollHintColumn(hasMore: config.activeDescriptors.count > Self.visibleCapacity) {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(config.activeDescriptors) { desc in
                                let locked = config.activeWidgetIDs.count <= WidgetConfigurationManager.minWidgets
                                Button(action: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        config.remove(desc.id)
                                    }
                                }) {
                                    tile(icon: desc.iconName, name: desc.displayName, tint: .red)
                                }
                                .buttonStyle(.plain)
                                .disabled(locked)
                                .opacity(locked ? 0.4 : 1)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // 2 列下的大图标块：图标 / 文字放大，方块更高。
    private func tile(icon: String, name: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint.opacity(0.78))
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }
}

// 可滚动列：项目数超出可视区时（由 hasMore 决定），底部渐隐 + 向下浮动箭头提示"还有更多"。
private struct ScrollHintColumn<Content: View>: View {
    let hasMore: Bool
    @ViewBuilder let content: Content

    @State private var bob = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                // 底部留白，避免最后一行被渐隐遮罩压住看不清。
                .padding(.bottom, hasMore ? 22 : 0)
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            if hasMore {
                // 只留浮动箭头 + 柔和投影（在玻璃上保证可见），不叠硬边渐隐矩形。
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                    .padding(.bottom, 3)
                    .offset(y: bob ? 2 : -2)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: bob)
                    .allowsHitTesting(false)
                    .onAppear { bob = true }
            }
        }
    }
}
