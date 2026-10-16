//
//  UpdateChecker.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：UpdateChecker.java（去掉了「下载 APK 并调起安装」的部分）
//
//  ⚠️ 平台差异：iOS 禁止应用自升级，也不能安装 ipa。所以这里只做「查版本 + 提示」，
//  真正的升级方式是：重新用 Sideloadly / AltStore 覆盖安装（免费证书 7 天），
//  或用 Xcode 重新运行。UI 里会把这一点讲清楚。
//

import Foundation

enum UpdateChecker {

    struct VersionInfo {
        var version: String = ""
        var versionCode: Int = 0
        var size: Int64 = 0
        var updateLog: String = ""
        var downloadUrl: String = ""
    }

    /// 查询结果回调：nil 表示查询失败
    static func fetch(completion: @escaping (VersionInfo?) -> Void) {
        attempt(bases: Api.bases, completion: completion)
    }

    private static func attempt(bases: [String], completion: @escaping (VersionInfo?) -> Void) {
        guard let base = bases.first, let url = URL(string: base + Api.pathVersion) else {
            completion(nil)
            return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200, let data = data,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var info = VersionInfo()
                info.version = obj["version"] as? String ?? ""
                info.versionCode = obj["versionCode"] as? Int ?? 0
                info.size = (obj["size"] as? NSNumber)?.int64Value ?? 0
                info.updateLog = obj["updateLog"] as? String ?? ""
                info.downloadUrl = obj["downloadUrl"] as? String ?? ""
                DispatchQueue.main.async { completion(info) }
            } else {
                attempt(bases: Array(bases.dropFirst()), completion: completion)
            }
        }.resume()
    }

    /// 人工检查的结论文案
    static func manualResultText(_ info: VersionInfo?) -> String {
        guard let info = info else { return "检查更新失败：网络不可用或服务器无响应" }
        if info.versionCode <= AppInfo.versionCode {
            return "已是最新版本 v\(AppInfo.versionName)"
        }
        var msg = "发现新版本 v\(info.version)"
        if info.size > 0 {
            msg += String(format: "（%.1f MB）", Double(info.size) / 1_048_576.0)
        }
        if !info.updateLog.isEmpty {
            msg += "\n\n更新内容：\n\(info.updateLog)"
        }
        msg += "\n\niOS 版升级方式：用 Sideloadly / AltStore 重新安装新的 ipa 即可覆盖升级，线路配置不会丢。"
        return msg
    }
}