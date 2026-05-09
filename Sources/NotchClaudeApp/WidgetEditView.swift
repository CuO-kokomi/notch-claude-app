import SwiftUI

struct WidgetAddView: View {
    @ObservedObject var config: WidgetConfigurationManager
    @Binding var isAddMode: Bool

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

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
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.32))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        LazyVGrid(columns: columns, spacing: 6) {
                            ForEach(config.inactiveDescriptors) { desc in
                                Button(action: {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        config.add(desc.id)
                                    }
                                }) {
                                    VStack(spacing: 3) {
                                        Image(systemName: desc.iconName)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.green.opacity(0.72))
                                        Text(desc.displayName)
                                            .font(.system(size: 8, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.64))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.white.opacity(0.06))
                                    )
                                }
                                .buttonStyle(.plain)
                                .disabled(config.activeWidgetIDs.count >= WidgetConfigurationManager.maxWidgets)
                                .opacity(config.activeWidgetIDs.count >= WidgetConfigurationManager.maxWidgets ? 0.4 : 1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(width: 1)

                // Right: active, click to remove
                VStack(alignment: .leading, spacing: 4) {
                    Text("已添加 \(config.activeWidgetIDs.count)/\(WidgetConfigurationManager.maxWidgets)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(config.activeDescriptors) { desc in
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    config.remove(desc.id)
                                }
                            }) {
                                VStack(spacing: 3) {
                                    Image(systemName: desc.iconName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.red.opacity(0.72))
                                    Text(desc.displayName)
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.64))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.white.opacity(0.06))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(config.activeWidgetIDs.count <= WidgetConfigurationManager.minWidgets)
                            .opacity(config.activeWidgetIDs.count <= WidgetConfigurationManager.minWidgets ? 0.4 : 1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
