# liam-skills

Liam 分享的 Skills 合集，遵循 [Agent Skills 开放标准](https://agentskills.io)。同时支持 [Claude Code](https://claude.com/claude-code) 与 [Codex CLI](https://developers.openai.com/codex)。

## 仓库布局

Skills 物理存放在 `.agents/skills/` 下 —— 这是 Agent Skills 开放标准约定的路径，Codex CLI 默认就会扫描。Claude Code 通过 `.claude-plugin/marketplace.json` 显式引用同一份目录，因此两边共用一套源文件。

## 安装 —— Claude Code

### 方式 1：注册插件市场（推荐）

```text
/plugin marketplace add tobemaster56/liam-skills
```

注册后通过 Browse UI 安装：

1. 执行 `/plugin`
2. 选择 **Browse and install plugins**
3. 找到 **liam-skills** 市场 → 选择 **liam-skills** 插件 → **Install now**

### 方式 2：直接安装

```text
/plugin install liam-skills@liam-skills
```

### 方式 3：让 Agent 自助安装

直接对 Agent 说：

> 请帮我安装 github.com/tobemaster56/liam-skills 的 Skills。

### 更新

1. 执行 `/plugin`
2. 切到 **Marketplaces** 标签
3. 选择 **liam-skills** → **Update marketplace**

也可以开启 **Enable auto-update** 自动跟随新版本。

## 安装 —— Codex CLI

Codex 没有"插件市场"概念，但会扫描 `.agents/skills/`。

**全局可用**（任意目录下都能调用）：

```bash
git clone https://github.com/tobemaster56/liam-skills.git ~/.local/share/liam-skills
mkdir -p ~/.agents/skills
ln -s ~/.local/share/liam-skills/.agents/skills/switch-appleid ~/.agents/skills/switch-appleid
```

后续更新只需 `git -C ~/.local/share/liam-skills pull`。

**仅在某项目内使用**：直接 `git clone` 到项目根，Codex 会自动从 cwd 沿仓库结构向上扫描发现。

## 可用 Skills

| Skill | 描述 | 触发词示例 |
|-------|------|-----------|
| [`switch-appleid`](./.agents/skills/switch-appleid/SKILL.md) | macOS App Store 一键切换不同区域 Apple ID（CN/US/TR/JP 等）。凭据存钥匙串，AppleScript 驱动 App Store UI | "切换 Apple ID 区域"、"switch apple id"、"切到美区/国区/土区" |

## 添加新 Skill

1. 在 `.agents/skills/` 下新建目录 `.agents/skills/<name>/`，写一个 `SKILL.md`，顶部 YAML frontmatter 至少含 `name`、`description`、`version` 三个字段。`name` 须等于目录名。
2. 需要执行脚本时新建 `scripts/`，需要内嵌长文档时新建 `references/` —— 这些子目录中的所有引用必须**指向 skill 自身目录**，不得跨 skill。
3. 在 `.claude-plugin/marketplace.json` 的 `plugins[0].skills` 数组里追加 `"./.agents/skills/<name>"`。
4. 在本 README 的「可用 Skills」表格里加一行。
5. 提交。

## 许可

[MIT](./LICENSE)
