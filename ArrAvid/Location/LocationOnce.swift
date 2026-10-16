//
//  LocationOnce.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Loc.java
//  一次性取点工具（用于「用当前位置设为终点站」）。
//

import Foundation
import CoreLocation

final class LocationOnce: NSObject, CLLocationManagerDelegate {

    typealias Callback = (CLLocation?) -> Void

    /// 全局最后一次已知位置（由 MonitorEngine 每次定位成功后写入），供「按名称查站点」反查城市用。
    private static let keyLastLat = "arravid_last_known_lat"
    private static let keyLastLng = "arravid_last_known_lng"
    private static let keyLastAt = "arravid_last_known_at"

    static func lastKnown() -> CLLocation? {
        let d = UserDefaults.standard
        guard d.object(forKey: keyLastLat) != nil else { return nil }
        let lat = d.double(forKey: keyLastLat)
        let lng = d.double(forKey: keyLastLng)
        let at = d.double(forKey: keyLastAt)
        if lat == 0 && lng == 0 { return nil }
        return CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                          altitude: 0,
                          horizontalAccuracy: -1,
                          verticalAccuracy: -1,
                          timestamp: Date(timeIntervalSince1970: at))
    }

    static func remember(_ location: CLLocation) {
        let d = UserDefaults.standard
        d.set(location.coordinate.latitude, forKey: keyLastLat)
        d.set(location.coordinate.longitude, forKey: keyLastLng)
        d.set(Date().timeIntervalSince1970, forKey: keyLastAt)
    }

    // MARK: - 单次请求

    private let manager = CLLocationManager()
    private var callback: Callback?
    private var finished = false
    private var timeoutWork: DispatchWorkItem?
    /// 拿不到新点时兜底返回的系统缓存位置
    private var bestFallback: CLLocation?

    private static var shared: LocationOnce?

    /// 取一次当前位置；最多等 30 秒，超时返回缓存位置（可能为 nil）。
    static func requestOnce(completion: @escaping Callback) {
        let instance = LocationOnce()
        shared = instance
        instance.start(completion: completion)
    }

    private func start(completion: @escaping Callback) {
        callback = completion
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest

        bestFallback = manager.location

        // 缓存足够新（5 分钟内）就直接用，不必等 GPS
        if let cached = bestFallback, Date().timeIntervalSince(cached.timestamp) < 5 * 60 {
            finish(with: cached)
            return
        }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
        manager.requestLocation()

        let work = DispatchWorkItem { [weak self] in
            self?.finish(with: self?.bestFallback)
        }
        timeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    private func finish(with location: CLLocation?) {
        guard !finished else { return }
        finished = true
        timeoutWork?.cancel()
        timeoutWork = nil
        manager.stopUpdatingLocation()
        let cb = callback
        callback = nil
        cb?(location)
        LocationOnce.shared = nil
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        bestFallback = loc
        LocationOnce.remember(loc)
        finish(with: loc)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: bestFallback)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if !finished { manager.requestLocation() }
        case .denied, .restricted:
            finish(with: bestFallback)
        default:
            break
        }
    }
}