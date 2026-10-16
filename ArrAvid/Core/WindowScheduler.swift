//
//  WindowScheduler.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Scheduler.java
//
//  ⚠️ 平台差异（重要）：
//  Android 可以用 AlarmManager.setExactAndAllowWhileIdle 在「窗口开始」那一刻精确唤醒 App；
//  iOS 完全没有等价能力（没有精确闹钟、没有后台定时启动）。因此 iOS 版的策略是：
//    1) 常驻「地理围栏监控 + 显著位置变化」——几乎不耗电，系统在跨基站/进出围栏时唤醒 App；
//    2) 只有在「监控窗口」内（或用 App 时）才升级为连续 GPS 定位；
//    3) 窗口计算逻辑与 Android 完全一致，用于判定"现在该不该盯着"。
//  这样既保住了「其余时间不取 GPS」的省电目标，又不依赖系统定时唤醒。
//

import Foundation

enum WindowScheduler {

    /// 请求码（保留自 Android 版，方便日志对齐；iOS 端用于通知标识）
    static func requestCode(_ id: Int64) -> Int {
        Int(abs(id) % 100000) + 100
    }

    // MARK: - 窗口判定

    /// 现在是否已经落在该线路的监控窗口内
    static func isNowInWindow(_ r: Route) -> Bool {
        inWindow(r, date: Date())
    }

    static func inWindow(_ r: Route, date: Date) -> Bool {
        let cal = Calendar.current
        if !r.isDayEnabled(cal.component(.weekday, from: date)) { return false }
        let comps = cal.dateComponents([.hour, .minute], from: date)
        let cur = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        return cur >= r.windowStartMinutes && cur <= r.windowEndMinutes
    }

    // MARK: - 下一次该启动监控的时刻

    /// 下一次该启动监控的时刻；nil 表示没有可排定的时间。
    ///
    /// 关键修正（沿用 Android 1.4.x 的修复）：今天已经过了「开启点」、但「现在」仍在窗口内
    /// （例如 18:50 保存一条 18:45-19:10 的线路），应当立刻开始监控，而不是等到明天。
    static func nextTriggerDate(_ r: Route, now: Date = Date(), allowImmediate: Bool = true) -> Date? {
        let startMin = r.windowStartMinutes
        let cal = Calendar.current

        for off in 0...7 {
            guard let day = cal.date(byAdding: .day, value: off, to: now) else { continue }
            var comps = cal.dateComponents([.year, .month, .day], from: day)
            comps.hour = startMin / 60
            comps.minute = startMin % 60
            comps.second = 0
            guard let candidate = cal.date(from: comps) else { continue }
            if !r.isDayEnabled(cal.component(.weekday, from: candidate)) { continue }

            if candidate.timeIntervalSince(now) > 5 { return candidate }

            // 今天的开启点已过：若现在仍在窗口内，应当立刻开始监控
            if off == 0 && allowImmediate {
                if let end = windowEndDate(r, on: now), now <= end {
                    return now.addingTimeInterval(3)
                }
            }
        }
        return nil
    }

    /// 指定「某天」的窗口结束时刻
    static func windowEndDate(_ r: Route, on date: Date) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: date)
        comps.hour = r.windowEndMinutes / 60
        comps.minute = r.windowEndMinutes % 60
        comps.second = 0
        return cal.date(from: comps)
    }

    /// 今天的窗口结束时刻
    static func windowEndToday(_ r: Route, now: Date = Date()) -> Date? {
        windowEndDate(r, on: now)
    }

    /// 今天窗口开始时刻（用于计算"晚了多少分钟"）
    static func windowStartToday(_ r: Route, now: Date = Date()) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = r.windowStartMinutes / 60
        comps.minute = r.windowStartMinutes % 60
        comps.second = 0
        return cal.date(from: comps)
    }

    // MARK: - 文案

    static func describeNext(_ r: Route) -> String {
        let now = Date()
        if isNowInWindow(r) {
            return "现在就在监控窗口内（\(r.windowText)）"
        }
        guard let at = nextTriggerDate(r, now: now, allowImmediate: false) else { return "未排定" }
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day, .hour, .minute], from: at)
        let diff = at.timeIntervalSince(now)
        let hours = Int(diff) / 3600
        let mins = (Int(diff) % 3600) / 60
        let when = "\(comps.month ?? 0)月\(comps.day ?? 0)日 "
            + "\(Route.two(comps.hour ?? 0)):\(Route.two(comps.minute ?? 0))"
        let left = hours > 0 ? "\(hours) 小时 \(mins) 分后" : "\(mins) 分后"
        return "\(when)（\(left)）"
    }
}