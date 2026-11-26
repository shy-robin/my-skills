# my-skills

个人维护的 Agent Skills 仓库，兼容 `npx skills` 标准目录规范。

## 安装

```bash
# 安装仓库内全部 skill（全局）
npx skills add shy-robin/my-skills -g

# 仅安装指定 skill
npx skills add shy-robin/my-skills --skill codex-worker -g
```

## Skills 列表

| Skill | 说明 |
| :--- | :--- |
| `codex-worker` | AGY 负责制定精准方案与 Code Review，通过显式 `SESSION_ID` 委派本机 Codex CLI 实现并闭环审查 |
