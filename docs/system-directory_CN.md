# 系统目录与清理说明

本文说明 `_system/` 下各目录的职责、是否可以清理、删除后的影响，以及 LENS 是否能够自动重建。

## 清理规则总览

| 路径 | 功能 | 是否可以清理 | 删除影响 | 是否自动重建 |
| --- | --- | --- | --- | --- |
| `cache/` | PDF 转换、prompt、队列和 AI 响应等临时中间文件 | 可以，但必须确认没有 LENS 任务正在运行 | 下次运行需要重新生成或获取中间数据 | 可以 |
| `logs/` | 带时间戳的运行与 follow-up 日志 | 可以定期清理 | 丢失历史调试记录 | 有新日志时自动创建 |
| `data/` | SQLite 数据库和持久化工作流状态 | 不可以 | 可能丢失 follow-up 历史、处理状态和尝试记录 | 目录可重建，丢失状态不可恢复 |
| `config/` | 运行变量和文献来源注册表 | 不可以 | 路径、研究项目、来源和工作流行为失效 | 不可以 |
| `skills/` | LENS Skills、规则、模板、schema、配置和执行脚本 | 不可以 | LENS 功能无法运行 | 不可以 |
| `scripts/` | 仓库级安装、更新和验证工具 | 不可以 | 无法执行维护与验证命令 | 不可以 |
| `docs/` | 运行和开发文档 | 不建议 | 运行可能不受影响，但维护依据丢失 | 不可以 |
| `assets/` | README 和仓库文档使用的图片附件 | 不建议 | README 图片和文档附件失效 | 不可以 |
| `.git/` | Git 历史和仓库元数据 | 不可以 | 版本管理和安全更新功能损坏 | 不可以 |

## `cache/`

`cache/` 是不纳入 Git 的可丢弃运行目录，不是文献数据库，也不是正式产物目录。

预期子目录如下：

```text
cache/
├── ingest_markdown/       # 从原始 PDF 转换得到的 Markdown
├── ingest_prompts/        # 自动生成的摄取 prompt 与笔记清单
├── literature_followup/   # 待处理记录、prompt 与结构化 AI 响应
└── assets/                # 预留的临时生成资源目录
```

- `skills/lens-paper-note/scripts/ingest_paper.sh` 使用 `ingest_markdown/` 和 `ingest_prompts/`。
- `skills/lens-literature-followup/scripts/run_followup.sh` 使用 `literature_followup/`。
- 子目录按需创建，两次运行之间可能不存在或为空。
- 如果 `_system/cache` 不可写，论文摄取流程会在当次运行中退回 `${TMPDIR:-/tmp}/literature_ingest_cache`。

清理前必须确认没有论文摄取、图片提取或 follow-up 任务正在运行。清空 cache 不会删除原始 PDF、Obsidian 笔记、笔记 assets、Wiki 页面或持久化 follow-up 数据库。

## `data/`

`data/` 保存持久化机器状态，不能作为 cache 处理。当前最主要的状态文件是 literature follow-up SQLite 数据库：

```text
data/literature_followup/literature_followup.sqlite3
```

它记录已经获取的论文、项目匹配、总结状态、尝试次数和历史记录。SQLite 文件不纳入 Git；`.gitkeep` 只用于保留目录结构。迁移或破坏性维护前应备份该目录。

## `config/`

- `lens_config.sh` 定义或推导 Literature 工作区、论文收件箱、研究项目、模型、Figure 提取行为、PPT 默认值和运行目录。
- `followup_sources.json` 定义期刊 RSS 和预印本来源。

单次运行可以用环境变量覆盖可移植配置。除非准备手动重建配置，否则不要删除这些文件。

## `skills/`

- `lens-paper-note/`：Article/Review 全文阅读、结构化笔记生成、Figure/Table 提取、Wiki 重建、Reading Canvas 和笔记状态工具。
- `lens-literature-followup/`：RSS/API 获取、项目匹配、持久状态、AI 摘要及 weekly/project follow-up 页面。
- `lens-paper-note-to-ppt/`：按照 `ppt.config` 把 LENS 笔记转换为以图片为主的 PowerPoint。

每个 Skill 自包含，可以拥有 `SKILL.md`、`agents/`、`references/`、`assets/`、`scripts/`、schema、模板或独立配置。

## `scripts/`

- `install.sh`：把支持的 Skills 链接到 Codex Skills 目录。
- `update.sh`：执行安全的 fast-forward 更新、验证和重新安装。
- `validate.sh`：验证必需文件、语法、JSON、配置和自动推导路径。

处理具体论文的执行脚本位于对应 Skill 目录中。

## `docs/`

- `installation.md`：安装与初始化。
- `configuration.md`：运行配置和来源注册表。
- `workflow.md`：端到端文献工作流。
- `troubleshooting.md`：常见错误与恢复。
- `system-directory.md`：英文目录与清理说明。
- `system-directory_CN.md`：本中文目录与清理说明。

## `assets/`

保存纳入版本控制、供仓库文档使用的附件，例如 README 截图。它不同于：

- `cache/assets/`：可以清理的临时目录；
- `Reading/ai-draft/assets/<note-stem>/`：笔记专属 Figure 和 PPTX；
- Library 内的 assets：属于人工整理后的笔记。

## `logs/`

按需创建且不纳入 Git。literature follow-up 会把带时间戳的日志写入 `logs/literature_followup/`。不再需要调试历史后，可以定期删除日志。

## `_system` 根目录文件

- `README.md`：简洁项目入口和语言选择。
- `README_CN.md` 与 `README_EN.md`：面向用户的项目说明。
- `LICENSE`：仓库许可证。
- `.gitignore`：排除 cache、logs、数据库和本地杂项。
- `.git/`：Git 历史和元数据，不应手动编辑或清理。

## `_system` 之外的正式产物

面向用户的正式产物位于上一级 `Literature/` 工作区：

- `Reading/ai-draft/`：AI 生成的论文笔记。
- `Reading/ai-draft/assets/<note-stem>/`：提取图片和生成的 PPTX。
- `Library/`：人工整理后的笔记及 assets。
- `Synthesis/`：跨论文综合笔记。
- `Followup/`：weekly 和 project 级文献跟踪页面。
- `Wiki/Reading/` 与 `Wiki/Library/`：生成的页面、JSON 索引和 GraphView 文件。

原始 PDF 始终是论文内容的事实来源，通常位于配置的 `RAW_DIR` 或用户提供的其他路径。
