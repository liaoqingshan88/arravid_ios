//
//  NotificationService.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Notif.java + AlarmEngine 里的通知部分。
//  iOS 的通知分类、权限与投递都在这里收口。
//

import Foundation
import UserNotifications
import UIKit

final class NotificationService {

    static let shared = NotificationService()

    // 标识符
    static let arrivalCategory = "ARRAVID_ARRIVAL"
    static let arrivalNotificationId = "arravid_arrival"
    static let monitorNotificationId = "arravid_monitor"
    static let snoozeNotificationId = "arravid_snooze"

    // 动作标识
    static let actionStop = "ARRAVID_STOP"
    static let actionSnooze = "ARRAVID_SNOOZE"

    private init() {}

    // MARK: - 权限与分类

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = NotificationRouter.shared

        let stop = UNNotificationAction(identifier: Self.actionStop,
                                        title: "我已下车",
                                        options: [.destructive, .foreground])
        let snooze = UNNotificationAction(identifier: Self.actionSnooze,
                                          title: "再过 2 分钟提醒我",
                                          options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.arrivalCategory,
                                              actions: [stop, snooze],
                                              intentIdentifiers: [],
                                              options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    /// 申请通知权限。critical 需要 Apple 单独审批的 entitlement，这里只申请常规+时效性权限。
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async { completion?(granted) }
            }
    }

    func authorizationStatus(completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { completion(settings.authorizationStatus) }
        }
    }

    // MARK: - 到站强提醒

    func postArrival(route: Route) {
        let content = UNMutableNotificationContent()
        content.title = route.announce
        content.body = "即将到达 \(route.stationName)，请准备下车"
        content.categoryIdentifier = Self.arrivalCategory
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "alarm.wav"))
        content.interruptionLevel = .timeSensitive
        content.relevanceScore = 1.0
        content.threadIdentifier = "arravid"
        content.userInfo = ["routeId": route.id]

        let request = UNNotificationRequest(identifier: Self.arrivalNotificationId,
                                            content: content,
                                            trigger: nil)   // nil = 立即投递
        UNUserNotificationCenter.current().add(request)
    }

    func removeArrival() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.arrivalNotificationId])
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.arrivalNotificationId])
    }

    /// 「再过 2 分钟提醒我」
    func scheduleSnooze(route: Route, after seconds: TimeInterval = 120) {
        let content = UNMutableNotificationContent()
        content.title = route.announce
        content.body = "（稍后再提醒）即将到达 \(route.stationName)"
        content.categoryIdentifier = Self.arrivalCategory
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: "alarm.wav"))
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["routeId": route.id, "snooze": true]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: Self.snoozeNotificationId,
                                            content: content,
                                            trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelSnooze() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.snoozeNotificationId])
    }

    // MARK: - 监控状态（被动，不响不亮）

    private var lastMonitorPost = Date.distantPast

    func updateMonitorNotification(title: String, body: String) {
        // 节流：最快 60 秒一次，避免刷屏
        if Date().timeIntervalSince(lastMonitorPost) < 60 { return }
        lastMonitorPost = Date()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.interruptionLevel = .passive
        content.threadIdentifier = "arravid-monitor"

        let request = UNNotificationRequest(identifier: Self.monitorNotificationId,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func removeMonitorNotification() {
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [Self.monitorNotificationId])
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [Self.monitorNotificationId])
    }
}

// MARK: - 通知点击/动作路由

final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {

    static let shared = NotificationRouter()

    private override init() { super.init() }

    /// 前台也把提醒显示出来（否则 App 在前台时通知会被吞掉）
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let id = notification.request.identifier
        if id == NotificationService.monitorNotificationId {
            completionHandler([])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let routeId = (userInfo["routeId"] as? NSNumber)?.int64Value

        switch response.actionIdentifier {
        case NotificationService.actionStop:
            TrackLog.log("确认", "用户在通知里点了「我已下车」")
            Diag.event("alarm_ack", "用户在通知里点了「我已下车」—— 确认收到过提醒")
            AlarmEngine.shared.stop()
            MonitorEngine.shared.stopMonitoring(reason: "用户已下车")

        case NotificationService.actionSnooze:
            TrackLog.log("确认", "用户点了「再过 2 分钟提醒我」")
            AlarmEngine.shared.stop()
            AlarmEngine.shared.snooze(routeId: routeId, after: 120)

        case UNNotificationDefaultActionIdentifier:
            // 点通知主体 → 打开 App；AlarmEngine 会在前台把全屏提醒页拉起来
            if AlarmEngine.shared.active == false, let id = routeId {
                // 通知已经投递了一段时间才被点开，重新拉一次提醒（学习/上报已做过，不再重复）
                AlarmEngine.shared.presentFromNotification(routeId: id)
            }

        default:
            break
        }
        completionHandler()
    }
}