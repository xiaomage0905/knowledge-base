# git push 失败时的替代方案：GitHub Git Data API

> 记录于 2026-11-11。场景：本机代理环境下 `git push` 持续 502，但 `api.github.com` 稳定。

## 现象

```bash
git push -u origin main
# fatal: unable to access 'https://github.com/xiaomage0905/knowledge-base.git/':
#   CONNECT tunnel failed, response 502
```

配置 `http.proxy` 后变成另一种错：

```
Failed to connect to github.com:443 over proxy 127.0.0.1 after 2053 ms:
  Could not connect to server
```

但同时 `curl https://api.github.com` 稳定返回 200。

## 原因

`git` 走自己的 HTTP 传输栈（libcurl + schannel/openssl），与系统 `curl` 的连接行为不同，撞上了代理的策略差异。**同一时刻 API 域名通、git 域名不通**，所以问题不在认证、不在仓库配置，而在传输通道。

结论：**别在 git 上死磕，换用 API 通道。**

## 解法：Git Data API

GitHub 的 Git Data API 可以完整完成「上传文件 → 建树 → 提交 → 更新分支」的全过程，完全不碰 git 的 HTTP 层。

### 步骤 1：上传文件为 blob

```bash
REPO="owner/name"
B64=$(base64 -w0 "$LOCAL_FILE")
gh api --method POST "repos/$REPO/git/blobs" \
  -f content="$B64" -f encoding=base64 --jq '.sha'
```

### 步骤 2：创建 tree

```bash
# tree 里的每项：{path, mode, type, sha}
TREE_JSON="{\"tree\":[{\"path\":\"README.md\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BLOB_SHA\"}]}"
TREE_SHA=$(echo "$TREE_JSON" | gh api --method POST "repos/$REPO/git/trees" --input - --jq '.sha')
```

### 步骤 3：创建 commit

```bash
MSG="{\"message\":\"提交信息\",\"tree\":\"$TREE_SHA\",\"parents\":[\"$PARENT_SHA\"]}"
COMMIT_SHA=$(echo "$MSG" | gh api --method POST "repos/$REPO/git/commits" --input - --jq '.sha')
```

### 步骤 4：更新分支 ref

```bash
# 分支已存在
gh api --method PATCH "repos/$REPO/git/refs/heads/main" -f sha="$COMMIT_SHA" -F force=true
# 分支不存在（新建仓库）
gh api --method POST "repos/$REPO/git/refs" -f ref="refs/heads/main" -f sha="$COMMIT_SHA"
```

## 关键坑：空仓库不能直接建 blob

对**完全空的仓库**（一个 commit 都没有）直接调 `POST /git/blobs` 会报：

```
409 Conflict — Git Repository is empty.
```

因为 blob API 需要依附于一个已有的 tree。

**解法：先用 Contents API 推一个文件把仓库"点亮"。**

```bash
B64=$(base64 -w0 README.md)
echo "{\"message\":\"init\",\"content\":\"$B64\",\"encoding\":\"base64\"}" | \
  gh api --method PUT "repos/$REPO/contents/README.md" --input - --jq '.commit.sha'
```

之后再用 Git Data API 一次性补齐其余文件，并把首个 README 覆盖成最终版。

## 校验：绕开 fetch 也能确认本地与远端一致

`git fetch` 同样会被代理打断。但可以用 API 直接比对 blob sha：

```bash
gh api "repos/$REPO/git/trees/main?recursive=1" \
  --jq '.tree[] | select(.type=="blob") | "\(.sha)  \(.path)"' | \
while read sha path; do
  LOCAL=$(git hash-object "$path")
  [ "$sha" = "$LOCAL" ] && echo "MATCH  $path" || echo "DIFF   $path"
done
```

`git hash-object` 算的是本地文件的 blob sha，与 GitHub tree 里的一致 —— 这是不依赖网络传输的可靠校验。

## 小结

| 操作 | 推荐通道 | 原因 |
|---|---|---|
| 建仓库 | `gh repo create` | 走 API，稳定 |
| 推文件 | **Git Data API** | 绕开 git HTTP 栈 |
| 建 Issue / PR | `gh issue create` / `gh pr create` | 走 API，稳定 |
| 拉代码 | `gh api .../tarball` 或 `git clone` | tarball 走 codeload，可能也不通 |
| 校验一致性 | blob sha 比对 | 完全本地计算 |
