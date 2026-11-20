# Gemini（Google AI）用量设置

> English version below ·《[English](#gemini-google-ai-usage-setup)》

Notch 的「用量」功能可以显示你在 **Antigravity** 里的 Gemini 额度，和 Claude、Codex、Grok 并排。
和其它几家不同，Google 不允许在内嵌浏览器里登录，所以 Notch **不自己登录 Google**——它通过运行
**Antigravity 自带的命令行工具**（`agy`）来读取用量。因此设置几乎是零配置：只要你装了 Antigravity
并登录过，打开开关就行。

## 前提条件

- 一台登录了 Google 账号、能用 Antigravity 的 Mac。
- 本机装有 **Antigravity**，并且**已经登录**（命令行 `agy` 或 Antigravity 应用都行）。
  Notch 读到的就是它的登录状态，所以 Antigravity 这边必须是已登录的。
- Antigravity 命令行二进制在默认位置：`~/.local/bin/agy`。

## 设置步骤（一站式）

1. **安装并登录 Antigravity。** 用你平时的方式：打开 Antigravity 应用登录，或在终端里跑 `agy`
   按提示登录。
2. **在 Notch 里打开 Gemini。** 「设置… → 用量」里，打开 **显示 Gemini** 开关。

完成。Gemini 的额度会出现在「用量」标签页和主页用量模块里，和其它几家一样，大约每 5 分钟刷新一次，
分 **5 小时** 和 **每周** 两个窗口。

> 不用在 Notch 里登录，也不用填任何密钥或令牌，**也不会弹钥匙串授权**——Notch 只是运行你本机已有的
> Antigravity 命令行工具，由它自己读自己的登录。

## 工作原理

Notch 运行一条 Antigravity 自带的只读命令：

```
agy -p /usage --output-format json
```

- 这是 Antigravity 的内置命令，**本地**就能答复（和 Claude Code 的 `/usage` 一样）：**不开启会话、
  不消耗任何额度、瞬时返回**（返回里 `num_turns` 和 `total_tokens` 都是 0）。
- 命令由 agy 自己执行，**认证完全由它自己处理**——所以 Notch **不碰钥匙串、不碰任何令牌或密钥**，
  也不需要内置任何 Google 凭据。
- Notch 只解析它返回的 JSON，取出 “Gemini Models” 那一组的 5 小时和每周额度（忽略 Claude/GPT 那组），
  换算成“已用百分比 + 重置时间”。付费计划单独的 Argon 额度，用到了会作为每周额度的一个分项显示。

## 隐私与安全

- Notch **不碰钥匙串、不碰令牌、不存任何 Google 凭据**，源码里也没有。
- Notch 只运行你本机已有的 `agy`，**不修改** Antigravity 的任何状态，也**不消耗**你的额度。
- 命令的输出用完即弃，不落盘。

## 常见问题

- **Gemini 显示“未登录”或“加载失败”。** 多半是 Antigravity 这边没登录或登录过期了。打开 Antigravity
  应用、或在终端跑 `agy` 重新登录，然后在 Notch 的「用量」页点重试（或等下次自动刷新）。设置页里的
  **打开 Antigravity** 按钮也能直接跳过去。
- **找不到 Antigravity。** 确认 `~/.local/bin/agy` 存在。如果你只装了 Antigravity 应用、没装命令行，
  用 Antigravity 的 `install` 之类的方式把 `agy` 装到默认位置。
- **这条命令的输出没有公开文档**，Antigravity 更新后随时可能改动；真出问题时 Notch 只会显示读取失败，
  不会影响其它几家。

---

# Gemini (Google AI) usage setup

Notch's **Usage** feature can show your Gemini quota in **Antigravity**, next to Claude, Codex, and
Grok. Unlike the others, Google does not allow sign-in inside an embedded browser, so Notch **does
not sign you in to Google** — it reads your usage by running **Antigravity's own command-line tool**
(`agy`). Setup is therefore almost zero-config: if Antigravity is installed and signed in, just turn
Gemini on.

## Requirements

- A Mac with a Google account that can use Antigravity.
- **Antigravity** installed and **signed in** (via the `agy` CLI or the Antigravity app). Notch reads
  its sign-in state, so Antigravity must be signed in.
- The Antigravity CLI binary at its default location: `~/.local/bin/agy`.

## Setup (one-stop)

1. **Install and sign in to Antigravity** the way you normally would — open the app and sign in, or run
   `agy` in a terminal and follow the prompts.
2. **Turn on Gemini in Notch.** In **Settings… → Usage**, switch on **Show Gemini**.

That's it. Gemini's quota appears in the **Usage** tab and the Home usage module like the others,
refreshing about every 5 minutes, with a **5-hour** and a **weekly** window.

> You don't sign in inside Notch, you never type a secret or token, and **there is no keychain prompt** —
> Notch just runs the Antigravity CLI you already have, and that tool reads its own sign-in.

## How it works

Notch runs one read-only built-in Antigravity command:

```
agy -p /usage --output-format json
```

- It is a built-in command the tool answers **locally** (like Claude Code's `/usage`): it **starts no
  session, spends no quota, and returns at once** (`num_turns` and `total_tokens` are both 0 in the
  result).
- `agy` runs it and **handles all authentication itself** — so Notch **touches no keychain and no token
  or secret**, and needs no Google credentials of its own.
- Notch only parses the returned JSON, taking the 5-hour and weekly limits from the "Gemini Models"
  group (ignoring the Claude/GPT group) and turning them into "percent used + reset time". The separate
  Argon bucket on paid plans is shown as a part of the weekly window when any is used.

## Privacy and safety

- Notch **touches no keychain, no token, and stores no Google credential**, and none is in its source.
- Notch only runs the `agy` you already have; it **changes nothing** in Antigravity and **spends none**
  of your quota.
- The command's output is used and discarded, never written to disk.

## Troubleshooting

- **Gemini shows "Not signed in" or "Failed to load".** Antigravity is probably signed out or its
  sign-in expired. Sign in again in the Antigravity app or by running `agy`, then press Retry in Notch's
  Usage pane (or wait for the next refresh). The **Open Antigravity** button in Settings takes you there.
- **Antigravity isn't found.** Make sure `~/.local/bin/agy` exists. If you installed only the Antigravity
  app and not the CLI, use Antigravity's own `install` step to put `agy` in the default location.
- **This command's output is undocumented** and may change when Antigravity updates; if that happens
  Notch just shows a failed read for Gemini and the other providers are unaffected.
