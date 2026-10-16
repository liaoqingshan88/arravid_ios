//
//  Route.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Route.java
//  一条通勤线路的配置 + 监控窗口计算。
//

import Foundation

struct Route: Codable, Identifiable, Equatable {

    /// bit0 = 周一 ... bit6 = 周日（与 Android 版完全一致的位序，便于数据迁移）
    static let dayNames = ["一", "二", "三", "四", "五", "六", "日"]
    static let maskWorkday = 0x1F
    static let maskWeekend = 0x60
    static let maskEveryday = 0x7F

    var id: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    var name: String = "上班"
    /// 提醒站名称
    var destName: String = ""
    var lat: Double = 0
    var lng: Double = 0
    var hasLocation: Bool = false
    /// 提醒半径（米）。用户要求统一 800 米。
    var radiusMeters: Int = 800
    /// 预期到站时间 HH:mm
    var arriveTime: String = "08:30"
    /// 到站前多少分钟开始监控
    var leadMinutes: Int = 10
    /// 到站后继续监控多少分钟（固定值，不再暴露给用户）
    var tailMinutes: Int = 15
    /// bit0=周一 ... bit6=周日
    var daysMask: Int = Route.maskWorkday
    var enabled: Bool = true
    var autoLearn: Bool = true
    /// 到站循环播报文字，留空则用「站名 到了，请下车」
    var announceText: String = ""
    /// 旧版本字段，保留兼容，语音播报现已强制开启
    var voiceEnabled: Bool = true
    var arrivalHistory: [Int] = []

    // MARK: - 计算属性

    var coordinate: (lat: Double, lng: Double) { (lat, lng) }

    var arriveMinutes: Int {
        let parts = arriveTime.split(separator: ":")
        guard let h = Int(parts.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "") else {
            return 8 * 60 + 30
        }
        var hour = h
        var minute = 0
        if parts.count > 1 { minute = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0 }
        if hour < 0 || hour > 23 { hour = 8 }
        if minute < 0 || minute > 59 { minute = 30 }
        return hour * 60 + minute
    }

    var medianArrivalMinutes: Int {
        guard !arrivalHistory.isEmpty else { return arriveMinutes }
        let sorted = arrivalHistory.sorted()
        return sorted[sorted.count / 2]
    }

    /// 打开学习且有足够样本时用实际中位数，否则用配置时间。
    var effectiveArrivalMinutes: Int {
        if !autoLearn || arrivalHistory.count < 3 { return arriveMinutes }
        return medianArrivalMinutes
    }

    var windowStartMinutes: Int {
        max(0, effectiveArrivalMinutes - max(1, leadMinutes))
    }

    var windowEndMinutes: Int {
        min(24 * 60 - 1, effectiveArrivalMinutes + max(1, tailMinutes))
    }

    var effectiveTimeText: String { Route.minsToText(effectiveArrivalMinutes) }

    var windowText: String {
        "\(Route.minsToText(windowStartMinutes)) - \(Route.minsToText(windowEndMinutes))"
    }

    var stationName: String {
        let d = destName.trimmingCharacters(in: .whitespaces)
        return d.isEmpty ? "提醒站" : d
    }

    /// 到站要循环播报的文字
    var announce: String {
        let t = announceText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? Route.defaultAnnounce(destName) : t
    }

    static func defaultAnnounce(_ dest: String?) -> String {
        var d = (dest ?? "").trimmingCharacters(in: .whitespaces)
        if d.isEmpty { d = "提醒站" }
        return "\(d) 到了，请下车"
    }

    static func two(_ v: Int) -> String { v < 10 ? "0\(v)" : String(v) }

    static func minsToText(_ mins: Int) -> String {
        let m = ((mins % 1440) + 1440) % 1440
        return "\(two(m / 60)):\(two(m % 60))"
    }

    /// Calendar 的 weekday（1=周日 ... 7=周六）-> 0..6（周一..周日）
    static func dayIndex(_ calendarWeekday: Int) -> Int {
        (calendarWeekday + 5) % 7
    }

    func isDayEnabled(_ calendarWeekday: Int) -> Bool {
        (daysMask & (1 << Route.dayIndex(calendarWeekday))) != 0
    }

    var daysText: String {
        if daysMask == Route.maskEveryday { return "每天" }
        if daysMask == Route.maskWorkday { return "工作日" }
        if daysMask == Route.maskWeekend { return "周末" }
        var sb = ""
        for i in 0..<7 where (daysMask & (1 << i)) != 0 {
            sb += Route.dayNames[i]
        }
        return sb.isEmpty ? "未选择" : "周\(sb)"
    }

    // MARK: - 兼容旧数据

    enum CodingKeys: String, CodingKey {
        case id, name, destName, lat, lng, hasLocation, radiusMeters, arriveTime
        case leadMinutes, tailMinutes, daysMask, enabled, autoLearn, announceText
        case voiceEnabled, arrivalHistory
    }

    init() {}

    /// 容错解码：Android 端存的 JSON 缺少某些字段时用默认值补上。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Route()
        id = (try? c.decode(Int64.self, forKey: .id)) ?? fallback.id
        name = (try? c.decode(String.self, forKey: .name)) ?? fallback.name
        destName = (try? c.decode(String.self, forKey: .destName)) ?? fallback.destName
        lat = (try? c.decode(Double.self, forKey: .lat)) ?? 0
        lng = (try? c.decode(Double.self, forKey: .lng)) ?? 0
        hasLocation = (try? c.decode(Bool.self, forKey: .hasLocation)) ?? false
        radiusMeters = (try? c.decode(Int.self, forKey: .radiusMeters)) ?? 800
        arriveTime = (try? c.decode(String.self, forKey: .arriveTime)) ?? fallback.arriveTime
        leadMinutes = (try? c.decode(Int.self, forKey: .leadMinutes)) ?? 10
        tailMinutes = (try? c.decode(Int.self, forKey: .tailMinutes)) ?? 15
        daysMask = (try? c.decode(Int.self, forKey: .daysMask)) ?? Route.maskWorkday
        enabled = (try? c.decode(Bool.self, forKey: .enabled)) ?? true
        autoLearn = (try? c.decode(Bool.self, forKey: .autoLearn)) ?? true
        announceText = (try? c.decode(String.self, forKey: .announceText)) ?? ""
        voiceEnabled = (try? c.decode(Bool.self, forKey: .voiceEnabled)) ?? true
        arrivalHistory = (try? c.decode([Int].self, forKey: .arrivalHistory)) ?? []
    }
}