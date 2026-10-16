//
//  Config.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Api.java / MapConfig.java / AppInfo.java
//

import Foundation
import UIKit
import CryptoKit

// MARK: - 服务端接口

/// 服务端接口配置。设备统计与股票预警共用同一套接口，用 app 字段区分。
enum Api {
    /// 主地址：域名
    static let basePrimary = "http://www.yanhexing.com:9000"
    /// 备用地址：IP 直连（域名解析异常时兜底）
    static let baseFallback = "http://47.107.180.174:9000"

    /// 版本接口：到站提醒专属（用于检查更新）
    static let pathVersion = "/api/arravid/version"
    /// 设备上报：与股票预警共用同一套系统，靠 app 字段区分
    static let pathReport = "/api/device/report"
    /// 诊断事件上报
    static let pathEvent = "/api/arravid/event"

    /// 本产品在统计系统里的标识
    static let appId = "arravid"

    static var bases: [String] { [basePrimary, baseFallback] }
}

// MARK: - 地图服务配置

/// 开发者内置配置：地图服务。终端用户不需要任何配置。
///
/// 与 Android 版行为一致：
///  * AMAP_KEY 非空 → 直连高德 Web 服务，按名称查站点可用；
///  * PROXY_URL 非空 → 走自建代理（返回与高德 place/text 相同结构）；
///  * 两者都为空 → 「按名称查」不可用，另两种方式（当前位置 / 地图选点）照常。
enum MapConfig {
    /// 高德 Web 服务 Key（开发者内置）
    static let amapKey = "9c956e6ad9d2d2390fad99cb3d7f9043"
    /// 自建代理接口地址
    static let proxyURL = ""

    static var isSearchAvailable: Bool {
        !amapKey.trimmingCharacters(in: .whitespaces).isEmpty
            || !proxyURL.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - 应用/设备信息

enum AppInfo {

    static var versionName: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    static var versionCode: Int {
        let raw = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "0"
        return Int(raw) ?? 0
    }

    static var bundleId: String {
        Bundle.main.bundleIdentifier ?? "com.arravid.reminder"
    }

    private static let fallbackKey = "arravid_fallback_id"

    /// 匿名设备标识：iOS 上没有 ANDROID_ID，改用 identifierForVendor（按「厂商 + 设备」隔离），
    /// 拿不到时落一个随机 UUID 并持久化；再拼上包名做 SHA-256 后截断 32 位，服务器端拿不到原始 ID。
    static var deviceId: String {
        var raw: String?
        if let idfv = UIDevice.current.identifierForVendor?.uuidString, !idfv.isEmpty {
            raw = idfv
        }
        if raw == nil {
            let defaults = UserDefaults.standard
            if let saved = defaults.string(forKey: fallbackKey) {
                raw = saved
            } else {
                let generated = UUID().uuidString
                defaults.set(generated, forKey: fallbackKey)
                raw = generated
            }
        }
        return sha256Hex(raw! + "|" + bundleId)
    }

    /// 机型信息（与 Android 版字段对齐，方便服务端同一套看板统计）
    static var manufacturer: String { "Apple" }

    static var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial += String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? UIDevice.current.model : identifier
    }

    static var systemVersion: String { UIDevice.current.systemVersion }

    static var deviceInfo: String { "\(manufacturer) \(model)" }

    private static func sha256Hex(_ input: String) -> String {
        guard let data = input.data(using: .utf8) else { return "unknown" }
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(32))
    }
}