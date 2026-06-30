# 从一个真实需求出发：用 Agent Skill + AppleScript 一键切换 App Store 区域

> 这是一篇手把手教程。看完你会知道：
> - **Agent Skill** 是什么、为什么它比"复制粘贴提示词"好用
> - **AppleScript** 是什么、它能怎么操控 macOS 上的 GUI 应用
> - 怎么把这两者拼起来，做一个能直接在 Claude Code / Codex 里调用的小工具
>
> 全程以一个真实需求作引子：**在 macOS App Store 一键切换不同区域的 Apple ID**。

## 故事的起点

如果你同时持有几个不同区域的 Apple ID（比如国区下国行 App、美区下某些独占应用、土区充值便宜的订阅），你大概熟悉这套流程：

1. 打开 App Store
2. 菜单 → Store → Sign Out
3. 菜单 → Store → Sign In
4. 弹窗里输账号 → 回车
5. 弹窗里输密码 → 回车
6. 二步验证码（如果开了的话）

一次大约 30 秒，体力活。换三次区一分半钟就没了。

更糟的是：账号密码每次都得现敲，或者在密码管理器里复制 —— 跨应用切到剪贴板、再回到 App Store 粘贴，节奏一旦断了就得从头来。

**这事天生该自动化。**

## 第一种思路：写个 shell 脚本？

shell 擅长拼接命令、处理文本、调用 CLI，但碰到 GUI 就抓瞎 —— App Store 是个 Cocoa 应用，没暴露任何命令行接口。你没法 `appstore signout && appstore signin --account=...` 这么写，因为 Apple 根本没给你这种 API。

你需要的是一种**能模拟用户在 GUI 里点击、键入**的东西。

## 第二种思路：AppleScript

### 它是什么

AppleScript 是苹果在 1993 年就发布的脚本语言，专为**自动化 Mac 应用**而生。它最大的特点是语法接近英文自然语言（有些人觉得这反而读着费劲，见仁见智），并且能直接和大多数 GUI 应用对话。

举个最小例子，打开计算器并算 `2+2`：

```applescript
tell application "Calculator"
    activate
end tell

tell application "System Events"
    tell process "Calculator"
        click button "2" of group 1 of window 1
        click button "+" of group 1 of window 1
        click button "2" of group 1 of window 1
        click button "=" of group 1 of window 1
    end tell
end tell
```

读起来像在跟电脑下命令：「告诉计算器：激活」「告诉系统事件：在计算器的窗口里点这些按钮」。

### 它能干什么

- **驱动几乎所有 macOS GUI 应用**：菜单点击、按钮点击、文本框输入、窗口管理
- **读写文件 / 弹窗交互**
- **通过 `do shell script` 调用任意 shell 命令**（这是个关键能力，我们一会儿用）
- **打包成 `.app` 应用** 或挂到登录项 / 快捷键

### 它的边界

- **只能跑 macOS**（不跨平台）
- **依赖 GUI 元素层级**：你写 `text field 1 of sheet 1 of sheet 1 of window 1`，如果 App 升级改了布局，脚本会失效，得用 Accessibility Inspector 重新定位
- **需要辅助功能权限**：第一次跑会请求授权（系统设置 → 隐私与安全性 → 辅助功能）

### 怎么运行

最简单的方式：

```bash
osascript /path/to/your-script.applescript [参数]
```

也可以双击 `.scpt` 或 `.applescript` 文件用「脚本编辑器」打开运行。

## 串起来：先把脚本写出来

回到 App Store 切区。把流程拆成可自动化的步骤：

| 步骤 | 工具 |
|------|------|
| 1. 从某处读出对应区域的账号 / 密码 | macOS 钥匙串 + `security` 命令 |
| 2. 退出 App Store（避免菜单灰着） | AppleScript `tell application ... quit` |
| 3. 重新打开 App Store | AppleScript `activate application ...` |
| 4. 模拟点击 Store 菜单 → Sign In | AppleScript `click menu item ... of menu bar 1` |
| 5. 在登录弹窗里填账号回车、填密码回车 | AppleScript `set value of text field ...` + `keystroke return` |

### 关键设计：账号密码放哪？

**绝对不能写死在脚本里。** 脚本是要分享、可能要上 GitHub 的，明文密码进 git 历史就完了。

正解：**macOS 钥匙串**（Keychain）。系统级密码管理器，命令行可读可写：

```bash
# 写入一条「服务名 = AppleId_TU」的密码
security add-generic-password \
  -a "your-apple-id@example.com" \
  -s "AppleId_TU" \
  -w "your-password" \
  -U                # -U: 已存在则更新
```

读取（在 AppleScript 里）：

```applescript
do shell script "security find-generic-password -s 'AppleId_TU' -w"
```

这条 shell 命令返回密码原文。第一次读会弹钥匙串授权框 —— 选 **Always Allow** 后从此静默。

### 完整脚本

```applescript
#!/usr/bin/osascript

# Usage: osascript switch-appleid-zone.applescript <cn|us|tu>

on run argv
    # ------------ 解析参数 + 本地化菜单名 ------------
    set zone to item 1 of argv
    set lang to user locale of (get system info)

    # 仅适配简体中文和英文，其它语言主动报错
    if lang is equal to "zh_CN" then
        set signInMenuItem to "登录"
        set signOutMenuItem to "退出登录"
        set menuNameOfStore to "商店"
    else if lang starts with "en" then
        set signInMenuItem to "Sign In"
        set signOutMenuItem to "Sign Out"
        set menuNameOfStore to "Store"
    else
        error "不支持的系统语言：" & lang & "。仅支持 zh_CN / en_*。"
    end if

    # zone → 钥匙串 service 名映射
    if zone is equal to "cn" then
        set theService to "AppleId_CN"
    else if zone is equal to "us" then
        set theService to "AppleId_US"
    else if zone is equal to "tu" then
        set theService to "AppleId_TU"
    else
        error "未知的 zone：" & zone & "，请使用 cn / us / tu"
    end if

    set creds to getKeychainCredentials(theService)
    set account to account of creds
    set pwd to password of creds

    # ------------ 重启 App Store ------------
    tell application "System Events"
        if exists process "App Store" then
            tell application "App Store" to quit
            delay 2
        end if
    end tell

    activate application "App Store"

    tell application "System Events"
        tell process "App Store"
            set frontmost to true
            delay 2

            # ------------ 打开菜单触发登录弹窗 ------------
            click menu bar item menuNameOfStore of menu bar 1
            delay 2

            if exists (menu item signInMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1) then
                # 未登录：直接点 Sign In
                click menu item signInMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1
            else
                # 已登录：先 Sign Out 再 Sign In
                click menu item signOutMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1
                delay 5
                click menu item signInMenuItem of menu 1 of menu bar item menuNameOfStore of menu bar 1
            end if
            delay 2

            # ------------ 填账号 → 回车 → 填密码 → 回车 ------------
            set value of text field 1 of sheet 1 of sheet 1 of window 1 to account
            keystroke return
            delay 2

            # 切到下一步后，账号变成 text field 2，密码是 text field 1（小坑）
            set value of text field 2 of sheet 1 of sheet 1 of window 1 to account
            set value of text field 1 of sheet 1 of sheet 1 of window 1 to pwd
            keystroke return

            # 二步验证由用户手动完成
        end tell
    end tell
end run

on getKeychainCredentials(theService)
    try
        set theAccount to do shell script ¬
            "security find-generic-password -s " & quoted form of theService & ¬
            " | awk -F'\"' '/acct/{print $4}'"
        set thePassword to do shell script ¬
            "security find-generic-password -s " & quoted form of theService & " -w"
        return {account:theAccount, password:thePassword}
    on error errMsg number errNum
        error "读取钥匙串失败 (" & theService & "): " & errMsg number errNum
    end try
end getKeychainCredentials
```

到这一步，已经能用了：

```bash
osascript switch-appleid-zone.applescript tu
```

但还能更进一步 —— 把它变成一个 **AI Agent 能自动调用** 的 skill。

## 进阶：把脚本包装成 Agent Skill

### Agent Skill 是什么

如果你用过 Claude Code、Codex CLI、Cursor 这类 AI Agent，你大概碰到过这种情况：

> 你：「帮我把 App Store 切到土区」
> Agent：「我需要先了解你的环境，可以告诉我……」

每次都得重新解释一遍上下文，烦。

**Skill** 就是为了一次性解决这个问题：你把一段「该怎么做某件事」的指南写成一个文件（`SKILL.md`），放在 Agent 能扫描到的位置。下次你说出对应的触发词，Agent 自动加载这份说明，按里面写的步骤执行 —— 不需要你重新教它。

格式很简单：一个目录 + 一个 `SKILL.md`：

```
switch-appleid/
├── SKILL.md                              # 说明 + 触发条件
└── switch-appleid-zone.applescript       # 资产文件
```

`SKILL.md` 顶部用 YAML frontmatter 声明三件事：

```markdown
---
name: switch-appleid
version: 1.0.0
description: "在 macOS App Store 一键切换不同区域的 Apple ID（当前内置支持国区 / 美区 / 土区）。当用户说「切换 Apple ID」「切到美区」「换成国区账号」「App Store 换区」「switch apple id」时触发……"
---

# Switch Apple ID Region (macOS App Store)

帮助用户在 macOS App Store 里一键切换……（接下来是给 Agent 看的步骤说明）
```

**`description` 是关键字段** —— Agent 用它来决定该不该自动召回你的 skill。所以：

- 列尽可能多的触发词（中英文同义词都要）
- 描述清楚适用场景与不适用场景
- 限制在 1500 字符内（Claude Code 在 1536 字符截断）

### Skill 在 AI 生态里的位置

这是 [Agent Skills 开放标准](https://agentskills.io)（2025 年提出），目前被这些工具支持：

| 工具 | 默认扫描路径 |
|------|------------|
| Claude Code | `~/.claude/skills/`（默认配置下），插件市场（`.claude-plugin/marketplace.json`） |
| Codex CLI | `.agents/skills/`（cwd 向上扫到仓库根） + `~/.agents/skills/`（全局） |
| Cursor / GitHub Copilot / Antigravity 等 | 各家自定路径，但都吃同样的 `SKILL.md` 格式 |

只要 `SKILL.md` 写对，一份文件多家工具通吃。

### 让两家 Agent 都能装

如果你的目标是同时支持 Claude Code 和 Codex CLI，最干净的做法是把 skill 放在 `.agents/skills/<name>/` 下（Codex 默认扫这里），然后在 Claude Code 的 marketplace 清单里**显式引用同一份目录**。

完整仓库结构：

```
liam-skills/
├── .claude-plugin/
│   └── marketplace.json          # Claude Code 插件市场清单
├── .agents/
│   └── skills/
│       └── switch-appleid/
│           ├── SKILL.md
│           └── switch-appleid-zone.applescript
├── README.md
└── LICENSE
```

`marketplace.json`：

```json
{
  "name": "liam-skills",
  "owner": { "name": "Liam", "email": "..." },
  "metadata": { "description": "...", "version": "1.0.0" },
  "plugins": [
    {
      "name": "switch-appleid",
      "description": "macOS App Store 一键切换不同区域 Apple ID...",
      "source": "./",
      "strict": false,
      "skills": ["./.agents/skills/switch-appleid"]
    }
  ]
}
```

几个关键字段：

- `source: "./"` —— 插件源就是仓库根（无需嵌套 `plugins/<name>/` 子目录）
- `strict: false` —— 表示不需要单独的 `plugin.json`，组件直接在 marketplace 条目里声明
- `skills: ["./.agents/skills/switch-appleid"]` —— 显式指向 skill 目录
- 每个 skill 作为一个独立 plugin 条目 —— 这样用户能挑着装，不必整组下载

## 发布到 GitHub + 安装使用

### 推到 GitHub

```bash
gh repo create your-user/liam-skills --public --source=. --remote=origin --description "..." --push
```

### Claude Code 用户安装

```text
/plugin marketplace add your-user/liam-skills        # 注册市场
/plugin install switch-appleid@liam-skills           # 单独装这个 skill
/reload-plugins                                      # 让 Agent 看到
```

之后任何时候你说「切到美区」「换成国区账号」，Claude Code 就会自动加载 SKILL.md，调用 `osascript` 跑脚本。

### Codex CLI 用户安装

Codex 没有「插件市场」概念，但会自动扫描 `.agents/skills/`：

```bash
git clone https://github.com/your-user/liam-skills.git ~/.local/share/liam-skills
mkdir -p ~/.agents/skills
ln -s ~/.local/share/liam-skills/.agents/skills/switch-appleid \
      ~/.agents/skills/switch-appleid
```

一次 `ln -s`，全局可用。

## 真实使用流程

设好钥匙串账号（一次性）：

```bash
security add-generic-password -a "你的国区账号" -s "AppleId_CN" -w "国区密码" -U
security add-generic-password -a "你的美区账号" -s "AppleId_US" -w "美区密码" -U
security add-generic-password -a "你的土区账号" -s "AppleId_TU" -w "土区密码" -U
```

之后任何时候，在 Claude Code / Codex 里：

> 帮我切到土区

Agent 自动调起 skill，几秒内 App Store 完成切换。剩下要做的就是 —— 如果你开了二步验证，从可信设备上拿验证码手敲进去。

## 常见坑位

| 现象 | 原因 | 处理 |
|------|------|------|
| 菜单项灰着点不动 | App Store 启动慢 / 网络慢 | 加大脚本里的 `delay` 数值 |
| 输入框定位失败 | macOS 大版本升级后 App Store UI 改了 | 用 Accessibility Inspector 重新定位 `text field` 层级 |
| 频繁弹钥匙串授权框 | 没勾「Always Allow」 | 弹框时选「Always Allow」，或在 Keychain Access → 这条目 → Access Control 里改 |
| 提示「不支持的系统语言」 | 系统语言不是 zh_CN 或 en_* | 临时切到中英文 / 在脚本里加对应分支 |
| 一直转圈 | 触发了二步验证 | 在可信设备上拿验证码手输 —— 脚本只负责到登录前 |

## 还能怎么扩展

这个范式很容易迁移到别的场景：

- **一键切换 iTunes / Apple Music 的 Apple ID**（同样的菜单点击套路）
- **一键启动一组日常应用 + 摆放窗口**（AppleScript 控制窗口位置）
- **VS Code / Cursor / Xcode 项目切换器**（按项目自动激活对应工作区 + 设置环境变量）
- **Zoom / Teams 自动加入定期会议**（定时触发，自动点击加入按钮）

**关键是：**

1. 你需要的功能在 GUI 应用里能完成
2. 每一步操作都能被「点击 / 键入 / 菜单选择」描述
3. 凭据 / 私密信息走钥匙串，不进脚本

只要这三点成立，AppleScript + Skill 的组合就是低门槛的解决方案。

## 完整代码与可装版本

本文中所有代码 + 可一键 `/plugin install` 的版本：

- **GitHub**: https://github.com/tobemaster56/liam-skills
- **直接安装**：
  ```text
  /plugin marketplace add tobemaster56/liam-skills
  /plugin install switch-appleid@liam-skills
  ```

欢迎 fork、改造、发 PR。

---

**写在最后**：自动化的乐趣其实不在「省了 30 秒」，而在「把繁琐流程外包给电脑之后，注意力终于可以放在该放的地方」。Agent Skill 让这事的门槛降到——任何一段你写得清楚的步骤说明都能变成 AI 的工具。下次再做重复操作时，不妨问问自己：这能不能写成一个 skill？
