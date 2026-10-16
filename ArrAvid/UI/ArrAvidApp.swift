//
//  ArrAvidApp.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：AndroidManifest.xml 里注册的 Application / BootReceiver / WindowAlarmReceiver。
//  iOS 没有开机广播和后台定时拉起，改成：App 启动 + 每次进后台时重排围栏与后台唤醒源。
//

import SwiftUI
import UIKit
import UserNotifications
import CoreLocation

@main
struct ArrAvidApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(state)
                .environmentObject(AlarmEngine.shared)
                .environmentObject(MonitorEngine.shared)
                .onAppear { state.refresh() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        NotificationService.shared.configure()
        MonitorEngine.shared.configure()

        // 被系统因「位置事件」在后台拉起时（围栏/显著位置变化），先做好准备
        let launchedByLocation = launchOptions?[.location] != nil

        TrackLog.log("启动", launchedByLocation ? "由位置事件在后台唤醒" : "正常启动")
        Diag.event("boot", launchedByLocation ? "由位置事件在后台唤醒" : "正常启动")

        MonitorEngine.shared.armBackgroundWatch()

        if !launchedByLocation {
            // 打开 App 就补排一次（对应 Android 1.4.1 的「每次打开都重排」修复）
            MonitorEngine.shared.refreshRegions()
            DeviceReport.reportIfNeeded()
        }

        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 回到低成本待命状态：围栏 + 显著位置变化
        MonitorEngine.shared.armBackgroundWatch()
        TrackLog.log("待命", "进入后台，已保持在待命状态（围栏 + 显著位置变化）")
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        AppState.shared.refresh()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppState.shared.refresh()
    }
}