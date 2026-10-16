//
//  RouteStore.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：RouteStore.java
//  UserDefaults + JSON 持久化（UserDefaults 在 iOS 上等价于小体积的持久化 KV，足够放线路配置）。
//

import Foundation
import CoreLocation

final class RouteStore {

    static let shared = RouteStore()

    private let defaults = UserDefaults.standard
    private let keyRoutes = "arravid_routes"
    private let keyAmap = "arravid_amap_key"
    private let keyLastLat = "arravid_last_pick_lat"
    private let keyLastLng = "arravid_last_pick_lng"
    private let keyCity = "arravid_city_adcode"
    private let keyCityAt = "arravid_city_at"

    private init() {}

    // MARK: - 线路

    func load() -> [Route] {
        guard let data = defaults.data(forKey: keyRoutes) else { return [] }
        return (try? JSONDecoder().decode([Route].self, from: data)) ?? []
    }

    func save(_ routes: [Route]) {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        defaults.set(data, forKey: keyRoutes)
    }

    func find(_ id: Int64) -> Route? {
        load().first { $0.id == id }
    }

    func upsert(_ route: Route) {
        var list = load()
        if let idx = list.firstIndex(where: { $0.id == route.id }) {
            list[idx] = route
        } else {
            list.append(route)
        }
        save(list)
    }

    func delete(_ id: Int64) {
        save(load().filter { $0.id != id })
    }

    func setEnabled(_ id: Int64, _ enabled: Bool) {
        guard var r = find(id) else { return }
        r.enabled = enabled
        upsert(r)
    }

    var count: Int { load().count }

    // MARK: - 高德 Web 服务 key（用于「按名称查找站点」）

    var amapKey: String {
        get { defaults.string(forKey: keyAmap) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespaces), forKey: keyAmap) }
    }

    // MARK: - 上次地图选点位置

    func lastPick() -> CLLocationCoordinate2D? {
        let lat = defaults.double(forKey: keyLastLat)
        let lng = defaults.double(forKey: keyLastLng)
        if lat == 0 && lng == 0 { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    func setLastPick(_ coord: CLLocationCoordinate2D) {
        defaults.set(coord.latitude, forKey: keyLastLat)
        defaults.set(coord.longitude, forKey: keyLastLng)
    }

    // MARK: - 反查城市缓存（6 小时）

    private let cityTTL: TimeInterval = 6 * 3600

    func cachedCity() -> String? {
        guard let city = defaults.string(forKey: keyCity), !city.isEmpty else { return nil }
        let at = defaults.double(forKey: keyCityAt)
        if Date().timeIntervalSince1970 - at < cityTTL { return city }
        return city.isEmpty ? nil : city
    }

    func storeCity(_ adcode: String) {
        guard !adcode.isEmpty else { return }
        defaults.set(adcode, forKey: keyCity)
        defaults.set(Date().timeIntervalSince1970, forKey: keyCityAt)
    }

    // MARK: - 一次性迁移：把已有线路的提醒半径统一到 800 米

    private let keyMigratedRadius = "arravid_migrated_radius800"

    /// 返回被修改的线路条数
    @discardableResult
    func migrateRadiusTo800() -> Int {
        if defaults.bool(forKey: keyMigratedRadius) { return 0 }
        var changed = 0
        for var r in load() where r.radiusMeters != 800 {
            r.radiusMeters = 800
            upsert(r)
            changed += 1
        }
        defaults.set(true, forKey: keyMigratedRadius)
        return changed
    }
}