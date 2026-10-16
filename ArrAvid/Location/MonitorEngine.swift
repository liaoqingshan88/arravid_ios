//
//  MonitorEngine.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：MonitorService.java + Scheduler(部分)。
//
//  ── iOS 上「到点自动开 GPS」不可能实现，所以这里换了一套等价方案 ─────────────
//  Android：AlarmManager 在窗口开始时精确唤醒 → 起前台服务 → 连续 GPS → 到站判定。
//  iOS：没有精确闹钟，也不允许后台定时启动。改为
//     ① 常驻「地理围栏监控 + 显著位置变化」（系统级、几乎不耗电，跨基站/进出围栏时唤醒 App）；
//     ② 一旦发现「进入监控窗口内」或「进入提醒站围栏」或「用户手动测试」→ 升级为连续 GPS；
//     ③ 连续 GPS 期间，判定逻辑、接近判断、兜底延长、学习记录与 Android 版逐条对齐。
//  这样既保留了「其余时间不取 GPS」的省电目标，又拿到了 iOS 允许的最强后台能力。
//

import Foundation
import CoreLocation
import UserNotifications
import UIKit

final class MonitorEngine: NSObject, ObservableObject, CLLocationManagerDelegate {

    static let shared = MonitorEngine()

    // 与 Android 版一致的常量
    private let tickInterval: TimeInterval = 30
    private let extendInterval: TimeInterval = 15 * 60
    private let maxExtensions = 3
    /// 窗口结束后最多再跑这么久就强制停止（兜底：避免整小时耗电）
    private let maxOverrun: TimeInterval = 45 * 60
    /// 判定"在车上"的速度阈值（米/秒），约 10.8 km/h
    private let movingSpeed: Double = 3.0
    /// 定位精度超过这个值就不做判定（避免飘点误触发）
    private let maxAccuracy: Double = 300
    /// 距离样本保留个数（用于判断是否在接近）
    private let historyLength = 4
    /// 进入围栏后多久还没拿到可用定位就直接响（宁可早响，不可漏站）
    private let regionEntryGrace: TimeInterval = 45

    // MARK: - 对外状态（供 SwiftUI 观察）

    @Published private(set) var running = false
    @Published private(set) var testMode = false
    @Published private(set) var statusLine = "未监控"
    @Published private(set) var fixCount = 0
    @Published private(set) var armed = false

    // MARK: - 内部状态

    private let manager = CLLocationManager()
    private var active: [Route] = []
    private var alerted = Set<Int64>()
    private var lastDistance: [Int64: Double] = [:]
    private var distHist: [Int64: [Double]] = [:]
    private var lastSpeed: [Int64: Double] = [:]
    private var lastFixTime: [Int64: Date] = [:]
    private var minDist: [Int64: Double] = [:]

    private var stopAt: Date?
    private var lastFixAt: Date?
    private var extensions = 0
    private var consecutive = 0
    private var ticker: Timer?
    private var regionEnteredAt: [String: Date] = [:]
    private var configured = false

    /// 与 Android 版 MonitorService.RUNNING 等价：避免「打开 App 重排」把正在跑的监控重启
    var isRunning: Bool { running }

    private override init() {
        super.init()
    }

    // MARK: - 配置 / 权限

    func configure() {
        guard !configured else { return }
        configured = true
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .automotiveNavigation
        manager.pausesLocationUpdatesAutomatically = false
        // 允许后台定位（Info.plist 里必须声明 UIBackgroundModes: location，否则会崩）
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    var hasAlwaysAuthorization: Bool {
        manager.authorizationStatus == .authorizedAlways
    }

    var hasAnyAuthorization: Bool {
        manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse
    }

    /// 是否拿到了「精确位置」（iOS 14+ 用户可以只给大致位置）
    var preciseAccuracy: Bool {
        manager.accuracyAuthorization == .fullAccuracy
    }

    /// 当前已注册的提醒站围栏数量
    var monitoredRegionCount: Int {
        manager.monitoredRegions.count
    }

    var locationServicesEnabled: Bool {
        CLLocationManager.locationServicesEnabled()
    }

    func requestWhenInUse() {
        configure()
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestAlways() {
        configure()
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            manager.requestAlwaysAuthorization()
        default:
            break
        }
    }

    // MARK: - 常驻后台监控（围栏 + 显著位置变化）

    /// 每次 App 启动、线路变化后调用：注册围栏 + 打开低成本的后台唤醒源。
    func armBackgroundWatch() {
        configure()
        guard hasAnyAuthorization else { return }

        refreshRegions()

        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
            armed = true
        }
        // 部分地区/关闭系统定位服务时会失败，忽略即可
        TrackLog.log("待命", "后台唤醒已就绪：地理围栏 \(manager.monitoredRegions.count) 个 + 显著位置变化")
    }

    /// 按当前线路重排围栏
    func refreshRegions() {
        guard hasAnyAuthorization else { return }
        let existing = manager.monitoredRegions
        for region in existing {
            manager.stopMonitoring(for: region)
        }
        for r in RouteStore.shared.load() where r.enabled && r.hasLocation {
            registerRegion(for: r)
        }
    }

    private func registerRegion(for r: Route) {
        let radius = min(max(Double(r.radiusMeters), 100), 3000)
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: r.lat, longitude: r.lng),
            radius: radius,
            identifier: "arravid.route.\(r.id)")
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
    }

    // MARK: - 监控生命周期

    /// 手动开启一次监控（不等时间窗），用于实测
    func startTestMonitor(minutes: Int = 30) {
        startMonitoring(routeId: nil, forceMinutes: minutes, source: "test")
    }

    /// 开始连续 GPS 监控
    /// - Parameters:
    ///   - routeId: 指定线路（来源为围栏/显著位置变化时）；nil 表示按窗口自动挑选
    ///   - forceMinutes: > 0 表示测试模式（所有可用线路都监控这么久）
    func startMonitoring(routeId: Int64?, forceMinutes: Int = 0, source: String) {
        configure()
        guard hasAnyAuthorization else {
            TrackLog.log("错误", "没有定位权限，无法监控")
            statusLine = "缺少定位权限"
            return
        }

        let now = Date()
        let routes = RouteStore.shared.load()
        testMode = forceMinutes > 0

        active.removeAll()
        alerted.removeAll()
        lastDistance.removeAll()
        distHist.removeAll()
        lastSpeed.removeAll()
        lastFixTime.removeAll()
        minDist.removeAll()
        extensions = 0
        fixCount = 0
        consecutive = 0
        regionEnteredAt.removeAll()

        if testMode {
            active = routes.filter { $0.enabled && $0.hasLocation }
            stopAt = now.addingTimeInterval(TimeInterval(forceMinutes) * 60)
            TrackLog.log("测试", "手动开启监控 \(forceMinutes) 分钟，线路 \(active.count) 条")
        } else {
            for r in routes {
                guard r.enabled && r.hasLocation else { continue }
                if WindowScheduler.inWindow(r, date: now) {
                    active.append(r)
                } else if let id = routeId, r.id == id,
                          let end = WindowScheduler.windowEndToday(r, now: now),
                          now.timeIntervalSince(end) < 10 * 60 {
                    active.append(r)
                }
            }

            if active.isEmpty {
                var lateNote = ""
                if let id = routeId, let er = routes.first(where: { $0.id == id }),
                   let end = WindowScheduler.windowEndToday(er, now: now) {
                    let overMin = Int(((now.timeIntervalSince(end)) / 60).rounded())
                    if overMin > 0 {
                        lateNote = "；触发来晚了，\(er.stationName) 窗口 \(er.windowText) 已过 \(overMin) 分钟"
                    }
                }
                TrackLog.log("跳过", "没有线路处于监控窗口内，不启动定位\(lateNote)")
                Diag.event("alarm_late", "触发时已不在监控窗口内，未启动监控（线路 id=\(routeId.map(String.init) ?? "nil")，来源=\(source)）\(lateNote)")
                statusLine = "不在监控窗口内"
                return
            }

            var latest = Date.distantPast
            for r in active {
                if let end = WindowScheduler.windowEndToday(r, now: now), end > latest { latest = end }
            }
            stopAt = latest == Date.distantPast ? nil : latest
            let summary = active.map { "\($0.stationName) \($0.windowText) 半径\($0.radiusMeters)m" }
                .joined(separator: "；")
            TrackLog.log("开始", "监控 \(active.count) 条线路 → \(summary)")
        }

        guard !active.isEmpty else {
            statusLine = "无可用线路"
            return
        }

        // 精确位置权限检查（iOS 14+）
        if manager.accuracyAuthorization == .reducedAccuracy {
            TrackLog.log("权限", "只授予了【大致位置】—— 定位精度可能差到数公里，会漏提醒！请在系统设置里改为精确位置")
        } else {
            TrackLog.log("权限", "已授予【精确位置】")
        }

        // 闹钟/唤醒迟到 → 把窗口结束同步顺延，保住覆盖时长（最多 15 分钟）
        if !testMode, let end = stopAt {
            let earliest = active.compactMap { WindowScheduler.windowStartToday($0, now: now) }.min() ?? now
            let lateMin = max(0, Int((now.timeIntervalSince(earliest) / 60).rounded()))
            if lateMin > 1 {
                let add = TimeInterval(min(lateMin, 15) * 60)
                stopAt = end.addingTimeInterval(add)
                TrackLog.log("启动", "唤醒迟到 \(lateMin) 分钟，窗口结束顺延 \(Int(add / 60)) 分钟")
            }
        }

        TrackLog.log("启动", "启动方式=\(source)，线路 \(active.count) 条")
        Diag.event("monitor_start", "启动方式=\(source)；"
            + active.map { "\($0.stationName) \($0.windowText) 半径\($0.radiusMeters)m" }.joined(separator: "；"))

        beginLocationUpdates()
        running = true
        updateStatusLine()
        startTicker()
    }

    /// 结束监控
    func stopMonitoring(reason: String) {
        ticker?.invalidate()
        ticker = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = true   // 保持后台能力，回到"待命"状态
        running = false
        testMode = false
        alertNotificationRemove()
        let n = fixCount
        let a = alerted.count
        TrackLog.log("结束", "\(reason)（窗口 \(stopAt.map { MonitorEngine.hhmm($0) } ?? "-")，定位 \(n) 次，实际提醒 \(a) 条线路；最近距离 \(minDistText())）")
        Diag.event("monitor_end", "\(reason)，窗口 \(stopAt.map { MonitorEngine.hhmm($0) } ?? "-")，定位 \(n) 次，实际提醒 \(a) 条线路；最近距离 \(minDistText())")
        active.removeAll()
        stopAt = nil
        statusLine = "未监控"
    }

    private func beginLocationUpdates() {
        // GPS 优先（间隔更短），并用显著位置变化作为兜底唤醒源
        manager.startUpdatingLocation()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
    }

    private func startTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard let end = stopAt else { return }
        let now = Date()

        // 兜底：窗口结束后很久仍未结束 → 强制停止
        if now.timeIntervalSince(end) > maxOverrun {
            TrackLog.log("结束", "超过窗口结束 \(Int(maxOverrun / 60)) 分钟仍未结束，强制停止")
            stopMonitoring(reason: "超时强制停止")
            return
        }

        if now > end && !AlarmEngine.shared.active {
            if extensions < maxExtensions && shouldExtend(now: now) {
                extensions += 1
                stopAt = now.addingTimeInterval(extendInterval)
                TrackLog.log("延长", "窗口到点但仍在移动且在接近，延长 \(Int(extendInterval / 60)) 分钟（第 \(extensions) 次）")
                updateStatusLine(prefix: "已延长监控至 \(MonitorEngine.hhmm(stopAt!))")
                return
            }
            stopMonitoring(reason: "正常结束")
        }
    }

    /// 窗口到点还该不该继续盯着
    private func shouldExtend(now: Date) -> Bool {
        guard let lastFix = lastFixAt, now.timeIntervalSince(lastFix) < 3 * 60 else { return false }
        for r in active where !alerted.contains(r.id) {
            guard let sp = lastSpeed[r.id], sp >= movingSpeed else { continue }
            guard let h = distHist[r.id], h.count >= 2 else { continue }
            if h[h.count - 1] < h[h.count - 2] { return true }
        }
        return false
    }

    // MARK: - 定位回调

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // 连续 GPS 时可能有多个点，逐个处理
        for loc in locations {
            LocationOnce.remember(loc)
            guard running, !active.isEmpty else { continue }
            evaluate(loc)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        TrackLog.log("定位", "定位失败：\(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        TrackLog.log("权限", "定位授权状态变更：\(MonitorEngine.describe(manager.authorizationStatus))，精度=\(manager.accuracyAuthorization == .fullAccuracy ? "精确" : "大致")")
        if hasAnyAuthorization {
            armBackgroundWatch()
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        handleRegion(region, entered: true)
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        handleRegion(region, entered: false)
    }

    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside {
            handleRegion(region, entered: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        TrackLog.log("围栏", "围栏注册失败 \(region?.identifier ?? "-")：\(error.localizedDescription)")
    }

    // MARK: - 到站判定

    private func evaluate(_ location: CLLocation) {
        let now = Date()
        lastFixAt = now
        fixCount += 1

        let acc = location.horizontalAccuracy
        let accOk = acc > 0 && acc <= maxAccuracy

        for r in active {
            let d = Geo.distance(location.coordinate,
                                 CLLocationCoordinate2D(latitude: r.lat, longitude: r.lng))

            // 网络/基站定位通常不提供 speed，用相邻两次定位的距离差自行估算
            var est: Double = -1
            if let prevD = lastDistance[r.id], let prevT = lastFixTime[r.id] {
                let dt = now.timeIntervalSince(prevT)
                if dt > 0.5 { est = abs(prevD - d) / dt }
            }

            lastDistance[r.id] = d
            lastFixTime[r.id] = now
            minDist[r.id] = min(minDist[r.id] ?? d, d)

            var h = distHist[r.id] ?? []
            h.append(d)
            while h.count > historyLength { h.removeFirst() }
            distHist[r.id] = h

            var sp = location.speed
            if sp < 0 { sp = -1 }
            if est > sp { sp = est }
            lastSpeed[r.id] = sp

            if alerted.contains(r.id) { continue }
            if d > Double(r.radiusMeters) { continue }

            let approaching: Bool
            if h.count >= 3 {
                approaching = h[h.count - 1] < h[h.count - 2] && h[h.count - 2] < h[h.count - 3]
            } else {
                approaching = false
            }
            let deepInside = d <= Double(r.radiusMeters) * 0.5
            // 粗定位兜底：精度差但已经很近 —— 宁可早响，也不要漏站
            let coarseClose = !accOk && d <= Double(r.radiusMeters) * 0.4

            if accOk && (approaching || deepInside) {
                TrackLog.log("触发", "\(r.stationName) 距离 \(Int(d.rounded()))m（精度 ±\(Int(acc.rounded()))m），"
                    + (approaching ? "距离持续缩小（接近中）" : "已在半径一半以内"))
                fire(r, distance: d, accuracy: acc, provider: "ios")
            } else if coarseClose {
                TrackLog.log("触发", "\(r.stationName) 距离 \(Int(d.rounded()))m，定位精度仅 ±\(Int(acc.rounded()))m 但已很近，粗定位兜底触发")
                fire(r, distance: d, accuracy: acc, provider: "ios-coarse")
            } else if !accOk {
                TrackLog.log("跳过", "\(r.stationName) 距离 \(Int(d.rounded()))m，精度 ±\(Int(acc.rounded()))m 太差，等下一个点")
            } else {
                TrackLog.log("观察", "\(r.stationName) 距离 \(Int(d.rounded()))m 在半径内，但距离未持续缩小（可能是路过），暂不触发")
            }
        }

        consecutive += 1
        if consecutive % 3 == 1 || consecutive == 1 {
            updateStatusLine()
        }
    }

    /// 进入围栏：升级为连续 GPS，并在宽限期内没拿到定位时兜底触发。
    /// 与 Android 版一致：只在监控窗口内（或刚过窗口 10 分钟内）才动作，
    /// 避免「住在站附近」的用户在非通勤时间被误报。
    private func handleRegion(_ region: CLRegion, entered: Bool) {
        guard entered else { return }
        guard let id = MonitorEngine.routeId(from: region.identifier) else { return }
        guard let route = RouteStore.shared.find(id), route.enabled else { return }

        let now = Date()
        regionEnteredAt[region.identifier] = now

        let inWindow = WindowScheduler.inWindow(route, date: now)
        var nearEnd = false
        if let end = WindowScheduler.windowEndToday(route, now: now) {
            nearEnd = now.timeIntervalSince(end) < 10 * 60
        }

        TrackLog.log("围栏", "进入提醒站围栏：\(route.stationName)（id=\(id)，窗口内=\(inWindow)）")
        Diag.event("region_enter", "进入围栏 \(route.stationName)（id=\(id)，窗口内=\(inWindow)）")

        guard inWindow || nearEnd else {
            TrackLog.log("围栏", "非窗口内越过提醒站围栏，不开始监控（窗口 \(route.windowText)）")
            return
        }

        if !running {
            // 围栏唤醒：窗口内必须开监控；刚过窗口也开 3 分钟做近距离确认（成本很低，只在你已到站附近时发生）
            startMonitoring(routeId: id, forceMinutes: 0, source: "region")
            if !running {
                startMonitoring(routeId: id, forceMinutes: 3, source: "region-near")
            }
        }

        // 兜底：进入围栏后 45 秒仍没有可用定位，直接按"已到站"处理
        DispatchQueue.main.asyncAfter(deadline: .now() + regionEntryGrace) { [weak self] in
            guard let self = self, self.running else { return }
            guard let r = self.active.first(where: { $0.id == id }) else { return }
            if self.alerted.contains(id) { return }
            let gotFix = self.lastFixTime[id] != nil && Date().timeIntervalSince(self.lastFixTime[id]!) < self.regionEntryGrace
            if gotFix { return }
            TrackLog.log("触发", "\(r.stationName) 进入围栏 \(Int(self.regionEntryGrace)) 秒未拿到定位，按已到站兜底触发")
            self.fire(r, distance: self.lastDistance[id] ?? -1, accuracy: -1, provider: "region")
        }
    }

    private static func routeId(from regionIdentifier: String) -> Int64? {
        let prefix = "arravid.route."
        guard regionIdentifier.hasPrefix(prefix) else { return nil }
        return Int64(regionIdentifier.dropFirst(prefix.count))
    }

    // MARK: - 触发提醒

    /// 同一条线路 60 分钟内已提醒过就不再重复
    private func recentlyAlerted(_ r: Route) -> Bool {
        let key = "arravid_alert_r\(r.id)"
        let last = UserDefaults.standard.double(forKey: key)
        return last > 0 && Date().timeIntervalSince1970 - last < 60 * 60
    }

    private func markAlerted(_ r: Route) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "arravid_alert_r\(r.id)")
    }

    private func fire(_ r: Route, distance: Double, accuracy: Double, provider: String) {
        if recentlyAlerted(r) {
            alerted.insert(r.id)
            TrackLog.log("跳过", "\(r.stationName) 最近已提醒过（60 分钟内），不再重复提醒")
            return
        }
        markAlerted(r)
        alerted.insert(r.id)

        let distText = distance >= 0 ? "\(Int(distance.rounded()))m" : "未知"
        let accText = accuracy >= 0 ? "±\(Int(accuracy.rounded()))m" : "未知"
        Diag.event("alarm_fired", "\(r.stationName) 距离 \(distText)，精度 \(accText)，来源 \(provider)")
        recordArrival(r)
        AlarmEngine.shared.start(route: r)
        updateStatusLine()
    }

    /// 记录实际到站时间，用于自动学习
    private func recordArrival(_ r: Route) {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)

        var route = r
        if let last = route.arrivalHistory.last {
            let diff = abs(minutes - last)
            if diff <= 5 || diff >= 1435 {
                TrackLog.log("学习", "\(r.stationName) 与上一次样本（\(Route.minsToText(last))）过近，本次不重复记录")
                return
            }
        }
        route.arrivalHistory.append(minutes)
        while route.arrivalHistory.count > 20 { route.arrivalHistory.removeFirst() }
        RouteStore.shared.upsert(route)
        if let idx = active.firstIndex(where: { $0.id == r.id }) {
            active[idx] = route
        }
        TrackLog.log("学习", "\(r.stationName) 记录到站时间 \(Route.minsToText(minutes))，样本 \(route.arrivalHistory.count) 个")
    }

    // MARK: - 状态文案 / 通知

    private var statusDetail: String {
        var parts: [String] = []
        for r in active {
            if let d = lastDistance[r.id] {
                parts.append("\(r.stationName) 距 \(Geo.human(d))")
            } else {
                parts.append("\(r.stationName) 定位中…")
            }
        }
        return parts.joined(separator: "　|　")
    }

    private func updateStatusLine(prefix: String? = nil) {
        let head = prefix ?? "正在监控 \(active.count) 条线路\(testMode ? "（测试）" : "")"
        statusLine = statusDetail.isEmpty ? head : "\(head)　\(statusDetail)"
        guard running, !testMode else { return }
        // 每 3 个点更新一次后台通知（passive：不响不亮，只在通知中心里看进度）
        if consecutive % 3 == 1 || consecutive == 1 || prefix != nil {
            NotificationService.shared.updateMonitorNotification(
                title: "正在监控 \(active.count) 条线路",
                body: statusDetail.isEmpty ? "等待定位…" : statusDetail)
        }
    }

    private func alertNotificationRemove() {
        NotificationService.shared.removeMonitorNotification()
    }

    private func minDistText() -> String {
        let parts = active.map { r -> String in
            if let d = minDist[r.id] { return "\(r.stationName) \(Int(d.rounded()))m" }
            return "\(r.stationName) 没收到过定位"
        }
        return parts.isEmpty ? "无" : parts.joined(separator: "；")
    }

    static func hhmm(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return "\(Route.two(c.hour ?? 0)):\(Route.two(c.minute ?? 0))"
    }

    static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "未询问"
        case .restricted: return "受限"
        case .denied: return "已拒绝"
        case .authorizedAlways: return "始终允许"
        case .authorizedWhenInUse: return "使用期间"
        @unknown default: return "未知"
        }
    }
}