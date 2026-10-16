# Critical Alerts（静音下也响铃）

## 为什么需要它

iOS 默认走「播放」音频通道，**静音开关拨到静音时不会响**。对到站提醒这种"必须吵醒人"的场景来说是个硬伤。

Apple 提供了一个特殊权限 `com.apple.developer.usernotifications.critical-alerts`：拿到后，通知可以用 `interruptionLevel = .critical`，绕过静音开关和勿扰模式强制发声（音量还会被系统自动拉高）。

## 怎么申请

1. 登录 [Apple Developer](https://developer.apple.com/account) → Certificates, Identifiers & Profiles → Identifiers → 找到你的 App ID → Capabilities → 勾选 **Critical Alerts** → Save。
2. Apple 会要求你填写用途说明（例如："本应用是通勤到站提醒工具，需要在用户手机静音或勿扰模式下仍能发出声音警报以避免错过下车"），通常 1-3 个工作日审批。
3. 批准后重新生成 Provisioning Profile，更新 Xcode 的签名配置。
4. 在 `ArrAvid/ArrAvid.entitlements` 里取消注释：
   ```xml
   <key>com.apple.developer.usernotifications.critical-alerts</key>
   <true/>
   ```
5. 把 `NotificationService.swift` 里 `postArrival` 和 `scheduleSnooze` 的 `content.interruptionLevel = .timeSensitive` 改成 `.critical`。
6. 重新构建安装即可。

## 限制

- 只有付费开发者账号（$99/年）能申请；免费 Apple ID 不行。
- Apple 审核严格，纯个人项目也可能被拒；建议用真实使用场景写说明。
- 即便拿到 entitlement，App Store 上架还需要额外说明；侧载自用不受影响。

## 没拿到怎么办

- 把手机静音开关拨回来；或者
- 在「设置 → 声音与触感 → 铃声和提醒」里把提醒音量调大；
- 或者依赖震动 + 语音播报（这两个不受静音开关影响）。
