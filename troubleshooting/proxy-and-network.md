# 代理与网络访问问题

> 记录于 2026-11-11，环境：Windows + Git Bash + 本地 HTTP 代理。

## 现象

同一个 shell 里访问不同域名，结果差异很大：

```bash
curl -o /dev/null -w "%{http_code}" https://api.github.com          # 200，稳定
curl -o /dev/null -w "%{http_code}" https://github.com              # 000（超时/502）
curl -o /dev/null -w "%{http_code}" https://objects.githubusercontent.com  # 404（其实是通的，只是根路径没内容）
curl -o /dev/null -w "%{http_code}" https://codeload.github.com     # 000
curl -o /dev/null -w "%{http_code}" https://raw.githubusercontent.com  # 000
```

下载 GitHub Release 的 zip 直链时：

```
curl: (56) CONNECT tunnel failed, response 502
```

而同一时刻 `api.github.com` 完全正常。

## 原因

本机配置了本地 HTTP 代理：

```bash
http_proxy=http://127.0.0.1:50630
https_proxy=http://127.0.0.1:50630
```

代理对不同目标域名的连通性策略不同，**放行了 `api.github.com` 等 API 域名，但拦截或不稳定地处理 `github.com`、`codeload`、`raw`** 等站点域名。

关键区别在于：**502 响应带 `Retry-After: 1` 头**，说明是间歇性抖动而非永久封锁 —— 重试即可恢复。

注意：`000` 只是 curl 的「拿不到任何 HTTP 响应」代号，不代表「域名解析失败」，容易误判。

## 解法

### 1. 所有 curl 加自动重试

```bash
curl -s --max-time 25 --retry 4 --retry-delay 2 --retry-all-errors \
     -X POST "https://api.github.com/..." -d "..."
```

`--retry-all-errors` 关键：默认 `--retry` 只对「传输层错误」重试，遇到 502 这类 HTTP 错误码不会重试。

### 2. 绕过被拦截的下载域名，改用 API 资产端点

直链 `github.com/.../releases/download/...` 会 502，改成两步走：

```bash
# 第一步：从 API 拿到 asset id
ASSET_ID=$(curl -s "https://api.github.com/repos/cli/cli/releases/latest" \
  | grep -B5 '"gh_2.103.3_windows_amd64.zip"' \
  | grep -oE '"id": [0-9]+' | head -1 | grep -oE '[0-9]+')

# 第二步：直接下资产（会 302 到 objects.githubusercontent.com，这个域名是通的）
curl -sL --max-time 300 \
  -H "Accept: application/octet-stream" \
  -o gh.zip \
  "https://api.github.com/repos/cli/cli/releases/assets/$ASSET_ID"
```

### 3. winget 安装失败时走同样的路

```bash
winget install --id GitHub.cli --exact
# → 执行此命令时发生意外错误：InternetOpenUrl() failed. 0x80072efd
```

`winget` 用的 WinHTTP 通道和 curl 的通道不同，代理兼容性更差。**改为手工下载便携版 zip 解压使用**，反而更可控（不受 PATH、注册表、UAC 影响）。

### 4. 浏览器自动化也可能超时

chrome-devtools MCP 导航 github.com 同样会 `ERR_CONNECTION_TIMED_OUT`。导航时显式加大超时：

```json
{ "pageId": 3, "type": "url", "url": "https://github.com/...", "timeout": 90000 }
```

另外页面会偶发重启导致 **pageId 变化**，每步操作前先 `list_pages` 确认。

### 5. 大量小文件走 git 传输会卡死 —— 改用 Git Data API

同一个 `.git` 仓库，`git push` 传 7 个文件可以，但改成 GitHub API 通道后更可控、更快。
另外注意：云盘备份脚本 `cmsync.py upload` **不会排除 `.git/` 目录**（只有 `sweep` 才排除），
上传一个 git 仓库目录时会把 `.git` 里的几十个 object 文件也传一遍，导致极慢（实测 17 分钟未完成）。

**解法：先打包再上传单个文件。**

```bash
# 用 Python 打包（Windows Git Bash 没有 zip 命令）
python - <<'PYEOF'
import zipfile, os
base = r"C:\path\to\repo"
out  = r"C:\path\to\repo.zip"
files = ["README.md","LICENSE",".gitignore","notes/a.md"]
with zipfile.ZipFile(out,"w",zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(os.path.join(base, f.replace("/", os.sep)), f)
PYEOF
```

注意 `git archive` 打包的是**本地 HEAD**，不是远端最新状态。本地与远端不一致时（尤其是用 API 推上去的提交），
要用工作区文件直接打包，否则会漏文件。

## 排查清单

遇到「某个域名不通」时，按此顺序确认：

1. `env | grep -i proxy` —— 有没有走代理
2. `curl -sv <url>` —— 看 CONNECT 隧道阶段的具体错误（502 / 超时 / 证书错误）
3. 看响应头有没有 `Retry-After` —— 有就是间歇性，加 `--retry`
4. 换一个同类的备用域名试试（如 `api.` 前缀 vs 主站）—— 常能绕开策略差异
