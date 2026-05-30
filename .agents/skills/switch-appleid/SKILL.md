---
name: switch-appleid
version: 1.1.0
description: "在 macOS App Store 一键切换不同区域的 Apple ID（当前内置支持国区 / 美区 / 土区，新增区域只需加一行映射）。当用户说「切换 Apple ID」「切到美区」「换成国区账号」「App Store 换区」「switch apple id」「在 Mac 上换苹果账号」时触发。涵盖把多区凭据存入钥匙串、用 AppleScript 驱动 App Store 退出并重新登录。"
---

# Switch Apple ID Region (macOS App Store)

帮助用户在 macOS App Store 里一键切换不同区域的 Apple ID。整体流程：

1. **凭据存到钥匙串** —— 每个区域一条 generic password 条目
2. **运行 AppleScript** —— 从钥匙串读账号密码，驱动 App Store 退出登录并重新登录

资产文件：`switch-appleid-zone.applescript`（同目录下的模板脚本）。

---

## Step 1：把账号存入钥匙串

约定 service 名为 `AppleId_<REGION>`。脚本内置三个映射：`AppleId_CN`、`AppleId_US`、`AppleId_TU`（即 `cn` / `us` / `tu` 参数）。新增区域时先在脚本 `keychainItemFor` 里加一行 `if region is "xx" then return "AppleId_XX"`，再在钥匙串里加同名条目。

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

新增区域只需在脚本 `keychainItemFor` 里加一行 `if` 映射，并在钥匙串里加对应条目。

脚本会：
1. 把 App Store 提到最前，并清理上一次可能残留的登录对话框
2. 打开"商店 / Store"菜单：已登录 → 先退出登录，然后点登录
3. 通过 **accessibility 元素**（而非屏幕坐标）定位登录对话框：先填 Apple ID 回车，待密码框出现后再填密码回车
4. 等对话框关闭以确认登录成功（放宽到约 20 秒，容忍慢网络验证）
5. **如果开启了两步验证，需要用户手动输入验证码**

> 提交用「在字段内按回车」而非点 Sign In 按钮——实测点按钮会提交未 commit 的旧值导致卡住，回车会先 commit 再提交，可靠得多。

---

## 注意事项

- **本地化**：脚本读取 `AppleLocale`（失败回退 `user locale`）选择菜单文案。简体中文 (`zh*`) 用「商店 / 登录 / 退出登录」，**其他语言（含英文及未识别语言）默认按英文界面**处理，并对带省略号的菜单项做了兜底。如需精确支持其他语言，在 `localeMenuNames` 里加一个分支即可。
- **辅助功能权限**：第一次运行时 macOS 会要求触发 osascript 的终端（Terminal / iTerm 等）获得 Accessibility 权限。系统设置 → 隐私与安全性 → 辅助功能 里勾上。
- **UI 元素定位**：脚本不写死字段序号，而是动态遍历登录 sheet 的 `text fields`，按 `description`（`secure text field` = 密码框）区分账号框与密码框，对 App Store 版本升级更鲁棒。若大版本改版后仍失效，可用 `tell process "App Store" to get entire contents` 重新核对结构。
- **iCloud 不受影响**：只切换 App Store 的 Apple ID，不会动 iCloud 登录。

---

## 排错

| 现象 | 原因 | 处理 |
|---|---|---|
| `在钥匙串里找不到名称为「AppleId_XX」的条目…` | 该 service 不存在，或缺账号/密码 | 重跑 Step 1 的 `security add-generic-password`（注意带上 `-a` 和 `-w`）|
| `找不到「Store / 商店」菜单` | App Store 没完全启动 / 不在前台 | 加大脚本开头的 `delay`，或先手动打开 App Store |
| `提交账号后未出现密码框（账号可能有误）` | Apple ID 输错，或网络慢没返回 | 核对钥匙串里的账号；网络慢时重跑一次 |
| `⚠ 对话框仍未关闭` | 慢网络下 Apple 服务器验证超时 | **通常登录其实已成功**，看左下角账户名确认；或重跑一次 |
| 一直卡在登录弹窗 | 触发了二步验证 | 手动输入设备验证码，脚本结束 |
| 频繁弹钥匙串授权 | 没勾 Always Allow | 弹框时选 "Always Allow"，或在 Keychain Access 里改 Access Control |

---

## 文件清单

- `SKILL.md` —— 本说明
- `switch-appleid-zone.applescript` —— AppleScript 模板，开箱即用，无需修改即可读钥匙串
