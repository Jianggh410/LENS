# LENS

**Literature Engine for Note-making and Synthesis**

[English](README_EN.md) · [安装](docs/installation.md) · [配置](docs/configuration.md) · [工作流](docs/workflow.md) · [系统目录](docs/system-directory_CN.md) · [故障排查](docs/troubleshooting.md)

LENS 是一个由 Codex Skills 与可执行脚本组成的科研文献工作流。你可以直接把 PDF 交给 Agent，让它生成中文结构化 Obsidian 笔记、提取 Figure/Table、建立文献索引、跟踪新论文，并把笔记转换成以论文图片为主的 PPT。

## 目录

- [1. 项目发起人与运营信息](#1-项目发起人与运营信息)
- [2. 项目理念与社区](#2-项目理念与社区)
- [3. 快速开始](#3-快速开始)
- [4. 安装](#4-安装)
- [5. 技能索引](#5-技能索引)
- [6. 贡献与开发](#6-贡献与开发)

## 1. 项目发起人与运营信息

- **发起人及维护者**：Howard Jiang
- **代码仓库**：[Jianggh410/LENS](https://github.com/Jianggh410/LENS)
- **问题反馈与功能建议**：[GitHub Issues](https://github.com/Jianggh410/LENS/issues)
- **许可证**：[LICENSE](LICENSE)

LENS 以个人科研知识库的实际使用需求为起点，目标是把“发现论文—全文阅读—提取证据—形成笔记—持续整理—汇报展示”连接成一条可复用的工作流。

## 2. 项目理念与社区

LENS 遵循以下原则：

1. **原始论文是事实来源**：元数据、方法、结果和 Figure 解读必须能回到 PDF 或经过验证的一手页面。
2. **证据结构优先**：笔记不仅摘要论文，还组织 Works、Results/Evidence、Question–Method Map、Evidence Chain、局限性和研究启示。
3. **AI 初稿与人工策展分离**：新笔记从 `ai-draft` 开始，经过人工阅读后再进入 Library。
4. **不可靠时显式降级**：Figure/Table 无法确认完整时保留候选裁剪并标记人工检查，不伪造缺失内容。
5. **产物可直接继续使用**：输出 Markdown、PNG、JSON、Canvas、Wiki 和 PPTX，而不是只在对话中返回一段摘要。
6. **Skill 自包含、流程可扩展**：规则、模板和脚本按 Skill 组织，便于独立维护与增加新能力。

欢迎通过 GitHub Issues 提交错误、规则建议、期刊版式样例或新的工作流需求。提交问题时，建议附上最小复现输入、预期结果和实际结果；涉及受版权保护的论文时，请不要公开上传无权分发的全文。

## 3. 快速开始

安装完成后，可以直接把论文或笔记交给 Agent。如果不确定该使用哪个 Skill，直接描述目标即可；已经知道 Skill 名时，也可以在提示词中明确指定。

| 想做什么 | 可以直接这样说 |
| --- | --- |
| 阅读一篇论文 | `使用 LENS 读取这个 PDF，生成结构化文献笔记。` |
| 重新提取图片 | `使用 LENS 重新提取这篇笔记的 Figure，并检查 panel 完整性。` |
| 处理 Review | `使用 LENS 读取这篇 Review，并按 Figure 和 Table 组织 Evidence。` |
| 制作 PPT | `把这篇文章的笔记做成 PPT。` |
| 查看状态 | `检查当前 LENS 文献笔记的状态。` |
| 跟踪文献 | `运行 LENS literature follow-up。` |

### 在 Agent 中使用

把 PDF 作为附件发送，随后用自然语言提出任务。Agent 会读取本地 LENS 规则，执行对应脚本，并返回可打开的笔记路径和提取状态。

![在 Agent 中使用 LENS](assets/agent-usage-example.png)

### 结构化笔记产物

Article 笔记通常包含 YAML 元数据、Info、Summary、Intro、Works、Results、Question–Method Map、Discussion 和 Key references；Review 则以 Figure/Table 为锚点组织 Evidence。提取的图片保存在笔记对应的 assets 目录。

![LENS 结构化论文笔记示例](assets/paper-note-example.png)

## 4. 安装

### 4.1 克隆到稳定路径

```bash
git clone git@github.com:Jianggh410/LENS.git
cd LENS
```

不要把仓库放在会被系统自动清理的临时目录。LENS 的运行配置、Skills 和持久数据都以仓库位置为基础推导。

### 4.2 验证环境

```bash
bash scripts/validate.sh
```

验证内容包括必需文件、Shell/Python 语法、JSON 配置以及运行路径。

### 4.3 接入 Codex

```bash
bash scripts/install.sh
```

安装脚本会把支持的 LENS Skills 链接到 Codex Skills 目录。完整的依赖、路径配置和更新方式见[安装文档](docs/installation.md)。

### 4.4 配置研究方向与文献来源

编辑：

- `config/lens_config.sh`：论文目录、Literature 工作区、研究项目关键词、模型和提取参数。
- `config/followup_sources.json`：期刊 RSS 与预印本来源。

详细字段见[配置文档](docs/configuration.md)。

## 5. 技能索引

### `lens-paper-note`

完整阅读 Article 或 Review PDF，并生成结构化中文 Obsidian 笔记。它还负责：

- YAML 元数据与 narrative 分类
- Article Results 和 Review Evidence 组织
- Question–Method Map 与 Evidence Chain
- 编号 Figure 和 Review Table 提取
- panel、caption、边缘和裁剪完整性检查
- Reading/Library Wiki 重建
- Reading Canvas 与笔记状态工具

### `lens-literature-followup`

从配置的 RSS/API 来源获取新论文，按 `USER_RESEARCH` 关键词匹配，保存历史状态，并生成 weekly/project 级文献跟踪页面。

### `lens-paper-note-to-ppt`

将 LENS Markdown 笔记转换为以 Figure/Table 为主的 PPTX。标题、字体、Citation、legend、页码和布局规则由 Skill 内的 `ppt.config` 控制。

## 6. 贡献与开发

### 6.1 共享设计原则

所有 LENS Skills 都应遵守以下原则：

1. **优先使用一手来源**：规则基于原始论文、官方期刊页面、数据库或明确的本地来源。
2. **显式胜过隐式**：重要判断需要留下状态、置信度、失败原因或可检查的中间产物。
3. **感知文献类型与版式**：Article、Review、不同期刊和不同 caption/panel 风格采用相应逻辑。
4. **输出优先**：返回可直接使用的 `.md`、`.png`、`.json`、`.canvas` 或 `.pptx`。
5. **可扩展**：每个 Skill 自包含；新增 Skill 尽量不破坏既有工作流。
6. **保护用户内容**：不覆盖人工编辑的笔记，不把 cache 当成持久数据，不手动修改自动生成的 Wiki。

### 6.2 仓库目录结构

仓库目录、每个文件夹的职责、是否可以清理以及清理影响，统一维护在：

- [系统目录与清理说明（中文）](docs/system-directory_CN.md)
- [System directories and cleanup](docs/system-directory.md)

README 不重复维护运行时目录细节，以免与实际配置漂移。

### 6.3 新增 Skill 流程

1. 在 `skills/` 下创建独立目录：

   ```text
   skills/lens-<topic>/
   ```

2. 添加 `SKILL.md`，明确触发条件、任务边界、输入、输出和失败策略。
3. 按需添加 `agents/`、`references/`、`assets/`、`scripts/` 或独立配置文件。
4. 把必要的结构和语法检查加入 `scripts/validate.sh`。
5. 更新安装逻辑、技能索引与相关文档。
6. 运行验证，并用真实但可合法分发的最小样例测试完整流程。

```bash
bash scripts/validate.sh
```

### 6.4 修改原则

- 不把用户数据、PDF、数据库、cache 或 logs 提交到 Git。
- 修改 Figure/Table 提取规则时，同时记录成功、降级和人工检查路径。
- 修改笔记模板时，确保 Wiki、PPT 和已有笔记仍能兼容。
- 修改配置字段时，同步更新 `docs/configuration.md` 和示例。
