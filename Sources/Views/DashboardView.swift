import SwiftUI

/// 原生儀表板:連線、用量、自動化任務（可啟停/執行）、待核准、已配對裝置、模型、節點、會話
struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var deviceToRemove: PairedDevice?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        connectionCard
                        usageCard
                        modelCard
                        approvalsCard
                        devicesCard
                        cronCard
                        nodesCard
                        sessionsCard
                    }
                    .padding(16)
                }
                .refreshable { await model.loadDashboard() }
            }
            .safeAreaInset(edge: .top) {
                SheetHeader(title: L("控制台"), onDone: { dismiss() })
            }
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.loadDashboard() }
            .confirmationDialog("撤銷這台裝置？", isPresented: Binding(
                get: { deviceToRemove != nil },
                set: { if !$0 { deviceToRemove = nil } }
            ), titleVisibility: .visible) {
                Button("撤銷（需重新配對）", role: .destructive) {
                    if let d = deviceToRemove { model.remove(d) }
                    deviceToRemove = nil
                }
                Button("取消", role: .cancel) { deviceToRemove = nil }
            } message: {
                Text(deviceToRemove.map { "\($0.name) \($0.ip)" } ?? "")
            }
        }
    }

    // MARK: - 連線

    private var connectionCard: some View {
        card("連線") {
            row("Gateway", model.gatewayURL?.host ?? "—")
            row("版本", model.gatewayVersion.isEmpty ? "—" : model.gatewayVersion)
            row("延遲", model.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
            row("狀態", model.isDemo ? "Demo" : (model.isConnected ? "已連線" : "未連線"))
            if let err = model.dashboardError {
                Text(err).font(Theme.ui(11)).foregroundStyle(Theme.warn)
            }
            if let err = model.actionError {
                Text(err).font(Theme.ui(11)).foregroundStyle(Theme.warn)
            }
        }
    }

    private var usageCard: some View {
        card("用量") {
            row("會話數", "\(model.sessions.count)")
            row("總 tokens", formatTokens(model.totalTokens))
            if let top = model.sessions.max(by: { $0.totalTokens < $1.totalTokens }), top.totalTokens > 0 {
                row("最重會話", "\(top.title) · \(formatTokens(top.totalTokens))")
            }
        }
    }

    // MARK: - 模型

    private var modelCard: some View {
        card("本會話模型") {
            HStack {
                Text(model.currentSession?.title ?? "—")
                    .font(Theme.ui(12)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Menu {
                    if model.availableModels.isEmpty {
                        Text(L("沒有可用模型"))
                    } else {
                        ForEach(model.availableModels, id: \.self) { m in
                            Button(m) { model.setModel(m) }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(currentModelLabel)
                            .font(Theme.ui(12, .semibold))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.panel2)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private var currentModelLabel: String {
        if let m = model.currentSession?.model, !m.isEmpty { return m }
        return "切換"
    }

    // MARK: - 待核准

    private var approvalsCard: some View {
        card("待核准 (\(model.pendingApprovals.count))") {
            if model.pendingApprovals.isEmpty {
                Text(L("沒有待核准的請求")).font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.pendingApprovals) { a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.deviceName).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink)
                        Text((a.platform + " " + a.ip).trimmingCharacters(in: .whitespaces))
                            .font(Theme.ui(10)).foregroundStyle(Theme.muted)
                        HStack(spacing: 8) {
                            Button(L("批准")) { model.approve(a) }
                                .font(Theme.ui(12, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                            Button(L("拒絕")) { model.reject(a) }
                                .font(Theme.ui(12, .semibold))
                                .foregroundStyle(Theme.warn)
                                .padding(.horizontal, 14).padding(.vertical, 6)
                                .background(Theme.panel2)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 已配對裝置

    private var devicesCard: some View {
        card("已配對裝置 (\(model.pairedDevices.count))") {
            if model.pairedDevices.isEmpty {
                Text(L("沒有已配對裝置")).font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.pairedDevices) { d in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(d.roles + (d.ip.isEmpty ? "" : " · " + d.ip))
                                .font(Theme.ui(10)).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        Button(L("撤銷")) { deviceToRemove = d }
                            .font(Theme.ui(11, .bold))
                            .foregroundStyle(Theme.warn)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.panel2)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - 任務

    private var cronCard: some View {
        card("自動化任務 (\(model.cronJobs.count))") {
            if model.cronJobs.isEmpty {
                Text(model.dashboardLoading ? "載入中…" : "沒有任務")
                    .font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.cronJobs.prefix(10)) { job in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(job.enabled ? Color.green.opacity(0.85) : Theme.muted.opacity(0.5))
                                .frame(width: 8, height: 8)
                            Text(job.name)
                                .font(Theme.ui(13, .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { job.enabled },
                                set: { _ in model.toggleJob(job) }
                            ))
                            .labelsHidden()
                            .scaleEffect(0.8)
                            Button(L("執行")) { model.runJob(job) }
                                .font(Theme.ui(11, .bold))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Theme.panel2)
                                .clipShape(Capsule())
                        }
                        HStack(spacing: 6) {
                            Text(job.scheduleText + (job.nextRunAt.map { " · 下次 " + shortTime($0) } ?? ""))
                                .font(Theme.ui(10)).foregroundStyle(Theme.muted).lineLimit(1)
                            if let st = job.lastStatus, st != "ok" {
                                Text(st).font(Theme.ui(10, .bold)).foregroundStyle(Theme.warn)
                            }
                        }
                        .padding(.leading, 16)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MM/dd HH:mm"; return f.string(from: d)
    }

    // MARK: - 節點

    private var nodesCard: some View {
        card("節點 (\(model.nodes.count))") {
            if model.nodes.isEmpty {
                Text(model.dashboardLoading ? "載入中…" : "沒有已配對節點")
                    .font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.nodes.prefix(8)) { n in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(n.online ? Color.green.opacity(0.85) : Theme.muted.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text(n.name).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                        Spacer()
                        Text(n.platform).font(Theme.ui(10)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    // MARK: - 會話

    private var sessionsCard: some View {
        card("最近會話") {
            if model.sessions.isEmpty {
                Text(L("沒有會話")).font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.sessions.prefix(6)) { s in
                    Button {
                        model.select(s); dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.title).font(Theme.ui(13, .semibold))
                                    .foregroundStyle(Theme.ink).lineLimit(1)
                                Text(s.id).font(Theme.ui(9))
                                    .foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(formatTokens(s.totalTokens))
                                .font(Theme.ui(10)).foregroundStyle(Theme.muted)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - helpers

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.ui(12, .bold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 8) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.panel)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.ui(12)).foregroundStyle(Theme.muted)
            Spacer()
            Text(v).font(Theme.ui(13, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
