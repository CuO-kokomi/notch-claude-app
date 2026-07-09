import SwiftUI

// 会话管理全屏模式：项目分组浏览 / 搜索（可选全文）/ resume 历史会话。
// 进出流程与「组件管理」add mode 一致，由 NotchPanelView 的 isSessionMode 驱动。
struct SessionManagerView: View {
    @ObservedObject var provider: SessionHistoryProvider
    @Binding var isSessionMode: Bool

    @State private var query = ""
    @State private var fullTextEnabled = false
    @State private var fullTextHits: Set<String>? = nil
    @State private var isSearching = false
    @State private var expandedGroups: Set<String> = []
    @State private var didInitExpansion = false
    @State private var resumedID: String?
    @State private var failedID: String?
    @State private var hoveredID: String?
    @State private var searchDebounce: DispatchWorkItem?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @AppStorage(SessionHistoryProvider.skipPermissionsKey) private var skipPermissions = false

    var body: some View {
        VStack(spacing: 8) {
            header
            searchBar
            sessionList
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .onAppear {
            provider.refresh()
            // 等入场 transition + 窗口 makeKey 完成后再聚焦，过早聚焦装配不上 field editor。
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { searchFocused = true }
        }
        .onChange(of: query) { _ in scheduleSearch() }
        .onChange(of: fullTextEnabled) { _ in scheduleSearch() }
        .onChange(of: provider.groups.count) { _ in initExpansionIfNeeded() }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 12) {
            Text("会话管理")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            Text("\(provider.totalCount) 会话 · \(provider.groups.count) 项目")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
            if provider.isScanning || isSearching {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
            }
            Spacer()
            checkbox("全文搜索", isOn: $fullTextEnabled, tint: .white.opacity(0.72))
            checkbox("跳过权限", isOn: $skipPermissions, tint: .orange)
            Button(action: exitMode) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
    }

    // 面板风格的自绘 checkbox（系统 Toggle 在暗玻璃上样式突兀）。
    private func checkbox(_ label: String, isOn: Binding<Bool>, tint: Color) -> some View {
        Button(action: { isOn.wrappedValue.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? tint : .white.opacity(0.42))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOn.wrappedValue ? tint : .white.opacity(0.56))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 搜索框

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
            TextField(fullTextEnabled ? "全文搜索会话内容…" : "搜索标题 / 路径…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .focused($searchFocused)
                .onExitCommand {
                    searchFocused = false
                    exitMode()
                }
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(0.08))
        )
    }

    // MARK: - 列表

    private var filteredGroups: [SessionGroup] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var groups = provider.groups
        if let hits = fullTextHits {
            groups = groups.compactMap { group in
                var g = group
                g.sessions = g.sessions.filter { hits.contains($0.path) }
                return g.sessions.isEmpty ? nil : g
            }
        } else if !q.isEmpty {
            groups = groups.compactMap { group in
                var g = group
                g.sessions = g.sessions.filter {
                    ($0.title + $0.firstMessage + $0.cwd).localizedCaseInsensitiveContains(q)
                }
                return g.sessions.isEmpty ? nil : g
            }
        }
        return groups
    }

    private var sessionList: some View {
        let groups = filteredGroups
        let filtering = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return Group {
            if groups.isEmpty {
                Text(provider.totalCount == 0 ? "暂无会话记录" : "没有匹配的会话")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(groups) { group in
                            groupHeader(group)
                            // 过滤中命中组全展开，浏览时按用户手动展开集。
                            if filtering || expandedGroups.contains(group.cwd) {
                                ForEach(group.sessions) { session in
                                    sessionRow(session)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func groupHeader(_ group: SessionGroup) -> some View {
        Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                if expandedGroups.contains(group.cwd) {
                    expandedGroups.remove(group.cwd)
                } else {
                    expandedGroups.insert(group.cwd)
                }
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.42))
                    .rotationEffect(.degrees(expandedGroups.contains(group.cwd) ? 90 : 0))
                Circle()
                    .fill(SessionHistoryProvider.projectColor(group.cwd))
                    .frame(width: 7, height: 7)
                Text(group.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Text(group.cwd)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.42))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(group.sessions.count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.56))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.white.opacity(0.1)))
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(SessionHistoryProvider.timeAgo(session.mtime))
                    Text("\(session.messageCount) 条消息")
                    if !session.branch.isEmpty {
                        Text("⎇ \(session.branch)")
                            .foregroundStyle(.orange.opacity(0.72))
                    }
                    if !session.firstMessage.isEmpty {
                        Text(session.firstMessage.replacingOccurrences(of: "\n", with: " "))
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            resumeButton(session)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .padding(.leading, 14)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(hoveredID == session.id ? 0.09 : 0.05))
        )
        .onHover { hoveredID = $0 ? session.id : nil }
        .animation(.easeOut(duration: 0.12), value: hoveredID)
    }

    private func resumeButton(_ session: SessionSummary) -> some View {
        let state: (text: String, color: Color) =
            resumedID == session.id ? ("已打开", .green)
            : failedID == session.id ? ("失败", .red)
            : ("打开", .white.opacity(0.85))
        return Button(action: { resume(session) }) {
            Text(state.text)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(state.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 动作

    private func resume(_ session: SessionSummary) {
        if provider.resume(session, skipPermissions: skipPermissions) {
            resumedID = session.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if resumedID == session.id { resumedID = nil }
            }
        } else {
            failedID = session.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                if failedID == session.id { failedID = nil }
            }
        }
    }

    private func exitMode() {
        searchTask?.cancel()
        isSessionMode = false
    }

    private func initExpansionIfNeeded() {
        guard !didInitExpansion, !provider.groups.isEmpty else { return }
        didInitExpansion = true
        expandedGroups = Set(provider.groups.prefix(2).map(\.cwd))
    }

    // 250ms 防抖；勾了全文且有词才发全文搜索，否则回本地过滤。
    private func scheduleSearch() {
        searchDebounce?.cancel()
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard fullTextEnabled, !q.isEmpty else {
            fullTextHits = nil
            isSearching = false
            return
        }
        let work = DispatchWorkItem {
            searchTask = Task { @MainActor in
                isSearching = true
                let hits = await provider.fullTextSearch(q)
                guard !Task.isCancelled else { return }
                fullTextHits = hits
                isSearching = false
            }
        }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}
