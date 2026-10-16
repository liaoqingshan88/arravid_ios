//
//  Diag.swift / DeviceReport.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Diag.java + DeviceReport.java
//  把「提醒是否成功」这类关键事件上报到服务器（按设备记录），便于远程排查。
//  全部在后台线程发送，失败静默；绝不会影响提醒本身。
//

import Foundation

enum Diag {

    /// 事件类型（与 Android 端保持一致，服务端看板可直接复用）：
    ///   boot          应用启动/重排
    ///   alarm         监控窗口的定时触发
    ///   monitor_start 监控启动
    ///   alarm_fired   判定到站并触发提醒
    ///   alarm_ack     用户点了「我已下车」
    ///   alarm_ui      提醒页面弹出情况
    ///   monitor_end   监控结束
    static func event(_ type: String, _ detail: String) {
        let payload: [String: Any] = [
            "deviceId": AppInfo.deviceId,
            "app": Api.appId,
            "type": type,
            "detail": detail,
            "appVersion": AppInfo.versionName,
            "versionCode": AppInfo.versionCode,
            "androidVersion": AppInfo.systemVersion,   // 字段名沿用服务端旧协议
            "manufacturer": AppInfo.manufacturer,
            "model": AppInfo.model,
            "platform": "ios",
            "ts": Int(Date().timeIntervalSince1970 * 1000)
        ]
        post(path: Api.pathEvent, payload: payload, expectSuccessFlag: false) { _ in }
    }

    /// 依次尝试主/备地址，任一成功即回调 true
    @discardableResult
    static func post(path: String,
                     payload: [String: Any],
                     expectSuccessFlag: Bool,
                     completion: @escaping (Bool) -> Void) -> URLSessionTask? {
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return nil
        }
        return attempt(bases: Api.bases, path: path, body: body,
                       expectSuccessFlag: expectSuccessFlag, completion: completion)
    }

    private static func attempt(bases: [String],
                                path: String,
                                body: Data,
                                expectSuccessFlag: Bool,
                                completion: @escaping (Bool) -> Void) -> URLSessionTask? {
        guard let base = bases.first, let url = URL(string: base + path) else {
            completion(false)
            return nil
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        req.timeoutInterval = 8

        let task = URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            var ok = code == 200
            if ok && expectSuccessFlag {
                let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                ok = text.contains("\"success\":true")
            }
            if ok {
                completion(true)
            } else {
                _ = attempt(bases: Array(bases.dropFirst()), path: path, body: body,
                            expectSuccessFlag: expectSuccessFlag, completion: completion)
            }
        }
        task.resume()
        return task
    }
}

enum DeviceReport {

    private static let keyLast = "arravid_stats_last_report"
    private static let interval: TimeInterval = 24 * 3600

    /// 每天最多上报一次；只包含机型和系统/应用版本，不含任何可识别个人身份的信息，也不含位置。
    static func reportIfNeeded() {
        let last = UserDefaults.standard.double(forKey: keyLast)
        let now = Date().timeIntervalSince1970
        if last > 0 && now - last < interval { return }

        let payload: [String: Any] = [
            "deviceId": AppInfo.deviceId,
            "app": Api.appId,
            "deviceInfo": AppInfo.deviceInfo,
            "manufacturer": AppInfo.manufacturer,
            "model": AppInfo.model,
            "androidVersion": AppInfo.systemVersion,
            "appVersion": AppInfo.versionName,
            "versionCode": AppInfo.versionCode,
            "platform": "ios"
        ]
        Diag.post(path: Api.pathReport, payload: payload, expectSuccessFlag: true) { ok in
            if ok {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: keyLast)
            }
        }
    }
}