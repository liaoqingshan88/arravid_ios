//
//  RouteEditView.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：RouteEditActivity.java
//  线路配置表单（含一键记录终点站坐标 / 地图选点 / 按名称查）。
//

import SwiftUI
import CoreLocation

struct RouteEditView: View {

    /// nil 表示新建
    let routeId: Int64?

    @EnvironmentObject var state: AppState
    @Environment(\.presentationMode) private var presentationMode

    @State private var draft = Route()
    @State private var isNew = true

    @State private var hasLoc = false
    @State private var lat = 0.0
    @State private var lng = 0.0

    @State private var locating = false
    @State private var showingMap = false
    @State private var showingSearch = false
    @State private var searchKeyword = ""
    @State private var searchResults: [StationSearch.Item] = []
    @State private var searchError: String?
    @State private var searching = false

    @State private var activeAlert: EditAlert?

    private enum EditAlert: Identifiable {
        case message(String)
        case confirmDelete

        var id: String {
            switch self {
            case .message(let m): return "msg-\(m)"
            case .confirmDelete: return "confirm-delete"
            }
        }
    }

    @State private var autoAnnounce = ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("基本信息")) {
                    HStack {
                        Text("线路名称")
                        Spacer()
                        TextField("例如：上班", text: $draft.name)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("提醒站名称")
                        Spacer()
                        TextField("到站提醒的车站", text: $draft.destName)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: draft.destName) { _ in syncAnnounce() }
                    }
                }

                Section(header: Text("提醒站位置（三种方式任选一种）")) {
                    Button {
                        useCurrentLocation()
                    } label: {
                        Label(locating ? "正在获取当前位置…（10~30 秒）" : "① 用当前位置设为提醒站",
                              systemImage: "location.fill")
                    }
                    .disabled(locating)

                    Button {
                        showingMap = true
                    } label: {
                        Label("② 地图选点", systemImage: "map")
                    }

                    Button {
                        searchKeyword = draft.destName
                        showingSearch = true
                    } label: {
                        Label(MapConfig.isSearchAvailable ? "③ 按名称查车站" : "③ 按名称查车站（未启用）",
                              systemImage: "magnifyingglass")
                    }
                    .disabled(!MapConfig.isSearchAvailable)

                    Text(locationText)
                        .font(.caption)
                        .foregroundColor(hasLoc ? .secondary : .orange)
                }

                Section(header: Text("时间与范围")) {
                    HStack {
                        Text("每天大致几点到站")
                        Spacer()
                        TextField("08:30", text: $draft.arriveTime)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numbersAndPunctuation)
                            .frame(width: 90)
                    }
                    HStack {
                        Text("到站前多少分钟开始监控")
                        Spacer()
                        TextField("10", value: $draft.leadMinutes, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 70)
                    }
                    HStack {
                        Text("提醒半径（米）")
                        Spacer()
                        TextField("800", value: $draft.radiusMeters, formatter: NumberFormatter())
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                            .frame(width: 80)
                    }
                    Text("窗口：\(draft.windowText)（到站后固定再监控 \(draft.tailMinutes) 分钟）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section(header: Text("监控日期")) {
                    HStack(spacing: 8) {
                        presetButton("工作日", Route.maskWorkday)
                        presetButton("每天", Route.maskEveryday)
                        presetButton("周末", Route.maskWeekend)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            dayToggle(i)
                        }
                    }
                }

                Section(header: Text("播报与学习")) {
                    Text("到站循环播报文字（留空自动用「站名 到了，请下车」）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField(autoAnnounce, text: $draft.announceText)

                    Text("语音播报为强制开启：进入提醒范围后会循环播报，直到你点「我已下车」。")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Toggle("自动学习实际到站时间并微调监控窗口", isOn: $draft.autoLearn)

                    Text(learnText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text("保存").bold().frame(maxWidth: .infinity)
                    }
                    if !isNew {
                        Button(role: .destructive) {
                            activeAlert = .confirmDelete
                        } label: {
                            Text("删除线路").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationBarTitle(isNew ? "新建线路" : "编辑线路", displayMode: .inline)
            .navigationBarItems(leading: Button("取消") { presentationMode.wrappedValue.dismiss() })
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showingMap) {
            MapPickerView(initialLat: hasLoc ? lat : 0, initialLng: hasLoc ? lng : 0) { coord in
                setStation(coord.latitude, coord.longitude, "已采用地图选点位置")
            }
        }
        .sheet(isPresented: $showingSearch) {
            searchSheet
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .message(let m):
                return Alert(title: Text("提示"), message: Text(m), dismissButton: .default(Text("好")))
            case .confirmDelete:
                return Alert(title: Text("删除线路"),
                             message: Text("确定删除这条线路吗？"),
                             primaryButton: .destructive(Text("删除")) {
                                 RouteStore.shared.delete(draft.id)
                                 MonitorEngine.shared.refreshRegions()
                                 state.reloadAndRearm()
                                 presentationMode.wrappedValue.dismiss()
                             },
                             secondaryButton: .cancel(Text("取消")))
            }
        }
        .onAppear(perform: load)
    }

    // MARK: - 子视图

    private func presetButton(_ title: String, _ mask: Int) -> some View {
        Button(title) {
            draft.daysMask = mask
        }
        .font(.caption)
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }

    private func dayToggle(_ index: Int) -> some View {
        let on = (draft.daysMask & (1 << index)) != 0
        return Button {
            if on {
                draft.daysMask &= ~(1 << index)
            } else {
                draft.daysMask |= (1 << index)
            }
        } label: {
            Text(Route.dayNames[index])
                .font(.caption)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(on ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                .foregroundColor(on ? .white : .primary)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private var searchSheet: some View {
        NavigationView {
            VStack(spacing: 0) {
                HStack {
                    TextField("例如：深圳北站 / 会展中心地铁站", text: $searchKeyword)
                        .textFieldStyle(.roundedBorder)
                    Button("查找") { doSearch() }
                        .buttonStyle(.borderedProminent)
                        .disabled(searching)
                }
                .padding()

                if searching {
                    ProgressView("正在查找…").padding()
                }
                if let err = searchError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding()
                }

                List(searchResults) { item in
                    Button {
                        setStation(item.lat, item.lng, "已填入「\(item.name)」坐标")
                        if draft.destName.trimmingCharacters(in: .whitespaces).isEmpty {
                            draft.destName = item.name
                        }
                        showingSearch = false
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.subheadline)
                            Text(item.address).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationBarTitle("按名称查找车站", displayMode: .inline)
            .navigationBarItems(leading: Button("关闭") { showingSearch = false })
            .onAppear { doSearch() }
        }
        .navigationViewStyle(.stack)
    }

    // MARK: - 文案

    private var locationText: String {
        if hasLoc {
            return String(format: "提醒站坐标（GPS）：%.6f, %.6f", lat, lng)
        }
        return "提醒站坐标：未设置 —— 请用上面三种方式之一确定车站位置"
    }

    private var learnText: String {
        let h = draft.arrivalHistory
        if h.isEmpty {
            return "学习记录：暂无（每次成功提醒会自动记录实际到站时间）"
        }
        let times = h.map { Route.minsToText($0) }.joined(separator: " / ")
        return "学习记录：\(h.count) 次，实际到站 \(times)；当前采用 \(draft.effectiveTimeText)"
    }

    // MARK: - 加载 / 保存

    private func load() {
        if let id = routeId, let existing = RouteStore.shared.find(id) {
            draft = existing
            isNew = false
        } else {
            draft = Route()
            draft.name = defaultNameForNew()
            isNew = true
        }
        hasLoc = draft.hasLocation
        lat = draft.lat
        lng = draft.lng
        syncAnnounce(force: true)
    }

    private func defaultNameForNew() -> String {
        let n = RouteStore.shared.count
        if n == 0 { return "上班" }
        if n == 1 { return "下班" }
        return "线路\(n + 1)"
    }

    /// 播报文字跟随站名：用户没手动改过就自动更新
    private func syncAnnounce(force: Bool = false) {
        let auto = Route.defaultAnnounce(draft.destName)
        defer {
            autoAnnounce = auto
            previousDestName = draft.destName
        }
        if force { return }
        let cur = draft.announceText.trimmingCharacters(in: .whitespaces)
        let previousAuto = Route.defaultAnnounce(previousDestName)
        // 从没填过，或者填的就是上一个站名的自动文案 → 跟着站名更新
        if cur.isEmpty || cur == previousAuto {
            draft.announceText = auto
        }
    }

    @State private var previousDestName = ""

    private func setStation(_ newLat: Double, _ newLng: Double, _ info: String?) {
        lat = newLat
        lng = newLng
        hasLoc = true
        if let info = info { state.showToast(info) }
    }

    private func useCurrentLocation() {
        locating = true
        LocationOnce.requestOnce { location in
            locating = false
            guard let loc = location else {
                state.showToast("定位失败：检查定位权限和系统定位开关后重试")
                return
            }
            let acc = loc.horizontalAccuracy
            var msg = "已用当前位置作为提醒站"
            if acc > 0 {
                msg += "　精度 ±\(Int(acc.rounded())) 米"
                if acc > 200 {
                    msg = "已记录，但定位精度只有 ±\(Int(acc.rounded())) 米，站点坐标可能偏 —— 建议改用「地图选点」或「按名称查」更准"
                }
            }
            setStation(loc.coordinate.latitude, loc.coordinate.longitude, msg)
        }
    }

    private func doSearch() {
        searching = true
        searchError = nil
        StationSearch.search(keyword: searchKeyword) { items, error in
            searching = false
            searchResults = items ?? []
            searchError = error ?? (items?.isEmpty == false ? nil : "没有找到结果")
        }
    }

    private static func parseInt(_ s: String, _ def: Int) -> Int {
        guard let v = Int(s.trimmingCharacters(in: .whitespaces)), v > 0 else { return def }
        return v
    }

    private static func normalizeTime(_ s: String) -> String {
        let cleaned = s.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "：", with: ":")
        let parts = cleaned.split(separator: ":")
        guard let h = Int(parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "") else {
            return "08:30"
        }
        var hour = h
        var minute = 0
        if parts.count > 1 { minute = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if hour < 0 || hour > 23 { hour = 8 }
        if minute < 0 || minute > 59 { minute = 0 }
        return "\(Route.two(hour)):\(Route.two(minute))"
    }

    private func save() {
        let dest = draft.destName.trimmingCharacters(in: .whitespaces)
        guard !dest.isEmpty else {
            activeAlert = .message("请填写提醒站名称")
            return
        }
        guard hasLoc else {
            activeAlert = .message("请先用「当前位置 / 地图选点 / 按名称查」确定车站位置")
            return
        }
        guard draft.daysMask != 0 else {
            activeAlert = .message("请至少选择一个日期")
            return
        }
        guard draft.radiusMeters > 0, draft.leadMinutes > 0 else {
            activeAlert = .message("监控提前量与提醒半径必须是大于 0 的整数")
            return
        }

        let nm = draft.name.trimmingCharacters(in: .whitespaces)
        draft.name = nm.isEmpty ? dest : nm
        draft.destName = dest
        draft.lat = lat
        draft.lng = lng
        draft.hasLocation = true
        draft.arriveTime = RouteEditView.normalizeTime(draft.arriveTime)
        draft.leadMinutes = RouteEditView.parseInt(String(draft.leadMinutes), 10)
        draft.radiusMeters = RouteEditView.parseInt(String(draft.radiusMeters), 800)

        let ann = draft.announceText.trimmingCharacters(in: .whitespaces)
        draft.announceText = (ann == Route.defaultAnnounce(dest)) ? "" : ann

        RouteStore.shared.upsert(draft)
        MonitorEngine.shared.refreshRegions()
        state.reloadAndRearm()

        let msg = WindowScheduler.isNowInWindow(draft)
            ? "已保存，并已立即开始监控（你现在就在监控窗口 \(draft.windowText) 内）"
            : "已保存：\(draft.daysText) \(draft.windowText) 自动开始监控"
        state.showToast(msg, seconds: 3)

        if WindowScheduler.isNowInWindow(draft) {
            MonitorEngine.shared.startMonitoring(routeId: draft.id, forceMinutes: 0, source: "app")
        }
        presentationMode.wrappedValue.dismiss()
    }
}