# knowledge-base

个人知识库 —— 技术笔记、踩坑记录、问题与解答。

> 这个仓库由 WorkBuddy 协助维护，记录日常开发中值得沉淀的问题与答案。
> 公开可见，便于随时检索与复用。

## 目录结构

```
knowledge-base/
├── README.md            # 本文件，仓库导航
├── notes/               # 主题笔记（按领域分文件）
│   └── dev-environment.md
├── troubleshooting/     # 踩坑记录：现象 → 原因 → 解法
│   ├── proxy-and-network.md
│   └── git-push-via-api.md
├── scripts/             # 可复用脚本
│   └── sync-via-api.sh  # git push 被代理阻断时的同步脚本
├── qa/                  # 问题与解答（Q&A）
└── snippets/            # 可直接复用的代码片段
```

## 使用约定

| 约定 | 说明 |
|---|---|
| 文件命名 | 全小写，多词用连字符，如 `network-proxy.md` |
| 踩坑记录格式 | **现象** → **原因** → **解法**，三段齐全才算完整 |
| Q&A 格式 | 一问一答，答案放前面，问题作为标题 |
| 提交信息 | 用中文写清楚「改了什么、为什么」 |

## 快速上手

```bash
# 克隆
git clone https://github.com/xiaomage0905/knowledge-base.git

# 新增一篇笔记
mkdir -p notes && vim notes/my-topic.md
git add notes/my-topic.md && git commit -m "docs: 新增 XXX 笔记" && git push
```

## 索引

### 笔记
- [开发环境配置](notes/dev-environment.md)

### 踩坑记录
- [代理与网络访问问题](troubleshooting/proxy-and-network.md)
- [git push 失败时的替代方案](troubleshooting/git-push-via-api.md)

### 脚本
- [sync-via-api.sh](scripts/sync-via-api.sh) —— 绕过 `git push`，用 Git Data API 同步文件

## 开放 Issue

见 [Issues 页面](https://github.com/xiaomage0905/knowledge-base/issues)。当前 Issue 列表：

```bash
gh issue list --repo xiaomage0905/knowledge-base --state open
```

## 许可

MIT License
