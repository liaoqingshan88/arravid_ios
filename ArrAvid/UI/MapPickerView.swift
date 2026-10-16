//
//  MapPickerView.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：MapPickerActivity.java（那边是「高德栅格瓦片 + 拖动十字准星」的 WebView 方案）
//  iOS 直接用系统 MapKit，体验好得多：拖地图 → 十字圈对准车站 → 点「就用这个位置」。
//
//  ⚠️ 坐标系说明（很重要）：
//  中国大陆的 Apple 地图底图是 GCJ-02（火星坐标），MapKit 在国区内返回的地图坐标同样是 GCJ-02，
//  而手机 GPS 给的是 WGS-84。所以这里和 Android 版一样，选点后要 GCJ-02 → WGS-84 转换再入库。
//  如果以后发现选点普遍偏移约 500 米，把 mapCoordinatesAreGCJ02 改成 false 即可（说明系统已给 WGS-84）。
//

import SwiftUI
import MapKit
import CoreLocation

struct MapPickerView: View {

    /// 中国大陆范围内 MapKit 的坐标是否按 GCJ-02 处理
    private static let mapCoordinatesAreGCJ02 = true

    let initialLat: Double
    let initialLng: Double
    let onPick: (CLLocationCoordinate2D) -> Void   // 回调给的是 WGS-84

    @Environment(\.presentationMode) private var presentationMode

    @State private var region: MKCoordinateRegion
    @State private var myLocation: CLLocationCoordinate2D?
    @State private var locating = false

    init(initialLat: Double,
         initialLng: Double,
         onPick: @escaping (CLLocationCoordinate2D) -> Void) {
        self.initialLat = initialLat
        self.initialLng = initialLng
        self.onPick = onPick

        let hasExisting = initialLat != 0 && initialLng != 0
        let last = RouteStore.shared.lastPick()
        var start = CLLocationCoordinate2D(latitude: 39.909, longitude: 116.397)  // 默认北京
        if hasExisting {
            start = MapPickerView.toMapCoordinate(CLLocationCoordinate2D(latitude: initialLat,
                                                                        longitude: initialLng))
        } else if let l = last {
            start = MapPickerView.toMapCoordinate(l)
        }
        _region = State(initialValue: MKCoordinateRegion(center: start,
                                                         span: MKCoordinateSpan(latitudeDelta: 0.01,
                                                                                longitudeDelta: 0.01)))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ZStack {
                    Map(coordinateRegion: $region, showsUserLocation: true)
                        .ignoresSafeArea(edges: .horizontal)

                    // 十字准星
                    ZStack {
                        Circle()
                            .stroke(Color(red: 0.85, green: 0.26, blue: 0.08), lineWidth: 3)
                            .frame(width: 26, height: 26)
                            .shadow(radius: 2)
                        Circle()
                            .fill(Color(red: 0.85, green: 0.26, blue: 0.08))
                            .frame(width: 4, height: 4)
                    }
                    .allowsHitTesting(false)

                    VStack {
                        Spacer()
                        Text("拖动地图，把圆圈对准要提醒的车站")
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.black.opacity(0.66))
                            .foregroundColor(.white)
                            .cornerRadius(14)
                            .padding(.bottom, 12)
                    }
                    .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(coordinateText)
                        .font(.caption)

                    HStack(spacing: 10) {
                        Button("取消") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button {
                            locateMe()
                        } label: {
                            Image(systemName: "location.circle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(locating)

                        Button("就用这个位置") {
                            confirm()
                        }
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(14)
            }
            .navigationBarTitle("地图选点", displayMode: .inline)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            // 没有历史坐标时自动定位到当前位置
            if initialLat == 0 && initialLng == 0 && RouteStore.shared.lastPick() == nil {
                locateMe()
            }
        }
    }

    private var coordinateText: String {
        let wgs = MapPickerView.toWgs84(region.center)
        return String(format: "当前坐标（GPS）：%.6f, %.6f　对准车站后点右下按钮",
                      wgs.latitude, wgs.longitude)
    }

    private func confirm() {
        let wgs = MapPickerView.toWgs84(region.center)
        RouteStore.shared.setLastPick(wgs)
        onPick(wgs)
        presentationMode.wrappedValue.dismiss()
    }

    private func locateMe() {
        locating = true
        LocationOnce.requestOnce { location in
            locating = false
            guard let loc = location else { return }
            myLocation = loc.coordinate
            withAnimation {
                region.center = MapPickerView.toMapCoordinate(loc.coordinate)
                region.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            }
        }
    }

    // MARK: - 坐标转换

    private static func toMapCoordinate(_ wgs: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard mapCoordinatesAreGCJ02 else { return wgs }
        return Geo.wgs84ToGcj02(wgs.latitude, wgs.longitude)
    }

    private static func toWgs84(_ mapCoord: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard mapCoordinatesAreGCJ02 else { return mapCoord }
        return Geo.gcj02ToWgs84(mapCoord.latitude, mapCoord.longitude)
    }
}