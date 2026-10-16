//
//  MainView.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：MainActivity.java
//  线路列表 + 权限自检 + 各种测试入口。
//

import SwiftUI
import CoreLocation

struct MainView: View {

    @EnvironmentObject var state: AppState
    @EnvironmentObject var alarm: AlarmEngine
    @EnvironmentObject var monitor: MonitorEngine

    @State private var editingRoute: Route?
    @State private var showingNewRoute = false
    @State private var showingLog = false
    @State private var checkingUpdate = false
    @State private var updateText = ""
    @State private var activeAlert: ActiveAlert?

    private enum ActiveAlert: Identifiable {
        case update(String)
        case delete(Route)

        var id: String {
            switch self {
            case .update(let text): return "update-\(text)"
            case .delete(let route): return "delete-\(route.id)"
            }
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    setupSection
                    routesSection
                    actionsSection
                    tipsSection
                }
                .padding(16)
            }
            .navigationBarTitle("到站提醒", displayMode: .inline)
            .navigationBarItems(trailing: Button(action: { showingNewRoute = true }) {
                Image(systemName: "plus")
            })
            .onAppear { state.refresh() }
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingNewRoute) {
            RouteEditView(routeId: nil)
                .environmentObject(state)
        }
        .sheet(item: $editingRoute) { route in
            RouteEditView(routeId: route.id)
                .environmentObject(state)
        }
        .sheet(isPresented: $showingLog) {
            TrackLogView()
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .update(let text):
                return Alert(title: Text("检查更新"), message: Text(text),
                             dismissButton: .default(Text("好")))
            case .delete(let route):
                return Alert(title: Text("删除线路"),
                             message: Text("确定删除「\(route.name)」吗？"),
                             primaryButton: .destructive(Text("删除")) { state.delete(route) },
                             secondaryButton: .cancel(Text("取消")))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = state.toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.78))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .fullScreenCover(item: Binding(get: { alarm.current }, set: { _ in })) { route in
            AlarmView(route: route)
                .environmentObject(alarm)
        }
    }

    // MARK: - 顶部说明

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("一次设置，每天按你的大致到站时间自动盯着：进入提醒站附近立刻响铃 + 震动 + 循环语音播报。")
                .font(.subheadline)
            Text("iOS 后台限制说明：系统不允许「到点自动开 GPS」，改成常驻「地理围栏 + 显著位置变化」——几乎不耗电，跨基站或进入提醒站附近时系统会唤醒本 App，再升级为精确定位做判定。")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 权限自检

    private var setupSection: some View {
        let pending = state.pendingChecks()
        return VStack(alignment: .leading, spacing: 8) {
            Text(pending.isEmpty ? "设置" : "设置（还有 \(pending.count) 项需要处理）")
                .font(.headline)

            if pending.isEmpty {
                Text("✅ 权限与系统设置已就绪，无需额外操作")
                    .font(.subheadline)
                    .foregroundColor(.green)
            } else {
                ForEach(pending) { item in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("⚠️ \(item.title)").font(.subheadline)
                            Text("　　\(item.impact)").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer(minLength: 8)
                        Button(item.actionTitle) { item.action() }
                            .font(.caption)
                            .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(8)
                }
            }

            Text(state.checkSummary)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text("提示：iOS 上必须选「始终允许」定位，并且打开「设置 → 隐私 → 定位服务」。系统还会在长时间不用后询问是否继续允许后台定位，请选「始终允许」。")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - 线路列表

    private var routesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("我的线路").font(.headline)

            if state.routes.isEmpty {
                Text("还没有线路。点右上角 ＋ 添加你的通勤线路。")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                ForEach(state.routes) { route in
                    routeCard(route)
                }
            }
        }
    }

    private func routeCard(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(route.name)　→　\(route.hasLocation ? route.stationName : "（未设置提醒站位置）")")
                .font(.headline)

            Text("播报：\(route.announce)")
                .font(.caption)
            Text("到站时间 \(route.effectiveTimeText)　监控窗口 \(route.windowText)　\(route.daysText)")
                .font(.caption)
            Text("提醒半径 \(route.radiusMeters) 米"
                + (route.arrivalHistory.isEmpty ? "" : "　已学习 \(route.arrivalHistory.count) 次"))
                .font(.caption)
            Text("下次自动开启：\(WindowScheduler.describeNext(route))")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Toggle("启用", isOn: Binding(
                    get: { route.enabled },
                    set: { state.setEnabled(route, $0) }))
                    .labelsHidden()
                Text("启用").font(.caption)
                Spacer()
                Button("编辑") { editingRoute = route }
                    .font(.caption)
                    .buttonStyle(.bordered)
                Button("删除") { activeAlert = .delete(route) }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - 操作按钮

    private var actionsSection: some View {
        VStack(spacing: 8) {
            Button {
                var r = Route()
                r.destName = "测试站"
                alarm.start(route: r)
                state.showToast("测试中：点通知里的「我已下车」可停止")
            } label: {
                Label("立即测试提醒（试听铃声 / 震动 / 语音）", systemImage: "bell.badge")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                startTestMonitor()
            } label: {
                Label("立即开始监控（测试用，30 分钟）", systemImage: "location")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                showingLog = true
            } label: {
                Label("查看监控日志（排查「为什么不响」）", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                checkUpdate()
            } label: {
                Label(checkingUpdate
                        ? "正在检查更新…"
                        : "检查更新（当前 v\(AppInfo.versionName)）",
                      systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(checkingUpdate)

            if monitor.running {
                Button(role: .destructive) {
                    monitor.stopMonitoring(reason: "用户手动停止")
                } label: {
                    Label("停止当前监控", systemImage: "stop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if monitor.running {
                Text(monitor.statusLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - 使用说明

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("使用步骤")
                .font(.headline)
            Text("""
            1）点右上角 ＋ 新建线路（第 1 条默认叫「上班」，第 2 条默认叫「下班」）。
            2）填提醒站名称，并用「当前位置 / 地图选点 / 按名称查」三种方式之一确定车站位置。
            3）填每天大致几点到站，例如 08:50，选好监控日期（工作日 / 每天 / 周末 / 自定义）。
            4）连续几次到站后，App 会自动学习你的实际到站时间并微调监控窗口。
            5）到站后点「我已下车」停止；也可以点「再过 2 分钟提醒我」。

            省电说明：平时不会开 GPS，只保留系统的「地理围栏 + 显著位置变化」，几乎不额外耗电。
            """)
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }

    // MARK: - 行为

    private func startTestMonitor() {
        let usable = state.routes.filter { $0.enabled && $0.hasLocation }
        guard !usable.isEmpty else {
            state.showToast("请先新建线路并设置提醒站位置")
            return
        }
        TrackLog.log("测试", "用户手动开启测试监控")
        monitor.startTestMonitor(minutes: 30)
        state.showToast("已开始监控 30 分钟（时间窗外的线路也会被监控）")
    }

    private func checkUpdate() {
        checkingUpdate = true
        UpdateChecker.fetch { info in
            checkingUpdate = false
            updateText = UpdateChecker.manualResultText(info)
            activeAlert = .update(updateText)
        }
    }
}