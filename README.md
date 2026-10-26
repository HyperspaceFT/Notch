# Notch

**简体中文** | [English](README.en.md)

> 一个运行在 macOS 刘海屏上的「灵动岛」。

![macOS 26+](https://img.shields.io/badge/macOS-26%2B-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![Heavy Vibe Coded](https://img.shields.io/badge/Heavy%20Vibe%20Coded-🤖-ff69b4)
![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue)

> [!WARNING]
> **本项目是 Heavy Vibe Coded 的。**
>
> 仓库中几乎所有代码、脚本和文档都由 AI（[Claude Code](https://claude.com/claude-code)）编写，作者只负责提需求、看效果、做决定，**没有逐行审阅代码**。
> 它能跑、看起来也不错，但请把它当作一个个人玩具项目：可能有 bug，可能某天在新系统上失灵，使用风险自负。欢迎提 Issue。

---

## 它能做什么

鼠标移到刘海上，刘海会弹一下、变大一圈；点一下展开成一个黑色的小面板，移开后又缩回去，和硬件刘海融为一体。拖着文件靠近刘海，它会直接展开到「文件」页。

| 功能 | 说明 |
|---|---|
| 🎵 正在播放 | 有歌曲在播放时，刘海两侧显示封面和随节拍摆动的波纹，点波纹暂停 / 继续，暂停 3 秒后收起。展开后的「正在播放」标签页里有大封面、可以拖动的进度条和切歌按钮。默认只读取「音乐」和 Spotify（需要「自动化」权限）；打开「读取任意 App 的正在播放」后也能读取浏览器等任意 App，**有一定风险，见下方说明**。波纹的节拍是按歌曲生成的，不是真实的音频频谱 |
| 🔔 通知 | 其他 App 弹出通知横幅时，刘海两侧显示 App 图标、标题和正文第一行，点一下看全文；最近 30 条列在「通知」标签页里，只保存在内存中。系统没有读取通知的公开接口，Notch 借「辅助功能」权限读取屏幕上的横幅，所以只能看到真正弹出来的横幅（提醒样式为「无」或被专注模式拦下的看不到），系统更新后也可能失效。可以选择「隐藏系统通知横幅」，只在灵动岛里显示；万一之后系统横幅一直不出现，在「终端」里运行 `killall NotificationCenter` 即可恢复 |
| 🏠 主页 | 展开后的首页：时间、天气、日历、笔记、提醒事项和用量模块排成一行，最多四个。在「设置…」的「主页」页里选择模块、拖动排序、调整长度；岛的宽度随模块数增加，最宽 840 点 |
| 📅 日历 | 按天列出最近几天的日程（默认 3 天，可设 1–14 天），点一下展开看全文，可以拷贝。日程来自「日历」App（需要「日历」权限）或 Google、Outlook 等的 ICS 订阅链接（只读，链接只保存在本机）。日程快开始时刘海两侧会提醒（提前多久可设，默认 5 分钟），有 Zoom、Google Meet、Teams、腾讯会议、飞书、钉钉或 Webex 链接时可以直接加入会议 |
| ⏱️ 计时器 | 在刘海右侧的计时器标签页里用刻度尺选时长（0–120 分钟），在触控板上两指滑动时每过一分钟轻震一下；点主页上的时间模块也能打开。计时期间，岛的边缘亮起一圈橙色光带，长短表示剩余时间，时间到了响铃提醒。同一时间只有一个计时器，只保存在内存里 |
| 📊 用量限额 | Claude、Codex（ChatGPT 订阅）和 Grok 订阅的 5 小时、每周等用量限额，显示在「用量」标签页和主页模块里。在「设置…」的「用量」页打开要显示的 AI，并在 Notch 自己的登录窗口里登录一次（不读取浏览器里的登录；无法用 Google 登录，请用邮箱验证码或密码）。只在展开面板或打开「用量」设置页时读取，每个 AI 5 分钟最多一次。用的是网页版的内部接口，没有公开文档，随时可能失效 |
| 🌤️ 天气 | 当前天气、今天的最高 / 最低气温和接下来几个小时的预报；一天分成三个时段，各自显示今日、未来几小时或明日天气，在「设置…」的「天气」页里调整，也可以在那里立即刷新定位和天气。需要「定位」权限（只用大致位置），数据来自 [Open-Meteo](https://open-meteo.com) |
| 📝 笔记 | 随手写笔记，有自己的标签页，也可以放到主页上。直接在岛上打字，不会切走当前的 App；边写边保存，只存在这台 Mac 上 |
| ✅ 提醒事项 | 主页模块：「提醒事项」App 里还没完成的待办，可以新建、勾掉和删除，改动通过 iCloud 同步到其他设备。需要「提醒事项」权限 |
| 📂 文件 | 左边是隔空投送区，把文件拖进去即可发送；右边是文件暂存区，文件可以再拖出去或拷贝粘贴，支持多选。可以打开「粘贴后自动删除文件」（只从暂存区移除，不删原文件） |
| 🎧 AirPods | 连上时刘海两侧显示耳机和电量；连接期间多出一个标签页，显示左右耳和充电盒的电量，调节音量和降噪模式。需要「蓝牙」权限；降噪模式用的是系统未公开的接口，系统更新后可能失效 |
| 🔋 电池 | 插拔电源时提示，电量降到 20%、10% 和 5% 时各提醒一次；展开后可以看剩余时间和电池健康 |
| 🔊 音量与亮度 | 按音量键或亮度键时，用刘海两侧的提示代替系统自带的；按住 Option + Shift 可以更细地调节。需要「辅助功能」权限，不想用可以在设置里关掉 |

> [!WARNING]
> **「读取任意 App 的正在播放」是一项有一定风险的功能，默认关闭。** macOS 15.4 起，只有 Apple 签名的程序才能读取系统「正在播放」的信息。打开开关后，Notch 会让系统自带的 `/usr/bin/perl` 加载一个第三方预编译库 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)（BSD 3-Clause，原样取自 boring.notch，保存在 `Vendor/MediaRemoteAdapter/`），让不属于 Apple 的代码以 Apple 程序的身份运行，绕开 macOS 有意设置的隐私限制。除了它公开的源码，Notch 无法核实这个二进制库实际做了什么，任何一次 macOS 更新也都可能让它失效。虽说市面上绝大多数的 Notch 均采用了此方法，但是这并不妨碍该方法是一种较为危险的实现。不打开它，「正在播放」仍然可以显示「音乐」和 Spotify；打开后如果这个组件在你的 Mac 上无法运行，也会自动退回到这种方式。

打开设置：鼠标移到刘海上，等它变大一圈后点右键，选 **设置…**。界面支持简体中文和英文（默认跟随系统语言），设置里还可以打开「登录时打开」和「光影与色彩」（卡片按内容着色，展开后岛的边缘跟着太阳和月亮的位置变化）。「通用」页最下面的「调试模式」用来检查界面，**如果你不知道自己在做什么，请不要打开**。

## 系统要求

- **macOS 26 或更新版本**（界面用到了 macOS 26 的 Liquid Glass 效果）
- **带刘海的 MacBook**（Apple Silicon）。没有刘海的屏幕上会显示一个模拟刘海。

## 安装

到 [Releases](https://github.com/HyperspaceFT/Notch/releases) 页面下载最新的 `Notch-x.y.z.zip`，然后：

1. 解压，把 `Notch.app` 拖进「应用程序」文件夹；
2. 双击打开。因为 App 没有经过苹果公证，系统会提示「无法验证开发者」，点「完成」；
3. 打开 **系统设置 → 隐私与安全性**，拉到最下面，点 **「仍要打开」** 并输入密码。

也可以在终端里执行下面这条命令，去掉下载隔离标记后直接打开：

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

第一次使用时，系统会请求这些权限，按需允许即可：

- **辅助功能**：接管音量键和亮度键，在灵动岛里显示通知（第一次打开时请求，需要到系统设置里打开 Notch）；
- **蓝牙**：显示 AirPods 的连接和电量（第一次打开时请求）；
- **定位**、**日历**：当地天气和「日历」App 里的日程（第一次展开刘海时请求；只用订阅链接的话日历权限可以不给）；
- **提醒事项**：第一次在提醒事项卡片上点「允许」时请求；
- **自动化**：读取和控制「音乐」、Spotify（第一次读取它们时请求）。

更新到新版本后，如果音量和亮度提示又变回了系统自带的样式，或者通知不再出现在灵动岛里，到 **系统设置 → 隐私与安全性 → 辅助功能** 里选中 Notch，点「−」删掉，再重新打开 Notch 允许一次。App 没有经过苹果的正式签名，签名变了的新版本会被系统当成另一个 App。

退出：鼠标移到刘海上，等它变大一圈后点右键，选 **退出**。

## 从源码构建

**不需要安装 Xcode**，只要有命令行工具（Command Line Tools）即可：

```bash
xcode-select --install
git clone https://github.com/HyperspaceFT/Notch.git
cd Notch
make cert   # 只需一次，见下面的「本地签名证书」
make run
```

构建好的 App 在 `build/Notch.app`。常用命令：

| 命令 | 作用 |
|---|---|
| `make build` / `make debug` | 构建 Release / Debug 版，输出到 `build/Notch.app` |
| `make run` | 构建并（重新）启动 App |
| `make test` | 运行单元测试 |
| `make dist` | 打包成 `build/dist/Notch-<版本号>.zip` |
| `make clean` | 删除所有构建产物 |
| `make cert` | 创建本地签名证书 |
| `make icon` | 改完 `Resources/AppIcon.svg` 后重新生成 `Resources/AppIcon.icns` |

调试时可以让刘海停在某个状态，加上 `-NotchDebugSnapshot` 还能把界面导出成图片（图里没有 Liquid Glass 效果）：

```bash
open build/Notch.app --args -NotchDebugState expanded   # 也可以是 activity / collapsed
open build/Notch.app --args -NotchDebugState expanded -NotchDebugSnapshot /tmp/notch.png
```

### 本地签名证书

没有证书时，每次构建都是临时签名（ad-hoc），签名每次都不一样，系统会把新构建当成另一个 App，「辅助功能」权限就失效了。`make cert` 在「登录」钥匙串里创建一个名为「Notch Local Signing」的自签名证书（有效期 10 年，`codesign` 可以直接使用），之后的构建都用它签名，权限会一直保留。它只用来在本机给 Notch 签名，「钥匙串访问」把它标成「不受信任」不影响使用。

换成证书签名后，需要最后一次到 **系统设置 → 隐私与安全性 → 辅助功能** 里把旧的 Notch 删掉再重新允许。不想用了，就在「钥匙串访问」里删掉这个证书，之后的构建会回到临时签名。

## 项目结构

项目是一个 Swift Package，按「外壳 + 可插拔功能」拆成几个模块，依赖方向是单向的：

```
Sources/
├── NotchKit/        # 功能模块的「接口」：NotchFeature 协议、NotchActivity、NotchContext、主页模块、右键菜单项、界面语言
├── NotchUI/         # 设计系统：刘海形状、主题、动画、Liquid Glass 按钮等通用组件
├── NotchShell/      # 外壳：窗口、屏幕/刘海定位、鼠标悬停、状态机、根视图
├── Features/        # 各个功能，每个功能一个文件夹，只依赖 NotchKit + NotchUI
└── NotchApp/        # 可执行入口、设置窗口；FeatureCatalog.swift 是启用功能的唯一清单
Tests/               # 单元测试
Resources/           # Info.plist 模板、签名权限、App 图标（AppIcon.svg 是源文件）
scripts/             # 构建、运行、打包脚本
Vendor/              # 随 App 附带的第三方预编译组件（mediaremote-adapter，BSD 3-Clause）
VERSION              # 版本号
```

```
NotchApp ──▶ NotchShell ──▶ NotchKit
    │            └────────▶ NotchUI
    └──▶ Features/* ──▶ NotchKit + NotchUI
```

刘海有三种状态：**collapsed**（和硬件刘海一样大，看不出来）、**activity**（某个功能发出「实时活动」时向两侧延伸，比如充电提示）和 **expanded**（点击后展开，顶部是各功能的标签页）。鼠标停在刘海上时它会放大一圈，这时点击展开，右键弹出菜单。

## 添加新功能

1. 在 `Sources/Features/<名字>/` 下新建文件夹，写一个遵循 `NotchFeature` 的类；
2. 在 `Package.swift` 的 `featureNames` 里加上 `"<名字>"`，会自动生成 `<名字>Feature` 模块；
3. 在 `Sources/NotchApp/FeatureCatalog.swift` 里 `import <名字>Feature` 并把实例加进列表，列表顺序就是标签页的顺序。

功能可以选择实现这些：

- `tabPlacement`（标签页放在刘海左侧还是右侧）、`isTabAvailable`（暂时隐藏标签页）、`isTabActive`（让收起的右侧按钮显示它）；
- 通过 `NotchContext` 的 `present(_:)` / `dismiss(activityID:)` 发出和收回实时活动，`requestExpand(detail:)` 让岛单独展开成某个视图，参照 `Sources/Features/Battery`；
- `makeHomeModules()` 为主页提供模块，`expandedWidth` 让标签页更宽（520–880 点），参照 `Sources/Features/Weather`；
- `menuItems` 往右键菜单里加菜单项，`debugItems` 往「调试」页里加操作（只显示示例内容，不改动用户的数据，也不控制系统或其他 App），参照 `Sources/Features/Clock`。

界面文字用 `localized(en:zh:)` 同时写出英文和中文，并在视图绘制时读取，这样切换语言后会立即刷新。

## 路线图

- [ ] 🔄 自动更新

已经完成的功能见上面的 [它能做什么](#它能做什么)。

## 致谢

做这个项目时参考了这些优秀的开源项目的思路：

- [boring.notch](https://github.com/TheBoredTeam/boring.notch)
- [NotchDrop](https://github.com/Lakr233/NotchDrop)
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)

「用量」里 Claude、Codex 和 Grok 的图标来自 [Lobe Icons](https://github.com/lobehub/lobe-icons)（MIT 许可证）；这些标志分别属于 Anthropic、OpenAI 和 xAI，只用来标明对应的服务。

## 许可证

Copyright (C) 2026 [HyperspaceFT](https://github.com/HyperspaceFT)

本项目以 [GNU 通用公共许可证第 3 版（GPL-3.0）](LICENSE) 发布，你也可以选择该许可证的任何更新版本。

简单来说：

- ✅ 可以自由使用、复制、修改、分发，也可以发布修改后的版本；
- 📌 分发时必须保留原作者的版权声明，并附上本许可证；
- 📌 发布修改版时，必须注明改了什么，并且修改版**同样要以 GPL-3.0 开源、公开完整源码**，不能闭源。

以上只是通俗说明，具体条款以 [LICENSE](LICENSE) 原文为准。
