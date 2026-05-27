---
name: switch-appleid
version: 1.0.0
description: "在 macOS App Store 一键切换不同区域的 Apple ID（当前内置支持国区 / 美区 / 土区，新增区域只需加一行映射）。当用户说「切换 Apple ID」「切到美区」「换成国区账号」「App Store 换区」「switch apple id」「在 Mac 上换苹果账号」时触发。涵盖把多区凭据存入钥匙串、用 AppleScript 驱动 App Store 退出并重新登录。"
---

# Switch Apple ID Region (macOS App Store)

帮助用户在 macOS App Store 里一键切换不同区域的 Apple ID。整体流程：

1. **凭据存到钥匙串** —— 每个区域一条 generic password 条目
2. **运行 AppleScript** —— 从钥匙串读账号密码，驱动 App Store 退出登录并重新登录

资产文件：`switch-appleid-zone.applescript`（同目录下的模板脚本）。

---

## Step 1：把账号存入钥匙串

约定 service 名为 `AppleId_<REGION>`。脚本内置三个映射：`AppleId_CN`、`AppleId_US`、`AppleId_TU`（即 `cn` / `us` / `tu` 参数）。新增区域时先在脚本里加 `else if` 分支，再在钥匙串里加同名条目。

为每个区域执行一次（`-U` 表示若已存在则更新）：

```bash
security add-generic-password -a "<your-apple-id@example.com>" -s "AppleId_CN" -w "<password>" -U
security add-generic-password -a "<your-apple-id@example.com>" -s "AppleId_US" -w "<password>" -U
security add-generic-password -a "<your-apple-id@example.com>" -s "AppleId_TU" -w "<password>" -U
```

> 含特殊字符（双引号、反斜杠、`$`、`!` 等）的密码用单引号包裹，钥匙串里存的是原文，AppleScript 不需要再转义。

验证：

```bash
security find-generic-password -s "AppleId_CN" | awk -F'"' '/acct/{print $4}'   # 看账号
security find-generic-password -s "AppleId_CN" -w                                # 看密码
```

第一次读取时系统会弹钥匙串授权框，可以选 "Always Allow"，之后 osascript 静默读取。

---

## Step 2：运行 AppleScript

脚本接受一个参数 `cn` / `us` / `tu`，自动映射到 `AppleId_CN/US/TU`。直接对 skill 目录下的脚本文件 `osascript` 即可，无需移动或安装：

```bash
osascript /path/to/switch-appleid-zone.applescript cn
```

> Agent 调用时会自己解析到 skill 目录的绝对路径。手动跑时，把 `/path/to/` 换成 skill 实际所在目录（plugin 安装通常落在 `~/.claude/plugins/...` 下）。

新增区域只需在脚本里加一个 `else if` 分支，并在钥匙串里加对应条目。

脚本会：
1. 退出并重新打开 App Store（避免菜单灰着没法点）
2. 打开"商店 / Store"菜单
3. 已登录 → 先退出再点登录；未登录 → 直接点登录
4. 填入账号回车，再填密码回车
5. **如果开启了两步验证，需要用户手动输入验证码**

---

## 注意事项

- **本地化**：脚本根据 `user locale` 选择菜单文案，仅支持 **简体中文 (`zh_CN`)** 和 **英文 (`en_*`)** 两种。其他系统语言下会直接报错退出（避免按错误的菜单名乱点）。如需支持其他语言，在脚本本地化分支里加一个 `else if` 即可。
- **辅助功能权限**：第一次运行时 macOS 会要求触发 osascript 的终端（Terminal / iTerm 等）获得 Accessibility 权限。系统设置 → 隐私与安全性 → 辅助功能 里勾上。
- **UI 元素位置**：脚本里 `text field 1/2 of sheet 1 of sheet 1 of window 1` 是按 App Store 当前版本写死的，macOS 大版本升级后可能需要重新对位（用 Accessibility Inspector 或 `tell process "App Store" to get entire contents`）。
- **iCloud 不受影响**：只切换 App Store 的 Apple ID，不会动 iCloud 登录。

---

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| `不支持的系统语言：xx_YY` | 当前系统语言不是 `zh_CN` 也不是 `en_*` | 切到简体中文或英文重试；或在脚本里加对应语言分支 |
| `读取钥匙串失败 (AppleId_XX)` | 该 service 不存在 | 重跑 Step 1 的 `security add-generic-password` |
| 账号是空字符串、密码却拿到了 | 加条目时漏了 `-a` 参数 | 用 `-U` 重加一次，带上 `-a` |
| 菜单项灰着点不动 | App Store 没完全启动 / 网络慢 | 加大脚本里的 `delay` |
| 一直卡在登录弹窗 | 触发了二步验证 | 手动输入设备验证码，脚本结束 |
| 频繁弹钥匙串授权 | 没勾 Always Allow | 弹框时选 "Always Allow"，或在 Keychain Access 里改 Access Control |

---

## 文件清单

- `SKILL.md` —— 本说明
- `switch-appleid-zone.applescript` —— AppleScript 模板，开箱即用，无需修改即可读钥匙串
