//
//  TrackLogView.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：MainActivity.showTrackLog()
//

import SwiftUI

struct TrackLogView: View {

    @Environment(\.presentationMode) private var presentationMode
    @State private var lines: [String] = []

    var body: some View {
        NavigationView {
            Group {
                if lines.isEmpty {
                    Text("（暂无记录，先点主页的『立即开始监控』跑一次）")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(12)
                    }
                }
            }
            .navigationBarTitle("监控日志（最近 150 条）", displayMode: .inline)
            .navigationBarItems(
                leading: Button("关闭") { presentationMode.wrappedValue.dismiss() },
                trailing: Button("清空") {
                    TrackLog.clear()
                    lines = []
                })
            .onAppear { lines = Array(TrackLog.read(150)) }
        }
        .navigationViewStyle(.stack)
    }
}