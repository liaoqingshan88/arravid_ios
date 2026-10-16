//
//  AppState.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：MainActivity.renderSetup() 里那套权限自检 + 线路列表状态。
//

import Foundation
import SwiftUI
import CoreLocation
import UserNotifications
import UIKit

final class AppState: ObservableObject {

    static let shared = AppState()

    @Published var routes: [Route] = []
    @Published var toast: String?

    // 权限自检
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var preciseAccuracy = true
    @Published var notificationAuthorized = false
    @Published var backgroundRefreshEnabled = true
    @Published var locationServicesEnabled = true
    @Published var monitoredRegionCount = 0

    private var toastWork: DispatchWorkItem?

    private init() {}

    // MARK: - 刷新

    func refresh() {
        routes = RouteStore.shared.load()
        locationStatus = MonitorEngine.shared.authorizationStatus
        preciseAccuracy = MonitorEngine.shared.preciseAccuracy
        locationServicesEnabled = CLLocationManager.locationServicesEnabled()
        backgroundRefreshEnabled = UIApplication.shared.backgroundRefreshStatus == .available
        monitoredRegionCount = MonitorEngine.shared.monitoredRegionCount

        NotificationService.shared.authorizationStatus { [weak self] status in
            self?.notificationAuthorized = (status == .authorized || status == .provisional || status == .ephemeral)
        }
    }

    func showToast(_ text: String, seconds: Double = 2.5) {
        toastWork?.cancel()
        toast = text
        let work = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    // MARK: - 线路操作

    func setEnabled(_ route: Route, _ enabled: Bool) {
        RouteStore.shared.setEnabled(route.id, enabled)
        reloadAndRearm()
    }

    func delete(_ route: Route) {
        RouteStore.shared.delete(route.id)
        reloadAndRearm()
        showToast("已删除「\(route.name)」")
    }

    func reloadAndRearm() {
        routes = RouteStore.shared.load()
        MonitorEngine.shared.refreshRegions()
        monitoredRegionCount = MonitorEngine.shared.monitoredRegionCount
    }

    // MARK: - 权限自检结果

    struct CheckItem: Identifiable {
        let id = UUID()
        var title: String
        var impact: String
        var actionTitle: String
        var action: () -> Void
    }

    /// 只把「还没做」的项列出来；全部就绪时返回空数组。
    func pendingChecks() -> [CheckItem] {
        var items: [CheckItem] = []

        if !locationServicesEnabled {
            items.append(CheckItem(
                title: "系统定位服务未打开",
                impact: "拿不到位置，无法判断到站",
                actionTitle: "去打开",
                action: { Self.openSystemSettings(path: "App-Prefs:Privacy&path=LOCATION") }))
        }

        switch locationStatus {
        case .authorizedAlways:
            if !preciseAccuracy {
                items.append(CheckItem(
                    title: "定位精度被设成「大致位置」",
                    impact: "误差可能几公里，会漏提醒；请在设置里打开「精确位置」",
                    actionTitle: "去设置",
                    action: { Self.openAppSettings() }))
            }
        case .authorizedWhenInUse:
            items.append(CheckItem(
                title: "定位不是「始终允许」",
                impact: "锁屏或切到后台时拿不到位置，到站不会响",
                actionTitle: "去设置",
                action: { MonitorEngine.shared.requestAlways(); Self.openAppSettings() }))
        case .notDetermined:
            items.append(CheckItem(
                title: "还没有定位权限",
                impact: "必须授权「始终允许」才能在后台判断到站",
                actionTitle: "去授权",
                action: { MonitorEngine.shared.requestAlways() }))
        default:
            items.append(CheckItem(
                title: "定位权限被拒绝",
                impact: "无法判断到站；请到系统设置里改回「始终允许」",
                actionTitle: "去设置",
                action: { Self.openAppSettings() }))
        }

        if !notificationAuthorized {
            items.append(CheckItem(
                title: "通知未授权",
                impact: "到站提醒弹不出来（只剩 App 在前台时的声音）",
                actionTitle: "去授权",
                action: { NotificationService.shared.requestAuthorization { _ in AppState.shared.refresh() } }))
        }

        if !backgroundRefreshEnabled {
            items.append(CheckItem(
                title: "后台 App 刷新被关闭",
                impact: "系统可能不把位置事件交给本 App，到站不响",
                actionTitle: "去设置",
                action: { Self.openAppSettings() }))
        }

        if routes.contains(where: { $0.enabled && $0.hasLocation }) && monitoredRegionCount == 0 {
            items.append(CheckItem(
                title: "提醒站围栏未生效",
                impact: "通常是定位权限或系统定位服务的问题，先修上面几项",
                actionTitle: "重排",
                action: { MonitorEngine.shared.refreshRegions(); AppState.shared.refresh() }))
        }

        return items
    }

    var checkSummary: String {
        let loc = locationStatus == .authorizedAlways ? "✅" : "❌"
        let precise = preciseAccuracy ? "✅" : "❌"
        let notify = notificationAuthorized ? "✅" : "❌"
        let refresh = backgroundRefreshEnabled ? "✅" : "❌"
        let services = locationServicesEnabled ? "✅" : "❌"
        let regions = monitoredRegionCount > 0 ? "✅" : "❌"
        return "定位\(loc)　精确\(precise)　通知\(notify)　后台刷新\(refresh)　定位服务\(services)　围栏\(regions)"
    }

    // MARK: - 打开系统设置

    static func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func openSystemSettings(path: String) {
        if let url = URL(string: path), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
            return
        }
        openAppSettings()
    }
}