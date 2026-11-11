#!/usr/bin/env bash
# 通过 GitHub Git Data API 把本地文件同步到远端分支
# 用法: ./sync-via-api.sh <owner/repo> <branch> <file1> [file2 ...]
# 适用于 git push 被代理阻断的环境
set -eu
export PATH="$HOME/.workbuddy/binaries/gh/bin:$PATH"

REPO="${1:?用法: sync-via-api.sh <owner/repo> <branch> <file...>}"
BRANCH="${2:?用法: sync-via-api.sh <owner/repo> <branch> <file...>}"
shift 2
FILES=("$@")

ENTRIES=()
for f in "${FILES[@]}"; do
  B64=$(base64 -w0 "$f")
  BLOB=$(gh api --method POST "repos/$REPO/git/blobs" -f content="$B64" -f encoding=base64 --jq '.sha')
  [ -n "$BLOB" ] && [ "${BLOB#*message}" = "$BLOB" ] || { echo "BLOB FAIL: $f -> $BLOB" >&2; exit 1; }
  echo "blob ok: $f"
  ENTRIES+=("{\"path\":\"$f\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BLOB\"}")
done

TREE_JSON="{\"tree\":[$(IFS=,; echo "${ENTRIES[*]}")]}"
TREE_SHA=$(echo "$TREE_JSON" | gh api --method POST "repos/$REPO/git/trees" --input - --jq '.sha')
[ -n "$TREE_SHA" ] || { echo "TREE FAIL" >&2; exit 1; }
echo "tree -> $TREE_SHA"

# 父 commit：分支存在则取当前 sha，不存在则用空仓库的首次提交方式
BASE=$(gh api "repos/$REPO/git/ref/heads/$BRANCH" --jq '.object.sha' 2>/dev/null || echo "")
if [ -z "$BASE" ]; then
  PARENTS="[]"
  REF_MODE="create"
else
  PARENTS="[\"$BASE\"]"
  REF_MODE="update"
fi

MSG=$(printf '{"message":"%s","tree":"%s","parents":%s}' "${SYNC_MESSAGE:-sync: 更新文件}" "$TREE_SHA" "$PARENTS")
COMMIT_SHA=$(echo "$MSG" | gh api --method POST "repos/$REPO/git/commits" --input - --jq '.sha')
[ -n "$COMMIT_SHA" ] || { echo "COMMIT FAIL" >&2; exit 1; }
echo "commit -> $COMMIT_SHA"

if [ "$REF_MODE" = "update" ]; then
  gh api --method PATCH "repos/$REPO/git/refs/heads/$BRANCH" -f sha="$COMMIT_SHA" -F force=true --jq '.ref'
else
  gh api --method POST "repos/$REPO/git/refs" -f ref="refs/heads/$BRANCH" -f sha="$COMMIT_SHA" --jq '.ref'
fi
echo "DONE $COMMIT_SHA"
