---
name: codex-worker
description: 使用当前 Agent（AGY）负责制定精准方案与 Code Review，并将具体编码实现委派给本机 Codex CLI（如 GPT-6.2）执行、按显式 SESSION_ID 精准打回修改的协作工作流。当用户说“交给 codex 实现”、“出方案让 codex 写”、“用 codex 写代码然后你 review”、“codex-worker”时使用。
---

# Codex Worker 协作工作流（AGY 规划/审查 + Codex 实现）

本 Skill 用于将 **方案设计 & Code Review** 与 **具体编码实现** 解耦，避免人工在两个终端之间复制粘贴 prompt，同时通过**日志隔离**和**显式 `SESSION_ID`** 杜绝 Token 浪费与多会话串话。

## 固定脚本入口

使用本 Skill 自带的包装脚本调用 Codex：

```bash
~/.gemini/config/skills/codex-worker/scripts/run_codex.sh
```

* **首次派发任务**（新建独立 Codex 会话）：
  ```bash
  ~/.gemini/config/skills/codex-worker/scripts/run_codex.sh \
    --cwd "<项目或 worktree 路径>" \
    [--effort low|medium|high] \
    --prompt-file "<任务说明文件>"
  ```
* **打回修改**（必须显式传回上一轮返回的 `SESSION_ID`，**严禁使用 `--last`**）：
  ```bash
  ~/.gemini/config/skills/codex-worker/scripts/run_codex.sh \
    --cwd "<项目或 worktree 路径>" \
    --session "<SESSION_ID>" \
    [--effort low|medium|high] \
    --prompt-file "<Review 意见文件>"
  ```

### 分工与推理档位建议
* **纯前端 UI 视觉 / 设计稿还原**：优先由当前 Agent（Gemini 4 Neon）直接完成，不必强行绕道委派给 Codex。
* **后端核心逻辑、复杂 TS 类型/状态机、精准重构、单测驱动修复**：优先委派给 Codex 执行。
* **`--effort` 档位**：日常简单任务省略（默认沿用本机配置的 `low`）；涉及复杂并发、算法、疑难 Bug 或高风险重构时传 `--effort medium` 或 `high`。

脚本会自动：
1. 将 Codex 的 `--json` 过程日志重定向到 `/tmp/codex-worker-*.jsonl`，**不污染当前上下文**；
2. 用 `-o` 将 Codex 最终回复写入 `/tmp/codex-worker-*.md`；
3. 仅向 stdout 打印精简元信息：`EXIT_CODE`、`SESSION_ID`、`SUMMARY_FILE`、`LOG_FILE`。

---

## 标准执行步骤

### 第 1 步：制定精准方案（减少 Codex 探索消耗）
1. 先自行阅读相关代码，弄清上下文。
2. 编写清晰、紧凑的实施方案，尽量写明：
   * 目标与验收标准；
   * 需要修改或新增的具体文件路径、关键函数/符号；
   * 边界条件、约束（不要顺手改动无关文件）；
   * 完成后应运行的校验/测试命令。
3. **如果需求较大或存在设计分歧**，先向用户展示方案并确认后再派发给 Codex；若用户已明确要求直接推进，可直接进入第 2 步。
4. 将方案写入临时文件（如 `/tmp/codex-plan-<slug>.md`），不要把超长多行文本硬拼在 shell 参数里。

### 第 2 步：派发给 Codex 实现
1. 调用 `run_codex.sh --cwd "<cwd>" --prompt-file "/tmp/codex-plan-<slug>.md"`。
2. 记录脚本返回的 **`SESSION_ID`**（UUID）与 `SUMMARY_FILE`。
3. 只读取 `SUMMARY_FILE` 了解 Codex 的执行摘要；除非 `EXIT_CODE != 0`，否则**不要**读取冗长的 `LOG_FILE`。

### 第 3 步：Code Review 与验证
1. 在目标目录执行 `git status --short` 和 `git diff`（只审查实际变更，不重复通读整个仓库）。
2. 运行对应的测试、类型检查或构建命令验证改动。
3. 核对是否满足第 1 步方案中的所有要求，以及是否存在逻辑 bug、遗漏边界或多余改动。

### 第 4 步：精准打回修改（最多 2 轮）
* **若审查通过**：直接向用户汇总改动内容、验证结果与文件路径，结束任务。
* **若发现明确问题**：
  1. 把具体、可执行的修改意见（含文件名、行号、原因和期望行为）写入 `/tmp/codex-review-<slug>.md`；
  2. 使用第 2 步保存的 **`SESSION_ID`** 调用 `run_codex.sh --session "<SESSION_ID>" --prompt-file ...`；
  3. 再次执行第 3 步审查。
* **防死循环硬性上限**：最多自动打回 **2 轮**。若 2 轮后仍未通过，停止自动循环，将现状、未解决的问题和建议方案汇报给用户裁决。

---

## 省 Token 与避坑原则
* **永远使用显式 `SESSION_ID`**，不要用 `--last`，确保同一目录或多 worktree 并行时绝不串话。
* **保持方案文件精炼具体**，帮 Codex 省去满仓库盲搜的开销。
* **只读 `SUMMARY_FILE` + `git diff`**，不要把 Codex 的完整事件流灌进 AGY 上下文。
* **不要随意开启 `--dangerously-bypass-approvals-and-sandbox`**，保持 `--approve-for-me` 默认的 `workspace-write` 沙箱与安全边界。
* **人工查看历史会话**：`codex exec` 创建的是非交互会话，若要在交互式选择器里查看，请使用 `codex resume --include-non-interactive`（跨目录加 `--all`），或直接 `codex resume <SESSION_ID>`。
