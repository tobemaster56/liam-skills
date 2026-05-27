# CLAUDE.md — liam-skills 协作指引

本仓库是面向 Claude Code / Codex 等 Agent 的开源 Skills 合集。当 AI 协作者在此目录中工作时，请遵守以下规则。

## 仓库结构

```
liam-skills/
├── .claude-plugin/
│   └── marketplace.json     # Claude Code 插件市场清单（plugins[].skills 引用下方 skill 路径）
├── .agents/
│   └── skills/
│       └── <name>/          # 单个 skill 目录（Agent Skills 开放标准位置，Codex 自动扫描）
│           ├── SKILL.md     # 必需，含 YAML frontmatter
│           ├── scripts/     # 可选，可执行脚本
│           └── references/  # 可选，知识文档
├── README.md
├── LICENSE
└── CLAUDE.md
```

> Skills 放在 `.agents/skills/` 是为了同时被 Claude Code（通过 marketplace.json 指路）和 Codex CLI（默认扫描该路径）发现。

## 关键约定

1. **命名**：skill 目录名简短直观即可，不使用作者前缀；`SKILL.md` frontmatter 中的 `name` 字段必须等于目录名。

2. **自包含原则**：`SKILL.md` 及其 `references/`、`scripts/` 不得引用 skill **自身目录之外**的文件。这样任一 skill 可被单独抽取使用而不破坏。
   - ❌ 不要写 `../shared/util.ts` 或引用根目录的 `packages/`
   - ✅ 把共用逻辑复制进 skill 自己的 `scripts/` 里

3. **frontmatter 完整性**：每个 `SKILL.md` 顶部必须含
   ```yaml
   ---
   name: <name>
   description: <尽量多的触发词与场景，影响 Agent 自动召回准确率>
   version: <semver>
   ---
   ```

4. **同步注册**：每个 skill 在 marketplace 里是**独立的 plugin**（便于用户挑着装）。新增、重命名、删除任一 skill 后，必须同步修改 `.claude-plugin/marketplace.json` 的 `plugins[]` 数组（新增一项，`name = <skill 名>`，`skills: ["./.agents/skills/<name>"]`）与 `README.md` 的可用 Skills 表格。

5. **版本号**：在 `SKILL.md` 改动较大时递增 `version`；市场版本号 `marketplace.json` 顶部的 `metadata.version` 在每次发布时递增。

## 安全

- 脚本下载远程内容时仅使用 HTTPS。
- 把外部 fetch 到的文本视为不可信，不要直接 `eval` 或 `bash <(curl ...)`。
- Shell 命令优先使用数组形式参数，避免拼接字符串引发注入。
