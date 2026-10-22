import SwiftUI

/// 原生儀表板(不跳去 OpenClaw 網頁):連線狀態、用量、自動化任務、節點、會話
struct DashboardView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background
                ScrollView {
                    VStack(spacing: 14) {
                        connectionCard
                        usageCard
                        cronCard
                        nodesCard
                        sessionsCard
                    }
                    .padding(16)
                }
                .refreshable { await model.loadDashboard() }
            }
            .navigationTitle("控制台")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("完成") { dismiss() } }
            }
            .task { await model.loadDashboard() }
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
        }
    }

    // MARK: - 用量

    private var usageCard: some View {
        card("用量") {
            row("會話數", "\(model.sessions.count)")
            row("總 tokens", formatTokens(model.totalTokens))
            if let top = model.sessions.max(by: { $0.totalTokens < $1.totalTokens }), top.totalTokens > 0 {
                row("最重會話", "\(top.title) · \(formatTokens(top.totalTokens))")
            }
        }
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.2fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: - 自動化

    private var cronCard: some View {
        card("自動化任務 (\(model.cronJobs.count))") {
            if model.cronJobs.isEmpty {
                Text(model.dashboardLoading ? "載入中…" : "沒有任務")
                    .font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.cronJobs.prefix(8)) { job in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(job.enabled ? Color.green.opacity(0.85) : Theme.muted.opacity(0.5))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.name)
                                .font(Theme.ui(13, .semibold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Text(job.scheduleText + (job.nextRunAt.map { " · 下次 " + shortTime($0) } ?? ""))
                                .font(Theme.ui(10))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("執行") { model.runJob(job) }
                            .font(Theme.ui(11, .bold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Theme.panel2)
                            .clipShape(Capsule())
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func shortTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f.string(from: d)
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
                Text("沒有會話").font(Theme.ui(12)).foregroundStyle(Theme.muted)
            } else {
                ForEach(model.sessions.prefix(6)) { s in
                    Button {
                        model.select(s)
                        dismiss()
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
}
