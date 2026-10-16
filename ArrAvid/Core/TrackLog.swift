//
//  TrackLog.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：TrackLog.java
//  监控诊断日志：真机实测后如果"没响"，靠它回答"为什么不响"。
//

import Foundation

enum TrackLog {

    private static let fileName = "monitor.log"
    private static let maxLines = 400
    private static let maxBytes = 96 * 1024
    private static let lock = NSLock()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "MM-dd HH:mm:ss"
        return f
    }()

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    static func log(_ tag: String, _ msg: String) {
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int, size > maxBytes {
            let keep = read(maxLines / 2)
            write(keep)
        }
        let line = "\(formatter.string(from: Date())) [\(tag)] \(msg)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    static func read(_ maxLines: Int = 400) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        if lines.count > maxLines {
            lines = Array(lines.suffix(maxLines))
        }
        return lines
    }

    static func clear() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
    }

    private static func write(_ lines: [String]) {
        let text = lines.joined(separator: "\n") + "\n"
        try? text.data(using: .utf8)?.write(to: fileURL, options: .atomic)
    }
}