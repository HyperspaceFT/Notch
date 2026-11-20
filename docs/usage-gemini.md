# Gemini（Google AI）用量设置

> English version below ·《[English](#gemini-google-ai-usage-setup)》

Notch 的「用量」功能可以显示你在 **Antigravity** 里的 Gemini 额度，和 Claude、Codex、Grok 并排。
和其它几家不同，Google 不允许在内嵌浏览器里登录，所以 Notch **不自己登录 Google**——它直接复用
**Antigravity 应用已经在这台 Mac 上保存好的登录**。因此设置几乎是零配置：只要你装了
Antigravity 并登录过，打开开关就行。

## 前提条件

- 一台登录了 Google 账号、能用 Antigravity 的 Mac。
- 本机装有 **Antigravity**，并且**已经登录**（命令行 `agy` 或 Antigravity 应用都行）。
  Notch 读取的就是它保存的登录，所以 Antigravity 这边必须是已登录状态。
- Antigravity 命令行二进制在默认位置：`~/.local/bin/agy`。

## 设置步骤（一站式）

1. **安装并登录 Antigravity。** 用你平时的方式：打开 Antigravity 应用登录，或在终端里跑 `agy`
   按提示登录。登录成功后，Antigravity 会把令牌存进本机的登录钥匙串。
2. **在 Notch 里打开 Gemini。** 「设置… → 用量」里，打开 **显示 Gemini** 开关。
3. **首次授权钥匙串。** 第一次读取时，macOS 会弹窗问是否允许 Notch 访问钥匙串里的
   `gemini / antigravity` 这条。点 **始终允许**（点一次，以后不再问）。

完成。Gemini 的额度会出现在「用量」标签页和主页用量模块里，和其它几家一样，大约每 5 分钟刷新一次。

> 不用在 Notch 里登录，也不用手动填任何密钥或令牌——这些 Notch 都从 Antigravity 本机的安装里自动取。

## 工作原理

- **令牌**：Notch 从登录钥匙串里读取 Antigravity 保存的 Google 令牌（服务 `gemini`、账号
  `antigravity`）。
- **刷新**：Google 的访问令牌一小时就过期。过期后，Notch 用钥匙串里的 refresh token 向
  Google 的令牌接口换一个新的，**只存在内存里**，绝不写回钥匙串或磁盘。
- **刷新所需的 OAuth 客户端**：这一步需要 Antigravity 自己的 OAuth 客户端（client id 和
  secret）。Notch **不把它写死在代码里**，而是在需要时从本机的 Antigravity 二进制
  （`~/.local/bin/agy`）里现找，逐个试到 Google 接受的那一对，然后记在内存里。所以无论是令牌还是
  客户端，**没有任何 Google 凭据被存进 Notch 或它的源码**。（安装类应用的 client secret 本来就
  内嵌在人人可下载的程序里，不算机密，只是用来向 Google 标明"这是 Antigravity 这个客户端"。）
- **额度**：Notch 用这个令牌去请求 Antigravity 读额度用的同一个内部接口
  （`cloudcode-pa.googleapis.com`），把 Gemini 各模型共用的那个额度池换算成"已用百分比 + 重置时间"。

## 隐私与安全

- Notch **绝不修改** Antigravity 的登录，也**绝不写**钥匙串——只读取。
- 刷新得到的令牌只在内存里，Notch 关掉就没了。
- 任何密钥、令牌都**不会**进入 Notch 的源码、配置文件，也不会发给 Google 以外的任何地方。
- 请求只发往 `oauth2.googleapis.com`（刷新令牌）和 `cloudcode-pa.googleapis.com`（读额度）。

## 常见问题

- **Gemini 显示"未登录"。** 多半是 Antigravity 这边没登录或登录过期了。打开 Antigravity 应用、
  或在终端跑 `agy` 重新登录，然后在 Notch 的「用量」页点重试（或等下次自动刷新）。设置页里的
  **打开 Antigravity** 按钮也能直接跳过去。
- **一直弹钥匙串授权。** 第一次请点 **始终允许**，否则每次读取都会再问。
- **找不到 Antigravity。** 确认 `~/.local/bin/agy` 存在。如果你只装了 Antigravity 应用、没装命令行，
  用 Antigravity 的 `install` 之类的方式把 `agy` 装到默认位置。
- **这些接口没有公开文档**，Google 随时可能改动；真出问题时 Notch 只会显示读取失败，不会影响其它几家。

---

# Gemini (Google AI) usage setup

Notch's **Usage** feature can show your Gemini quota in **Antigravity**, next to Claude, Codex, and
Grok. Unlike the others, Google does not allow sign-in inside an embedded browser, so Notch **does
not sign you in to Google** — it reuses the sign-in the **Antigravity app already keeps on this Mac**.
Setup is therefore almost zero-config: if Antigravity is installed and signed in, just turn Gemini on.

## Requirements

- A Mac with a Google account that can use Antigravity.
- **Antigravity** installed and **signed in** (via the `agy` CLI or the Antigravity app). Notch reads
  the sign-in it stores, so Antigravity must be signed in.
- The Antigravity CLI binary at its default location: `~/.local/bin/agy`.

## Setup (one-stop)

1. **Install and sign in to Antigravity** the way you normally would — open the app and sign in, or run
   `agy` in a terminal and follow the prompts. Once signed in, Antigravity stores its token in your
   login keychain.
2. **Turn on Gemini in Notch.** In **Settings… → Usage**, switch on **Show Gemini**.
3. **Allow keychain access once.** On the first read, macOS asks whether Notch may access the
   `gemini / antigravity` keychain item. Click **Always Allow** (once; it won't ask again).

That's it. Gemini's quota appears in the **Usage** tab and the Home usage module like the others,
refreshing about every 5 minutes.

> You don't sign in inside Notch, and you never type a secret or token — Notch takes all of that from
> Antigravity's own install on this Mac.

## How it works

- **Token:** Notch reads the Google token Antigravity stored in the login keychain (service `gemini`,
  account `antigravity`).
- **Refresh:** Google access tokens expire after an hour. When one does, Notch exchanges the keychain's
  refresh token for a new access token at Google's token endpoint and keeps it **in memory only** —
  never written back to the keychain or to disk.
- **The OAuth client for refresh:** that exchange needs Antigravity's own OAuth client (id and secret).
  Notch does **not** bake it into its code; it discovers it at run time from the Antigravity binary
  (`~/.local/bin/agy`), trying the pairs until Google accepts one, then keeps it in memory. So no Google
  credential — the token or the client — is ever stored in Notch or its source. (An installed-app client
  secret is not confidential; it ships inside every copy of the app and only names the Antigravity
  client to Google.)
- **Quota:** Notch uses that token against the same internal endpoint Antigravity reads quota from
  (`cloudcode-pa.googleapis.com`) and turns the pool the Gemini models share into "percent used + reset
  time".

## Privacy and safety

- Notch **never modifies** Antigravity's sign-in and **never writes** the keychain — it only reads.
- The refreshed token lives only in memory and is gone when Notch quits.
- No secret or token ever enters Notch's source or config files, or goes anywhere other than Google.
- Requests go only to `oauth2.googleapis.com` (token refresh) and `cloudcode-pa.googleapis.com` (quota).

## Troubleshooting

- **Gemini shows "Not signed in".** Antigravity is probably signed out or its sign-in expired. Sign in
  again in the Antigravity app or by running `agy`, then press Retry in Notch's Usage pane (or wait for
  the next refresh). The **Open Antigravity** button in Settings takes you there.
- **The keychain prompt keeps appearing.** Click **Always Allow** the first time, or it asks on every read.
- **Antigravity isn't found.** Make sure `~/.local/bin/agy` exists. If you installed only the Antigravity
  app and not the CLI, use Antigravity's own `install` step to put `agy` in the default location.
- **These endpoints are undocumented** and Google may change them at any time; if that happens Notch just
  shows a failed read for Gemini and the other providers are unaffected.
