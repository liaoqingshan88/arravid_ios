# 到站提醒（ArrAvid）iOS 版

每天坐同一条线路、到同一个站的**到站下车提醒** App。配好一次，App 会在你大致到站时间附近自动开始定位监控，进入终点站附近立刻**响铃 + 震动 + 语音报站**。

本目录是从 Android 版 `/home/admin/arravid` 移植过来的 iOS 原生工程（SwiftUI + CoreLocation），可以直接在 Mac 上用 Xcode 打开运行，也可以在 GitHub Actions 云构建出 ipa，再在 Windows 上用 Sideloadly 装到 iPhone。

---

## 一、与 Android 版的差异（必读）

iOS 的后台限制比 Android 严得多，下面几点是移植时绕不过去的：

| 能力 | Android 原版 | iOS 实现 |
| --- | --- | --- |
| **到点自动开 GPS** | AlarmManager.setExactAndAllowWhileIdle 精确唤醒 | ❌ iOS 不允许后台定时启动；改用「地理围栏 + 显著位置变化」常驻，跨基站或进出提醒站围栏时系统唤醒 App，再升级为连续 GPS |
| **锁屏/息屏弹全屏页** | 全屏 Intent / SYSTEM_ALERT_WINDOW | ❌ iOS 后台不能拉起界面；只能发高优先级通知，用户点开后才显示全屏提醒页 |
| **静音下也响铃** | STREAM_ALARM 无视静音键 | ⚠️ 默认走「播放」通道，静音开关拨到静音时不会响；要静音也响必须申请 Critical Alerts entitlement（需 Apple 单独审批，见 [docs/CRITICAL_ALERTS.md](docs/CRITICAL_ALERTS.md)） |
| **开机重排闹钟** | BootReceiver | ✅ iOS 没有开机广播；改成每次 App 启动 / 进后台时重排围栏 |
| **地图选点** | 高德栅格瓦片 WebView | ✅ 直接用系统 MapKit，体验更好；坐标系按 GCJ-02 处理（国区苹果地图底图就是火星坐标） |
| **自升级** | 下载 APK 调起安装 | ❌ iOS 禁止应用自升级；升级到新版本需要重新用 Sideloadly / AltStore 覆盖安装 |
| **电池优化白名单** | REQUEST_IGNORE_BATTERY_OPTIMIZATIONS | ✅ iOS 上叫「后台 App 刷新」+「始终允许定位」；设置里都打开即可 |

**省电目标仍然保留**：平时只跑系统的「地理围栏 + 显著位置变化」（几乎不额外耗电），只有进了提醒站附近或到了监控窗口才升级为连续 GPS。

---

## 二、工程结构

```
arravid_ios/
├── ArrAvid.xcodeproj/          ← Xcode 工程文件（脚本生成，可直接打开）
│   ├── project.pbxproj
│   └── xcshareddata/xcschemes/ArrAvid.xcscheme   ← 共享 Scheme，CI 也用这个
├── ArrAvid/
│   ├── Info.plist              ← 权限说明 + UIBackgroundModes: location/audio
│   ├── ArrAvid.entitlements    ← 预留 Critical Alerts（默认空）
│   ├── Core/                   ← Route / Store / Geo / WindowScheduler / TrackLog / Config
│   ├── Location/               ← MonitorEngine（核心监控逻辑）/ LocationOnce
│   ├── Alarm/                  ← AlarmEngine / NotificationService
│   ├── Net/                    ← StationSearch / UpdateChecker / Diag
│   ├── UI/                     ← SwiftUI 视图 + AppState + AppDelegate
│   └── Resources/              ← Assets.xcassets / alarm.wav / PrivacyInfo.xcprivacy
├── scripts/
│   ├── gen_xcodeproj.py        ← pbxproj 生成器（加新 Swift 文件后重跑）
│   ├── make_assets.py          ← 图标 + 铃声生成器（纯标准库）
│   └── build_unsigned_ipa.sh   ← Mac 本地一键打未签名 ipa
├── .github/workflows/ios-build.yml   ← GitHub Actions 云构建流水线
├── project.yml                 ← XcodeGen 备选方案（可选）
└── docs/                       ← Critical Alerts 等补充文档
```

---

## 三、怎么装到 iPhone

### 路线 A：有 Mac（推荐）

1. 把 `/home/admin/arravid_ios` 拷到 Mac（U盘 / scp / git clone）。
2. 双击 `ArrAvid.xcodeproj` 用 Xcode 打开。
3. 左上角选择你的真机 → 在 Signing & Capabilities 里勾选 Automatically manage signing，Team 选你的 Apple ID（免费账号也行）。
4. 点 ▶ 直接装到手机。免费 Apple ID 7 天过期，到期再点一次 ▶ 重装；付费开发者账号 1 年有效。

> 第一次装会提示"不受信任的开发者"：iPhone → 设置 → 通用 → VPN与设备管理 → 找到你的 Apple ID → 信任。

### 路线 B：没有 Mac，用 GitHub Actions 云构建 + Windows Sideloadly

1. 在 GitHub 新建一个仓库（公开仓库免费不限时；私有仓库免费额度 2000 分钟/月，macOS 按 10 倍扣 ≈ 200 分钟/月，够用）。
2. 把 `/home/admin/arravid_ios` 里的*全部内容*推到仓库根目录（不是放到子目录）。
3. Actions → 「iOS 云构建」→ Run workflow；或推送 `v1.4.3` 标签自动触发。
4. 构建完成后下载 Artifact：`ArrAvid-unsigned.ipa`。
5. Windows 上装 [Sideloadly](https://sideloadly.io)，拖入 ipa，登录你的免费 Apple ID，点 Start 装到手机。
6. 7 天后证书过期，重复步骤 3-5 重装一次（线路配置保存在手机上，不会丢）。

> 想彻底免重装：花 $99/年买 Apple Developer Program，在 CI 里配证书和描述文件就能打出带签名的 ipa，有效期 1 年。详见 [docs/CRITICAL_ALERTS.md](docs/CRITICAL_ALERTS.md)。

### 路线 C：Codemagic / MacinCloud

- Codemagic 免费档每月 500 分钟 macOS，自带 GUI 式配置，对新手更友好。
- MacinCloud 付费 ~$30/月租一台云端 Mac，可以远程桌面操作 Xcode。

---

## 四、首次使用

1. 打开 App → 依次授权「始终允许定位」「精确位置」「通知」。
2. 点右上角 ＋ 新建线路：填提醒站名称，用「当前位置 / 地图选点 / 按名称查」三种方式之一确定车站位置。
3. 填每天大致几点到站（例如 08:50），选好监控日期。
4. App 会在你接近提醒站时自动响铃 + 震动 + 循环语音播报「XX 到了，请下车」。
5. 点「我已下车」停止；也可以点「再过 2 分钟提醒我」。
6. 连续几次到站后，App 会自动学习你的实际到站时间并微调监控窗口。

---

## 五、已知限制

- **静音开关**：默认走「播放」通道，静音时不会响。想要静音也响，需要申请 Critical Alerts entitlement（见 [docs/CRITICAL_ALERTS.md](docs/CRITICAL_ALERTS.md)）。
- **后台被杀**：如果系统长时间不用后询问"是否继续允许后台定位"，一定要选「始终允许」；否则下次通勤可能漏提醒。
- **地铁/隧道**：GPS 信号弱时主要靠网络定位，精度差；建议把「提前量」设大一点（10~15 分钟）。
- **直线距离判定**：和 Android 版一样用的是 GPS 半径，不是公交线路距离；提醒站附近平行马路多时可把半径调小。
- **自升级**：iOS 不支持；有新版本就重新走一遍安装流程（配置不丢）。

---

## 六、开发备忘

- 加新 Swift 文件后跑 `python3 scripts/gen_xcodeproj.py` 重新生成 pbxproj。
- 改图标/铃声跑 `python3 scripts/make_assets.py`。
- bundle id = `com.arravid.reminder`，版本号 = 1.4.3（build 22），与 Android 版对齐。
- 服务端接口沿用 `http://www.yanhexing.com:9000`（明文），已在 Info.plist 里放开 ATS。
- 高德 Web Key 内置在 `Core/Config.swift`，与 Android 版一致。

---

## 七、许可

个人自用工具，源码仅供学习与自用部署。