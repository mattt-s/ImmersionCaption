# GitHub Release 发布指南

本文记录 ImmersionCaption 发布安装包的实际流程，供维护者及后续 AI coding agent 使用。适用于本地构建 `.pkg`、`.dmg` 和 `.sha256`，通过 GitHub CLI 创建草稿、验证附件后发布。应用的构建和打包由现有脚本负责，当前没有自动发布的 GitHub Actions 工作流。

当前仓库为 `mattt-s/ImmersionCaption`。已发布的 [v0.7.1](https://github.com/mattt-s/ImmersionCaption/releases/tag/v0.7.1) 对应提交 `b58ce7930e7e1391e55b8953a2747996ee8f58eb`，应用构建号为 11。**不要原样重跑流程来覆盖这个已发布版本。** 以下变量应从下一次实际准备发布的构建中获取；纯文档变更无需重新发布安装包。

## 1. 确认范围、版本和源提交

用户明确要求发布 Release 时，可以完成整个流程，无需在最后重复征求同意。仅要求本地打包时，生成本地产物即可。准备发布之前先检查现有会话授权、仓库及已有版本，保留用户工作，不改变仓库可见性。

在项目根目录、同一个 Bash 终端中执行下文命令。每一步失败后先处理原因，再继续；不要继续发布未通过验证的附件。

```bash
set -euo pipefail
git status --short --branch
git remote get-url origin
git log -1 --oneline
```

若应用功能、二进制或签名方式发生变化，先在 [Info.plist](../Resources/Info.plist) 更新合适的 `CFBundleShortVersionString` 和递增的 `CFBundleVersion`，同步中英文 README、架构及验证记录。完成与变更相关的检查，提交并推送源代码。发布用的提交必须已存在于远端；不要使用含未提交代码的构建或让标签指向与安装包不一致的提交。

运行时变更按 [AGENTS.md](../AGENTS.md) 执行测试及构建要求；涉及窗口启动时执行启动检查。纯文档变更检查链接、示例命令和格式即可，不需重建安装包。真实音频、系统权限及完整安装体验只记录实际完成的验证。

## 2. 准备 CLI 和 GitHub API 授权

先检查当前会话的连接器是否具备创建 Release、上传二进制附件的能力。此次发布时连接器没有这些操作，因此使用官方 GitHub CLI。**Git 的 SSH 推送成功，不代表已获得 Release API 的授权。**

```bash
if command -v gh >/dev/null 2>&1; then
    GH_BIN="$(command -v gh)"
elif [[ -x /tmp/immersion-release-tools/gh ]]; then
    GH_BIN=/tmp/immersion-release-tools/gh
else
    echo '请先准备官方 GitHub CLI，再重新执行本步骤。' >&2
    exit 1
fi
"$GH_BIN" --version
if ! "$GH_BIN" auth status; then
    printf '%s\n' '当前 CLI 尚未完成有效授权，请执行下方登录流程。'
fi
```

`/tmp/immersion-release-tools/gh` 只是此次会话使用的临时路径，可能已被清理。若没有 CLI，从 [GitHub CLI 官方安装入口](https://cli.github.com/)或[官方 Release](https://github.com/cli/cli/releases/latest)获取匹配本机架构的版本，并核对同一版本官方 checksums 文件，再使用解压后的可执行文件；设置 GH_BIN 为其实际路径。此次使用并验证的是 2.103.3，不要求未来固定使用该版本。若采用 Homebrew 安装，使用本机已配置的 Homebrew。CLI 是发布工具，不是应用的运行依赖。

仅在登录缺失或失效时启动授权：

```bash
"$GH_BIN" auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key
```

命令会在 **Mac 终端**生成一次性设备验证码。用户在 [github.com/login/device](https://github.com/login/device) 输入该码并授权 GitHub CLI；这里的 device 指运行命令的设备，**不是等手机 GitHub App 推送验证码**。Agent 将当次代码和官方页面告知用户，等待实际授权成功；不得替用户完成登录确认。过期后重新启动流程，不复用旧码，也不把验证码写入项目文档。

此命令保留 SSH 协议并跳过生成／上传 SSH 密钥。此次登录凭据由系统钥匙串保存。后续优先复用有效授权；不要求用户在聊天中提供密码或 token，不执行 `gh auth token`、`--show-token` 或 shell 跟踪来记录凭据，不使用 `--insecure-storage`。如果凭据存储回退为明文，明确说明实际状态，不声称已安全存入钥匙串。下载 CLI 或访问 API 时保留 TLS 校验；此次独立 Python 的证书链检查失败后，改用系统 `/usr/bin/curl` 成功访问，没有关闭证书校验。

检查目标仓库和权限：

```bash
RELEASE_REPO=mattt-s/ImmersionCaption
"$GH_BIN" api user --jq .login
"$GH_BIN" api "repos/$RELEASE_REPO" \
    --jq '{private: .private, default_branch: .default_branch, can_push: .permissions.push}'
"$GH_BIN" release list --repo "$RELEASE_REPO" --limit 20 \
    --json tagName,name,isDraft,isPrerelease,isLatest
```

确认登录账号对该仓库有写入权限。`release list --json` 不支持 `url` 字段；需要 URL 时读取 Release API 的 `html_url` 或使用 `release view`。不要因查不到私有仓库就认定仓库不存在，先核对账号和访问权限。

## 3. 构建与本地验证

```bash
scripts/package-app.sh
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/ImmersionCaption.app/Contents/Info.plist)"
RELEASE_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' build/ImmersionCaption.app/Contents/Info.plist)"
RELEASE_ARCHS="$(lipo -archs build/ImmersionCaption.app/Contents/MacOS/ImmersionCaption)"
case "$RELEASE_ARCHS" in
    arm64|x86_64) RELEASE_ARCH_LABEL="$RELEASE_ARCHS" ;;
    'arm64 x86_64'|'x86_64 arm64') RELEASE_ARCH_LABEL=universal ;;
    *) echo "不支持的架构：$RELEASE_ARCHS" >&2; exit 1 ;;
esac
RELEASE_TAG="v$RELEASE_VERSION"
RELEASE_COMMIT="$(git rev-parse HEAD)"
RELEASE_BASE="ImmersionCaption-$RELEASE_VERSION-$RELEASE_ARCH_LABEL"
git status --short
git ls-remote origin refs/heads/main
git ls-remote --tags origin "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}"
(cd build && shasum -a 256 -c "$RELEASE_BASE.sha256")
```

确认工作树仍干净、远端 main 包含准确发布提交，版本／构建号／架构与产物一致。已有标签必须指向预期提交；带注释的标签应检查解引用后的提交。已有同版本 Release 时先检查其草稿／已发布状态及附件；不要自动删除、移动标签或覆盖已发布附件。需修正已发布二进制时发布新版本，已启用不可变 Release 的仓库尤其如此。

[package-app.sh](../scripts/package-app.sh) 会重新执行 release build，生成三份文件：

| 产物 | 内容 |
| --- | --- |
| build/$RELEASE_BASE.pkg | 固定安装到 /Applications/ImmersionCaption.app 的原生安装器。 |
| build/$RELEASE_BASE.dmg | App、Applications 符号链接和中英文 INSTALL.txt。 |
| build/$RELEASE_BASE.sha256 | PKG 和 DMG 的 SHA-256 校验值。 |

上传前按 AGENTS.md 检查：展开 PKG（`pkgutil --expand-full`）核对唯一 App 载荷、无安装脚本、禁止重定位、版本及系统／架构要求；使用 `codesign --verify --strict` 验证 App 文件完整性并与原始 App 比较。对 DMG 执行 `hdiutil verify`，临时只读挂载，比较 App 文件、检查 Applications 链接及安装说明，随后卸载。临时目录使用 `mktemp`，不覆盖现有安装或更改音频设备／隐私设置。详细的已完成验证参见 [VALIDATION.md](VALIDATION.md)。

签名和公证要如实记录：默认是 ad-hoc App、未签名 PKG、未经公证。`codesign --verify` 成功不代表 Gatekeeper 信任；本机构建可打开也不证明浏览器下载后的副本能通过首次检查。可使用 `spctl --assess --type execute` / `--type install` 评估，但完整分发验收仍需真实下载、安装和首次启动测试。不得为验证而关闭 Gatekeeper 或删除隔离标记。已配置 CODE_SIGN_IDENTITY / INSTALLER_SIGN_IDENTITY 也不等于已完成 Apple 公证。

## 4. 编写说明并创建草稿

先准备中英文说明文件 `build/RELEASE_NOTES.md`，包含此次变更、系统／架构要求、设备端语言资源、安装步骤、三个附件、签名／公证状态及已知限制。测试数量只引用本次完成或明确标记为历史的验证记录。`build/` 被 Git 忽略，发布附件不提交到源码仓库。

确认 notes 文件和三个产物均已准备好，再执行以下会写入 GitHub 的命令：

```bash
"$GH_BIN" release create "$RELEASE_TAG" \
    "build/$RELEASE_BASE.pkg" \
    "build/$RELEASE_BASE.dmg" \
    "build/$RELEASE_BASE.sha256" \
    --repo "$RELEASE_REPO" \
    --target "$RELEASE_COMMIT" \
    --title "ImmersionCaption $RELEASE_TAG" \
    --notes-file build/RELEASE_NOTES.md \
    --draft
```

使用完整提交 SHA 的 `--target`，避免默认分支在上传期间前进而导致来源不一致。多行说明通过文件传入，保留真实换行，不在 shell 中拼接。当前流程面向正常版本；若用户要求预发布，在草稿中设置 `--prerelease`，且不要将它标为 Latest。创建草稿或部分上传失败时，先检查远端实际状态；恢复同一草稿，不盲目再次创建或用 `--clobber` 替换已有内容。

## 5. 检查草稿附件，再发布

以下步骤仅验证草稿，不改变远端状态：

```bash
RELEASE_METADATA="$(mktemp /tmp/immersion-release-metadata.XXXXXX)"
"$GH_BIN" api "repos/$RELEASE_REPO/releases/tags/$RELEASE_TAG" > "$RELEASE_METADATA"
python3 - "$RELEASE_METADATA" "$RELEASE_BASE" "$RELEASE_TAG" "$RELEASE_COMMIT" <<'PY'
from pathlib import Path
import hashlib, json, sys

metadata, base, tag, commit = sys.argv[1:]
release = json.loads(Path(metadata).read_text())
assert release['draft'] is True, 'Expected an unpublished draft'
assert release['tag_name'] == tag
assert release['target_commitish'] == commit
expected = {f'{base}.{ext}' for ext in ('pkg', 'dmg', 'sha256')}
assert {asset['name'] for asset in release['assets']} == expected
for asset in release['assets']:
    local = Path('build') / asset['name']
    assert asset['state'] == 'uploaded'
    assert asset['size'] == local.stat().st_size
    digest = 'sha256:' + hashlib.sha256(local.read_bytes()).hexdigest()
    assert asset.get('digest') == digest, f"Digest mismatch: {asset['name']}"
print('Draft target, names, uploaded states, sizes, and SHA-256 digests match.')
PY
```

如果服务端没有返回 digest，不能跳过校验或假定上传正确；将草稿附件下载到新的临时目录，与本地原件逐一比较后再继续。SHA-256 文件本身也必须与本地原件一致。

上述检查通过，且用户已授权发布时，正式发布正常版本并标记 Latest：

```bash
"$GH_BIN" release edit "$RELEASE_TAG" --repo "$RELEASE_REPO" --draft=false --latest
```

若当前会话已有明确发布授权，无需再问一次。若尚未得到发布授权，先完成可审阅的产物、说明及验证，再说明缺少的授权。发布成功后不要为了补充文档而重新打包、替换同版本附件或移动标签。

## 6. 验证发布结果和下载文件

```bash
"$GH_BIN" api "repos/$RELEASE_REPO/releases/tags/$RELEASE_TAG" \
    --jq '{tag: .tag_name, draft: .draft, prerelease: .prerelease, published_at: .published_at, url: .html_url}'
"$GH_BIN" api "repos/$RELEASE_REPO/releases/latest" --jq .tag_name
"$GH_BIN" api "repos/$RELEASE_REPO/git/ref/tags/$RELEASE_TAG" \
    --jq '{type: .object.type, sha: .object.sha}'
RELEASE_DOWNLOAD_DIR="$(mktemp -d /tmp/immersion-release-download.XXXXXX)"
"$GH_BIN" release download "$RELEASE_TAG" --repo "$RELEASE_REPO" \
    --pattern "$RELEASE_BASE.*" --dir "$RELEASE_DOWNLOAD_DIR"
for extension in pkg dmg sha256; do
    cmp "build/$RELEASE_BASE.$extension" "$RELEASE_DOWNLOAD_DIR/$RELEASE_BASE.$extension"
done
(cd "$RELEASE_DOWNLOAD_DIR" && shasum -a 256 -c "$RELEASE_BASE.sha256")
```

应确认 `draft=false`、正常版本 `prerelease=false`、发布时间存在、Latest 指向该版本，以及远端标签的最终提交等于 RELEASE_COMMIT。若标签类型为 tag，继续读取对应 tag 对象并解引用至 commit，不能直接比较标签对象 SHA 与提交 SHA。预发布或历史版本不执行／要求 Latest 检查。

本仓库目前公开。正式发布后还应使用不带 Authorization 的系统 `curl --fail --location` 下载三个 `browser_download_url`，与本地原件比较，证明用户能公开下载。若仓库是私有的，使用获授权的 CLI 下载，并明确其访问限制，不改变可见性。下载校验通过不等于安装或真实音频测试通过。

## 7. 同步文档与交付

在 [README.md](../README.md) 和 [README.zh-CN.md](../README.zh-CN.md) 同时更新版本及下载入口，链接到已发布的 Release 和三个附件；不要把未发布版本写成已经可下载。将版本／构建号、发布源提交、Release URL、附件和实际验证结果写入 [VALIDATION.md](VALIDATION.md)。检查 Markdown 本地链接及 `git diff --check`，提交并推送文档；文档提交可以晚于 Release 标签，不能因此移动原标签。

最终回复给用户 Release URL、三个附件情况、目标系统／架构及实际签名限制。若有步骤受阻，明确说明停在本地打包、草稿上传还是正式发布；仅上传成功时不能宣称已正式发布。

## 官方参考

- [GitHub CLI：浏览器授权](https://cli.github.com/manual/gh_auth_login)
- [GitHub CLI：创建 Release、target、草稿及不可变 Release](https://cli.github.com/manual/gh_release_create)
- [GitHub CLI：编辑／发布草稿](https://cli.github.com/manual/gh_release_edit)
- [GitHub CLI：下载附件](https://cli.github.com/manual/gh_release_download)
- [GitHub REST API：Release 附件及 digest](https://docs.github.com/en/rest/releases/assets)
- [Apple：在 Mac 上安全地打开 App](https://support.apple.com/zh-cn/102445)
