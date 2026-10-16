//
//  AlarmEngine.swift
//  到站提醒 (ArrAvid) — iOS
//
//  对应 Android 版：AlarmEngine.java + AlarmActivity.java（全屏页在 UI/AlarmView.swift）
//
//  到站时的强提醒：响铃 + 震动 + 循环语音播报 + 高优先级通知 +（App 在前台时）全屏提醒页。
//
//  ⚠️ 平台差异：
//   * Android 可以用 STREAM_ALARM 在静音下大声响铃，还能后台拉起全屏 Activity；
//     iOS 两者都受限：
//       - 声音走「播放」音频通道，静音键拨到静音时不会响；要静音也响必须申请
//         Critical Alerts entitlement（需 Apple 单独审批，见 docs/CRITICAL_ALERTS.md）。
//       - 后台不能拉起界面，只能发通知；用户点开后 App 内才会显示全屏提醒页。
//   * 因此这里用「后台音频持续播放」保住进程存活（Info.plist 里已声明 audio 后台模式），
//     这样响铃 / 语音循环能在锁屏、后台状态下坚持到用户处理为止。
//

import Foundation
import AVFoundation
import AudioToolbox
import UIKit

final class AlarmEngine: NSObject, ObservableObject {

    static let shared = AlarmEngine()

    /// 语音/响铃循环间隔
    private let repeatInterval: TimeInterval = 20
    /// 最多循环这么多轮就自动停止（9 × 20 秒 = 3 分钟），避免无人处理时无限响铃
    private let maxRepeats = 9

    @Published private(set) var active = false
    @Published private(set) var current: Route?

    private var player: AVAudioPlayer?
    private var synthesizer: AVSpeechSynthesizer?
    private var repeatTimer: Timer?
    private var vibrateTimer: Timer?
    private var repeatCount = 0
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        super.init()
    }

    // MARK: - 开始

    func start(route: Route) {
        stop(notify: false)

        active = true
        current = route
        repeatCount = 0

        configureAudioSession()
        startSound()
        startVibration()
        speak(route.announce)
        NotificationService.shared.postArrival(route: route)

        // 后台存活：音频已经在放，这里再申请一小段后台任务，确保第一轮语音能播完
        beginBackgroundTask()

        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: repeatInterval, repeats: true) { [weak self] _ in
            guard let self = self, self.active, let r = self.current else { return }
            self.speak(r.announce)
            NotificationService.shared.postArrival(route: r)
            self.repeatCount += 1
            if self.repeatCount >= self.maxRepeats {
                TrackLog.log("提醒", "已循环 \(self.maxRepeats) 轮无人处理，自动停止响铃")
                self.stop()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer

        Diag.event("alarm_ui", "提醒已触发：\(route.stationName)；App 状态=\(UIApplication.shared.applicationState == .active ? "前台" : "后台/锁屏")"
            + "，音频通道=播放，通知=时效性")
        TrackLog.log("提醒", "开始强提醒：\(route.announce)")
    }

    /// 用户点开通知，但引擎已停止（比如自动停了）时，把提醒页重新拉起来
    func presentFromNotification(routeId: Int64) {
        let route = RouteStore.shared.find(routeId) ?? {
            var r = Route()
            r.destName = "提醒站"
            return r
        }()
        start(route: route)
    }

    // MARK: - 停止

    func stop(notify: Bool = true) {
        if notify {
            TrackLog.log("提醒", "停止强提醒")
        }
        active = false
        current = nil

        repeatTimer?.invalidate()
        repeatTimer = nil
        vibrateTimer?.invalidate()
        vibrateTimer = nil

        player?.stop()
        player = nil

        synthesizer?.stopSpeaking(at: .immediate)
        synthesizer = nil

        NotificationService.shared.removeArrival()
        NotificationService.shared.cancelSnooze()
        endBackgroundTask()
    }

    /// 「再过 2 分钟提醒我」：先停掉当前响铃，再安排 2 分钟后的本地通知重新提醒。
    func snooze(routeId: Int64?, after seconds: TimeInterval) {
        // 先取好要高亮的线路（stop() 会清掉 current）
        let route = routeId.flatMap { RouteStore.shared.find($0) } ?? current ?? {
            var r = Route()
            r.destName = "提醒站"
            return r
        }()
        stop(notify: true)
        NotificationService.shared.scheduleSnooze(route: route, after: seconds)
        TrackLog.log("提醒", "已安排 \(Int(seconds / 60)) 分钟后再提醒：\(route.stationName)")
    }

    // MARK: - 声音

    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            // playback 通道：锁屏/后台能持续播放，且不受静音开关影响的只有 critical 提醒；
            // 这里用 playback + duckOthers，其它 App 的声音会被压低而不是中断。
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true, options: [])
        } catch {
            TrackLog.log("提醒", "音频会话配置失败：\(error.localizedDescription)")
        }
    }

    private func startSound() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "wav") else {
            TrackLog.log("提醒", "找不到内置铃声 alarm.wav，退回系统提示音")
            AudioServicesPlaySystemSound(1005)
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1          // 无限循环，直到用户点「我已下车」
            p.volume = 1.0
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            TrackLog.log("提醒", "铃声播放失败：\(error.localizedDescription)")
            AudioServicesPlaySystemSound(1005)
        }
    }

    private func startVibration() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        let timer = Timer(timeInterval: 1.6, repeats: true) { _ in
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
        RunLoop.main.add(timer, forMode: .common)
        vibrateTimer = timer
    }

    // MARK: - 语音播报

    private func speak(_ text: String) {
        let synth = synthesizer ?? AVSpeechSynthesizer()
        synthesizer = synth
        let utterance = AVSpeechUtterance(string: text)
        // 优先中文语音
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            ?? AVSpeechSynthesisVoice(language: "zh-Hans-CN")
        utterance.rate = 0.48
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0
        synth.speak(utterance)
    }

    // MARK: - 后台存活

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "arravid-alarm") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
}