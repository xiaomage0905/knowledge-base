# 开发环境配置

> 记录于 2026-11-11，Windows 11 + Git Bash 环境。

## GitHub CLI (gh)

### 安装

`winget` 通道在本机代理环境下不可用（`InternetOpenUrl() failed. 0x80072efd`），
改用 API 资产端点下载便携版：

```bash
GH_DIR=~/.workbuddy/binaries/gh
mkdir -p $GH_DIR && cd $GH_DIR

# 取 asset id
ASSET_ID=$(curl -s "https://api.github.com/repos/cli/cli/releases/latest" \
  | grep -B5 '"gh_2.103.3_windows_amd64.zip"' \
  | grep -oE '"id": [0-9]+' | head -1 | grep -oE '[0-9]+')

# 下载（注意用 api.github.com 的 asset 端点，不要用 github.com 直链）
curl -sL -H "Accept: application/octet-stream" -o gh.zip \
  "https://api.github.com/repos/cli/cli/releases/assets/$ASSET_ID"

unzip -o -q gh.zip
export PATH="$GH_DIR/bin:$PATH"      # 实际路径是 $GH_DIR/gh_2.103.3_windows_amd64/bin
gh --version
```

### 设备码登录（手动版）

`gh auth login --web` 在本机代理下会在最后换 token 时失败：

```
failed to authenticate via web browser: Post "https://github.com/login/oauth/access_token": unexpected EOF
```

改为手动走 OAuth Device Flow：

```bash
CLIENT_ID=178c6fc778ccc68e1d6a   # gh 官方内置的 client_id

# 1) 申请设备码
curl -s --retry 4 --retry-all-errors --retry-delay 2 \
  -X POST "https://github.com/login/device/code" \
  -H "Accept: application/json" \
  -d "client_id=$CLIENT_ID&scope=repo"
# → {"device_code":"...","user_code":"XXXX-XXXX","expires_in":899,"interval":5}

# 2) 浏览器打开 https://github.com/login/device，填入 user_code
#    页面是 8 个单字符输入框（4位 + 4位，中间固定有"-"）
#    点 Continue → Authorize 按钮有几秒冷却禁用期，等一下再点

# 3) 换 token
curl -s --retry 4 --retry-all-errors --retry-delay 2 \
  -X POST "https://github.com/login/oauth/access_token" \
  -H "Accept: application/json" \
  -d "client_id=$CLIENT_ID&device_code=$DEVICE_CODE&grant_type=urn:ietf:params:oauth:grant-type:device_code"
# → {"access_token":"gho_...","token_type":"bearer","scope":"repo"}
```

### 持久化凭据

写入 `%APPDATA%\GitHub CLI\hosts.yml`：

```yaml
github.com:
    oauth_token: gho_xxxxxxxx
    user: your-login-name
    git_protocol: https
```

之后 `gh auth status` 即可直接用，无需再走浏览器流程。

> 临时用法也可用环境变量：`export GH_TOKEN=gho_xxx`（优先级高于 hosts.yml）。

## 常用命令速查

```bash
# 当前登录状态
gh auth status

# 列出所有仓库（含私有、协作、组织仓库）
gh repo list --limit 100 --json nameWithOwner,visibility,isArchived,updatedAt

# 列出所有开放 Issue（需在 git 仓库内，或指定 --repo）
gh issue list --state open --limit 100
gh issue list --repo owner/repo --state open

# 某仓库的开放 Issue（含标题、作者、链接）
gh issue list --repo owner/repo --state open \
  --json number,title,author,createdAt,url

# GraphQL 一次性汇总（比 REST 更省请求）
gh api graphql -f query='query{viewer{login repositories(first:100){totalCount nodes{nameWithOwner visibility isArchived issues(states:OPEN){totalCount}}}}}' \
  --jq '.data.viewer'

# 建库（本地已有 git 仓库）
gh repo create owner/name --public --source=. --remote=origin

# 建库（纯远端，空库）
gh repo create owner/name --public --description "描述"
```

### 小坑

- `gh issue list` 在**非 git 目录**下会报 `failed to run git: fatal: not a git repository`，必须加 `--repo`。
- `gh issue list --json repository` 字段不存在，仓库名要自己拼前缀或用 `--jq` 处理。
- `gh search issues --owner <user>` 遇到空账号会报 `The listed users and repositories cannot be searched` —— 是因为该账号真的没有可搜索的资源，不是参数写错。
