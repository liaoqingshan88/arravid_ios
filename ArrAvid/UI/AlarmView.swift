//
//  AlarmView.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：AlarmActivity.java
//  到站全屏提醒页：我已下车 / 再过 2 分钟提醒我。
//
//  ⚠️ 平台差异：iOS 后台无法拉起界面，这个页面只有 App 在前台（或用户点开通知）时出现。
//  锁屏/后台状态下靠「循环响铃 + 震动 + 语音 + 时效性通知」提醒。
//

import SwiftUI

struct AlarmView: View {

    let route: Route
    @EnvironmentObject var alarm: AlarmEngine
    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        ZStack {
            Color(red: 1.0, green: 0.95, blue: 0.88).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                Text("到站提醒")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color(red: 0.85, green: 0.26, blue: 0.08))

                Text(route.announce)
                    .font(.system(size: 34, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color(red: 0.10, green: 0.14, blue: 0.49))
                    .padding(.horizontal, 20)

                Text("即将到达 \(route.stationName)")
                    .font(.title3)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    alarm.stop()
                    MonitorEngine.shared.stopMonitoring(reason: "用户已下车")
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("我已下车（停止提醒）")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.85, green: 0.26, blue: 0.08))

                Button {
                    alarm.snooze(routeId: route.id, after: 120)
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Text("再过 2 分钟提醒我")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)

                Spacer().frame(height: 20)
            }
            .padding(24)
        }
        .onDisappear {
            // 用户直接下滑关闭时，也要把提醒停掉，避免一直响
            if alarm.active {
                alarm.stop()
            }
        }
    }
}