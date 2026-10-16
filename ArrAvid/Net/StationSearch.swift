//
//  StationSearch.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：StationSearch.java
//  按名称查公交/地铁站点坐标。使用开发者内置的高德 Web 服务 Key，终端用户无需配置。
//
//  沿用 Android 端 v1.3.4 的关键修正：
//   1) 类型码用「交通设施服务」大类 150000（含地铁站 150500 / 公交车站 150700 / 火车站 150200）；
//   2) 结果太少时补一次「不加类型过滤」的搜索并合并去重；
//   3) 有定位时先反查城市(adcode)再搜索，避免「会展中心」这类泛词返回 0 个 POI；
//   4) 高德免费 Key 并发很低，对限流做一次退避重试。
//

import Foundation
import CoreLocation

final class StationSearch {

    struct Item: Identifiable {
        let id = UUID()
        var name = ""
        var address = ""
        var city = ""
        var type = ""
        /// WGS-84，可直接与手机 GPS 比较
        var lat: Double = 0
        var lng: Double = 0

        var display: String {
            if !address.isEmpty && address != name { return "\(name)（\(address)）" }
            return name
        }
    }

    private static let amapHost = "https://restapi.amap.com"
    /// 交通设施服务大类：含 150500 地铁站 / 150700 公交车站 / 150200 火车站 / 150600 轻轨站
    private static let typesTransport = "150000"
    /// 结果少于这个数就再补一次不带过滤的搜索
    private static let minTypedResults = 5

    enum SearchError: LocalizedError {
        case api(String, String)     // info, infocode
        case message(String)
        case network(String)

        var errorDescription: String? {
            switch self {
            case .api(let info, let code): return StationSearch.friendly(info: info, infocode: code)
            case .message(let m): return m
            case .network(let m): return "查询失败：\(m)"
            }
        }

        var isRateLimited: Bool {
            if case .api(_, let code) = self {
                return code == "10021" || code == "10019" || code == "10020"
            }
            return false
        }
    }

    private static func friendly(info: String, infocode: String) -> String {
        switch infocode {
        case "10021", "10019", "10020": return "查询太频繁，请等几秒再试。"
        case "10003": return "今日查询额度已用完，明天再试。"
        case "10001", "10002": return "地图服务 Key 无效或已过期。"
        case "10009": return "地图 Key 类型不匹配（需「Web 服务」类型）。"
        default: return "地图接口返回错误：\(info)"
        }
    }

    // MARK: - 对外入口

    static func search(keyword: String, completion: @escaping ([Item]?, String?) -> Void) {
        let kw = keyword.trimmingCharacters(in: .whitespaces)
        guard !kw.isEmpty else {
            completion(nil, "请输入车站名称")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [Item] = []
            var error: String?
            do {
                if MapConfig.isSearchAvailable {
                    if !MapConfig.amapKey.trimmingCharacters(in: .whitespaces).isEmpty {
                        let city = resolveCity()   // 失败也没关系，只是准确度差些
                        var out = try fetchWithRetry(url: try buildURL(
                            path: "/v3/place/text",
                            params: amapParams(keyword: kw, types: typesTransport, city: city)))

                        if out.count < minTypedResults {
                            sleepQuiet(0.4)
                            let all = try fetchWithRetry(url: try buildURL(
                                path: "/v3/place/text",
                                params: amapParams(keyword: kw, types: nil, city: city)))
                            for it in all where !containsSimilar(out, it) {
                                out.append(it)
                            }
                        }
                        items = out
                    } else {
                        let proxy = MapConfig.proxyURL.trimmingCharacters(in: .whitespaces)
                        let encoded = kw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kw
                        items = try fetchWithRetry(url: proxy + "?kw=" + encoded)
                    }
                    if items.isEmpty {
                        error = "没有找到「\(kw)」相关站点。可以带上城市名再试，例如「深圳\(kw)」。"
                    }
                } else {
                    error = "该功能未启用。请改用「当前位置」或「地图选点」。"
                }
            } catch let e as SearchError {
                error = e.errorDescription
            } catch let e {
                error = "查询失败：\(e.localizedDescription)"
            }
            let resultItems = items
            let resultError = error
            DispatchQueue.main.async {
                completion(resultItems.isEmpty ? nil : resultItems, resultError)
            }
        }
    }

    // MARK: - 内部实现

    private static func containsSimilar(_ list: [Item], _ it: Item) -> Bool {
        list.contains { $0.name == it.name && abs($0.lat - it.lat) < 0.0005 }
    }

    private static func sleepQuiet(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private static func buildURL(path: String, params: [(String, String?)]) throws -> String {
        var comps = URLComponents(string: amapHost + path)
        comps?.queryItems = params.map {
            URLQueryItem(name: $0.0, value: $0.1 ?? "")
        }
        guard let url = comps?.url?.absoluteString else {
            throw SearchError.message("URL 拼装失败")
        }
        return url
    }

    private static func amapParams(keyword: String, types: String?, city: String?) -> [(String, String?)] {
        var p: [(String, String?)] = [
            ("output", "JSON"),
            ("offset", "20"),
            ("page", "1"),
            ("extensions", "base"),
            ("key", MapConfig.amapKey.trimmingCharacters(in: .whitespaces)),
            ("keywords", keyword)
        ]
        if let city = city, !city.isEmpty { p.append(("city", city)) }
        if let types = types { p.append(("types", types)) }
        return p
    }

    /// 被限流时退避 1.5 秒重试一次
    private static func fetchWithRetry(url: String) throws -> [Item] {
        do {
            return try fetch(url: url)
        } catch let e as SearchError where e.isRateLimited {
            sleepQuiet(1.5)
            return try fetch(url: url)
        }
    }

    private static func requestJSON(_ url: String) throws -> [String: Any] {
        guard let u = URL(string: url) else { throw SearchError.message("URL 无效") }
        var req = URLRequest(url: u)
        req.timeoutInterval = 8
        let sem = DispatchSemaphore(value: 0)
        var resultData: Data?
        var resultError: Error?
        URLSession.shared.dataTask(with: req) { data, _, err in
            resultData = data
            resultError = err
            sem.signal()
        }.resume()
        sem.wait()
        if let err = resultError { throw SearchError.network(err.localizedDescription) }
        guard let data = resultData,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SearchError.network("返回内容无法解析")
        }
        if (obj["status"] as? String) != "1" {
            throw SearchError.api(obj["info"] as? String ?? "未知错误",
                                  obj["infocode"] as? String ?? "")
        }
        return obj
    }

    /// 拉取并解析高德 place/text 结构（代理接口也用同一结构）
    private static func fetch(url: String) throws -> [Item] {
        let root = try requestJSON(url)
        guard let pois = root["pois"] as? [[String: Any]] else { return [] }
        var out: [Item] = []
        for p in pois {
            guard let loc = p["location"] as? String, loc.contains(",") else { continue }
            let parts = loc.split(separator: ",")
            guard parts.count >= 2,
                  let gcjLng = Double(parts[0]), let gcjLat = Double(parts[1]) else { continue }
            // 高德返回 GCJ-02，转成 WGS-84 再入库
            let wgs = Geo.gcj02ToWgs84(gcjLat, gcjLng)
            var it = Item()
            it.name = p["name"] as? String ?? ""
            it.address = p["address"] as? String ?? ""
            it.city = p["cityname"] as? String ?? ""
            it.type = p["type"] as? String ?? ""
            it.lat = wgs.latitude
            it.lng = wgs.longitude
            out.append(it)
        }
        return out
    }

    /// 用「最后一次已知位置」反查城市 adcode，缓存 6 小时。
    private static func resolveCity() -> String? {
        let cached = RouteStore.shared.cachedCity()
        guard let loc = LocationOnce.lastKnown() else { return cached }
        let gcj = Geo.wgs84ToGcj02(loc.coordinate.latitude, loc.coordinate.longitude)
        let url = try? buildURL(path: "/v3/geocode/regeo", params: [
            ("output", "JSON"),
            ("key", MapConfig.amapKey.trimmingCharacters(in: .whitespaces)),
            ("location", "\(gcj.longitude),\(gcj.latitude)")
        ])
        guard let u = url, let root = try? requestJSON(u) else { return cached }
        if let rc = root["regeocode"] as? [String: Any],
           let adcode = rc["adcode"] as? String, !adcode.isEmpty {
            RouteStore.shared.storeCity(adcode)
            return adcode
        }
        return cached
    }
}