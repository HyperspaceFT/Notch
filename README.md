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

鼠标移到刘海上，刘海会弹一下、变大一圈（用 Force Touch 触控板时还会轻轻震一下）；点一下，它才「长大」成一个黑色的小面板；移开后又缩回去，和硬件刘海融为一体。拖着文件移到刘海上，它会直接展开到「文件」页。

目前内置的功能：

| 功能 | 说明 |
|---|---|
| 🎧 AirPods | 连上 AirPods 时，刘海左侧短暂显示耳机图标、右侧显示电量。连接期间，展开面板里刘海左侧、紧挨着刘海的位置会多出一个耳机标签页，可以看到左右耳和充电盒的电量，调节耳机音量和降噪模式（降噪 / 通透 / 自适应，视型号而定）。声音切换回 Mac 自带扬声器时（比如 AirPods 断开），刘海两侧也会短暂显示电脑图标和当前音量，这部分不需要蓝牙权限。系统自带的连接提示无法隐藏，仍会出现。需要「蓝牙」权限；降噪模式用的是系统未公开的接口，系统更新后可能失效 |
| 🏠 主页 | 展开后的主页，由几个模块从左到右排成一行，目前有时间和天气两个模块。时间最窄时是一个正方形，显示时:分和日期，加宽后显示到秒；天气最窄占整行的三分之一，上面是当前天气、下面是未来三小时，加宽后左边是当前天气、右边随宽度显示更多小时。在「设置…」的「主页」页里可以选择放哪些模块（最多四个）、调整顺序和长度 |
| 🌤️ 天气 | 主页上的天气模块：当前气温、天气和今天的最高 / 最低气温，以及接下来几个小时的预报，温度单位跟随系统设置。一天分成三个时段，每个时段可以显示今日天气、未来几小时或明日天气（默认 5–10 点今日、10–19 点未来几小时、19 点到次日 5 点明日），在「设置…」的「天气」页里拖动 24 小时圆环调整。需要「定位」权限，只用大致位置；数据来自 [Open-Meteo](https://open-meteo.com)，请求里只带精确到小数点后两位的经纬度；顺便取回当地的日出日落时间，用来点亮岛的边缘（见下文「光影与色彩」）。只在展开面板时更新，15 分钟最多一次 |
| 📂 文件 | 左边是隔空投送区，把文件拖进去即可用 AirDrop 发送；右边是文件暂存区，拖进来的文件可以再拖出去或右键「拷贝」后粘贴。打开「粘贴后自动删除文件」后，文件被拖出或粘贴后会自动从暂存区移除（不会删除原文件） |
| 🔋 电池 | 插上电源时，刘海左侧短暂弹出绿色的充电电池图标、右侧显示电量百分比，拔掉电源时也会提示；展开后刘海右侧的电池图标随电量变化，点开可以看到剩余时间和电池健康（最大容量、循环次数） |
| 🔊 音量与亮度 | 按音量键或亮度键时，用刘海两侧的提示代替系统自带的：左边是图标，右边的圆环显示当前音量或亮度；按住 Option + Shift 可以更细地调节。需要「辅助功能」权限（见下面的安装步骤），不想用可以在「设置…」的「灵动岛」页里关掉 |

界面支持简体中文和英文，默认跟随系统语言；也可以在右键菜单的「设置…」里切换，切换后立即生效。「设置…」里还可以打开「登录时打开」，让 Notch 开机自动启动。

「设置…」的「通用」页里有「光影与色彩」开关（默认打开）：卡片带有自上而下的光照和细描边，天气、充电、电量低、隔空投送等卡片会按内容着色，大号数字带一点光泽。展开后，岛的边缘会跟着天空变化：白天，一团柔和的光晕标出太阳此刻在天上的位置——从左侧升起，正午在底部中间，从右侧落下——越接近日出日落越橙；日落后换成月光，从右侧爬上顶部，由右往左横过（半夜有一部分藏在刘海后面），日出时从左侧下来，一天正好绕岛一圈；月亮越圆，月光越亮、越大。日出日落时间来自天气模块，会保存下来，天气暂时没有更新时也能沿用；从没取到过时，按早上 6 点日出、晚上 6 点日落来算。关掉开关就回到朴素的灰色卡片。

更多功能见下面的 [路线图](#路线图)。

## 系统要求

- **macOS 26 或更新版本**（界面用到了 macOS 26 的 Liquid Glass 效果）
- **带刘海的 MacBook**（Apple Silicon）。没有刘海的屏幕上会显示一个模拟刘海。

## 安装（给朋友用）

到 [Releases](https://github.com/HyperspaceFT/Notch/releases) 页面下载最新的 `Notch-x.y.z.zip`，然后：

1. 解压，把 `Notch.app` 拖进「应用程序」文件夹；
2. 双击打开。因为 App 没有经过苹果公证，系统会拦截并提示「无法验证开发者」，点「完成」；
3. 打开 **系统设置 → 隐私与安全性**，拉到最下面，点 **「仍要打开」** 并输入密码。之后就能正常使用了；
4. 第一次打开时系统会请求「辅助功能」权限（用来接管音量键和亮度键），点「打开系统设置」，在列表里打开 Notch；还会请求「蓝牙」权限（用来显示 AirPods 的连接和电量），点「允许」。第一次展开刘海时会请求「定位」权限（用来显示当地天气），点「允许」。

也可以在终端里执行下面这条命令，去掉下载隔离标记后直接打开：

```bash
xattr -dr com.apple.quarantine /Applications/Notch.app
```

更新到新版本后，如果音量和亮度提示又变回了系统自带的样式，到 **系统设置 → 隐私与安全性 → 辅助功能** 里选中 Notch，点「−」删掉，再重新打开 Notch 允许一次。App 没有经过苹果的正式签名，签名变了的新版本会被系统当成另一个 App。

退出方法：鼠标移到刘海上，等它变大一圈后点右键，选 **退出**（英文界面下是 Quit）。

## 从源码构建

**不需要安装 Xcode**，只要有命令行工具（Command Line Tools）即可：

```bash
xcode-select --install
```

然后：

```bash
git clone https://github.com/HyperspaceFT/Notch.git
cd Notch
make run
```

构建好的 App 在 `build/Notch.app`，可以直接双击运行。建议先执行一次 `make cert` 创建本地签名证书，否则每次重新构建后「辅助功能」权限都要重新给，见下面的 [本地签名证书](#本地签名证书)。

常用命令：

| 命令 | 作用 |
|---|---|
| `make build` | 构建 Release 版，输出到 `build/Notch.app` |
| `make debug` | 构建 Debug 版 |
| `make run` | 构建并（重新）启动 App |
| `make test` | 运行单元测试 |
| `make dist` | 打包成 `build/dist/Notch-<版本号>.zip`，方便发给别人 |
| `make clean` | 删除所有构建产物 |
| `make cert` | 创建本地签名证书，让重新构建后「辅助功能」权限不失效 |

调试时可以强制刘海停在某个状态，方便看效果；加上 `-NotchDebugSnapshot` 还能把界面导出成图片（不需要屏幕录制权限，但导出的图里没有 Liquid Glass 效果）：

```bash
open build/Notch.app --args -NotchDebugState expanded   # 也可以是 activity / collapsed
open build/Notch.app --args -NotchDebugState expanded -NotchDebugSnapshot /tmp/notch.png
```

### 本地签名证书

默认情况下，构建出来的 App 只有临时签名（ad-hoc），每次构建的签名都不一样。系统会把每次构建出来的 App 当成一个新 App，之前在「辅助功能」里给的权限就失效了，得删掉再重新允许。

在钥匙串里建一个本地签名证书，之后的构建都用它签名，签名就不会再变，权限也会一直保留。只需要执行一次：

```bash
make cert
```

它会：

1. 生成一个名为「Notch Local Signing」的自签名代码签名证书，有效期 10 年；
2. 把证书和私钥导入「登录」钥匙串，并允许 `codesign` 直接使用，构建时不会弹窗询问。

之后 `make build`、`make debug`、`make run` 都会自动用这个证书签名，构建输出里会显示 `==> Signing (Notch Local Signing)`；钥匙串里找不到它时会退回临时签名，显示 `==> Signing (ad-hoc; …)`。

这个证书只用来在本机给 Notch 签名。它是自签名的，「钥匙串访问」会把它标成「此证书不受信任」，这不影响签名，不需要改信任设置。

换成证书签名后第一次运行时，需要最后一次到 **系统设置 → 隐私与安全性 → 辅助功能** 里把旧的 Notch 删掉（−）再重新允许；以后再重新构建就不用管了。

不想用了：打开「钥匙串访问」，在「登录」钥匙串的「我的证书」里删掉「Notch Local Signing」，之后的构建会回到临时签名。

## 项目结构

项目是一个 Swift Package，按「外壳 + 可插拔功能」拆成几个模块，依赖方向是单向的：

```
Sources/
├── NotchKit/        # 功能模块的「接口」：NotchFeature 协议、NotchActivity、NotchContext、主页模块、界面语言
├── NotchUI/         # 设计系统：刘海形状、主题、动画、Liquid Glass 按钮等通用组件
├── NotchShell/      # 外壳：窗口、屏幕/刘海定位、鼠标悬停、状态机、根视图
├── Features/        # 各个功能，每个功能一个文件夹，只依赖 NotchKit + NotchUI
│   ├── Battery/
│   ├── Files/
│   ├── Home/
│   ├── SystemHUD/
│   └── Weather/
└── NotchApp/        # 可执行入口、设置窗口；FeatureCatalog.swift 是启用功能的唯一清单
Tests/               # 单元测试
Resources/Info.plist # App 信息模板
scripts/             # 构建、运行、打包脚本
VERSION              # 版本号
```

```
NotchApp ──▶ NotchShell ──▶ NotchKit
    │            └────────▶ NotchUI
    └──▶ Features/* ──▶ NotchKit + NotchUI
```

刘海有三种状态：

- **collapsed**：和硬件刘海一样大，看不出来；
- **activity**：某个功能发出「实时活动」时，刘海向两侧延伸，左右显示内容（比如充电提示）；
- **expanded**：点击刘海后展开，顶部是各功能的标签页（主页、文件、AirPods（连接时才出现）在刘海左侧，电池在右侧），下面是当前功能的内容。

鼠标停在 collapsed 或 activity 状态的刘海上时，刘海会带一点回弹地放大一圈（hovered），这时点击展开，右键弹出「设置…」/「退出」菜单。

## 添加新功能

新增一个功能只需要三步：

1. 在 `Sources/Features/<名字>/` 下新建文件夹，写一个遵循 `NotchFeature` 的类；
2. 在 `Package.swift` 的 `featureNames` 数组里加上 `"<名字>"`，会自动生成 `<名字>Feature` 模块并接进 App；
3. 在 `Sources/NotchApp/FeatureCatalog.swift` 里 `import <名字>Feature`，并把实例加进列表。列表顺序就是展开面板里标签页的顺序；标签页默认在刘海左侧，把 `tabPlacement` 设为 `.trailing` 可以放到右侧；`isTabAvailable` 返回 `false` 时标签页暂时隐藏（比如 AirPods 没连接时）。

功能可以通过 `NotchContext` 和外壳交互，比如 `present(_:)` 发出一个实时活动、`dismiss(activityID:)` 收回它。具体写法可以参照 `Sources/Features/Battery`。

功能还可以实现 `makeHomeModules()`，为主页提供模块（`NotchHomeModule`），并用 `HomeModuleSizing` 写明它的最小 / 最大长度，或者长度固定；用户就能在「设置…」的「主页」页里把它放到主页上。具体写法可以参照 `Sources/Features/Weather`。

界面文字用 `localized(en:zh:)` 同时写出英文和中文，并在视图绘制时读取（比如 `title` 写成计算属性），这样切换语言后会立即刷新。

## 路线图

- [ ] 🎵 正在播放 / 媒体控制
- [ ] 📅 日历与提醒事项
- [x] 📂 文件中转架（拖文件到刘海暂存）
- [x] 🔊 替换系统音量 / 亮度提示
- [x] 🎧 AirPods 连接提示与耳机设置（电量、音量、降噪模式）
- [x] 🌤️ 天气，以及可自定义的主页布局（选择模块、排序、调整长度）和天气时段
- [x] ⚙️ 设置面板（目前有开机自启、光影与色彩、音量/亮度提示开关、主页布局、天气时段和语言选项）
- [x] 🚀 开机自启
- [ ] 🔄 自动更新

## 致谢

做这个项目时参考了这些优秀的开源项目的思路：

- [boring.notch](https://github.com/TheBoredTeam/boring.notch)
- [NotchDrop](https://github.com/Lakr233/NotchDrop)
- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)

## 许可证

Copyright (C) 2026 [HyperspaceFT](https://github.com/HyperspaceFT)

本项目以 [GNU 通用公共许可证第 3 版（GPL-3.0）](LICENSE) 发布，你也可以选择该许可证的任何更新版本。

简单来说：

- ✅ 可以自由使用、复制、修改、分发，也可以发布修改后的版本；
- 📌 分发时必须保留原作者的版权声明，并附上本许可证；
- 📌 发布修改版时，必须注明改了什么，并且修改版**同样要以 GPL-3.0 开源、公开完整源码**，不能闭源。

以上只是通俗说明，具体条款以 [LICENSE](LICENSE) 原文为准。
