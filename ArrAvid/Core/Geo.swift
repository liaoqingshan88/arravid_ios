//
//  Geo.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：Geo.java
//  距离计算 + 火星坐标(GCJ-02)与 GPS(WGS-84)互转。
//

import Foundation
import CoreLocation

enum Geo {

    private static let pi = 3.1415926535897932384626
    private static let a = 6378245.0
    private static let ee = 0.00669342162296594323

    /// 两点直线距离（米）
    static func distance(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    static func distance(fromLat: Double, fromLng: Double, toLat: Double, toLng: Double) -> Double {
        distance(CLLocationCoordinate2D(latitude: fromLat, longitude: fromLng),
                 CLLocationCoordinate2D(latitude: toLat, longitude: toLng))
    }

    /// 人类可读距离
    static func human(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) 米" }
        return String(format: "%.1f 公里", meters / 1000.0)
    }

    // MARK: - 坐标纠偏

    private static func outOfChina(_ lat: Double, _ lng: Double) -> Bool {
        lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271
    }

    private static func transformLat(_ x: Double, _ y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLng(_ x: Double, _ y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return ret
    }

    /// WGS-84（手机 GPS）-> GCJ-02（高德/国内地图）
    static func wgs84ToGcj02(_ lat: Double, _ lng: Double) -> CLLocationCoordinate2D {
        if outOfChina(lat, lng) { return CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        var dLat = transformLat(lng - 105.0, lat - 35.0)
        var dLng = transformLng(lng - 105.0, lat - 35.0)
        let radLat = lat / 180.0 * pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi)
        dLng = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
        return CLLocationCoordinate2D(latitude: lat + dLat, longitude: lng + dLng)
    }

    /// GCJ-02（高德地图/搜索结果）-> WGS-84（手机 GPS），迭代逼近
    static func gcj02ToWgs84(_ gcjLat: Double, _ gcjLng: Double) -> CLLocationCoordinate2D {
        if outOfChina(gcjLat, gcjLng) {
            return CLLocationCoordinate2D(latitude: gcjLat, longitude: gcjLng)
        }
        var wLat = gcjLat
        var wLng = gcjLng
        for _ in 0..<6 {
            let g = wgs84ToGcj02(wLat, wLng)
            let dLat = g.latitude - gcjLat
            let dLng = g.longitude - gcjLng
            if abs(dLat) < 1e-8 && abs(dLng) < 1e-8 { break }
            wLat -= dLat
            wLng -= dLng
        }
        return CLLocationCoordinate2D(latitude: wLat, longitude: wLng)
    }
}