# JFrog AI Catalog Workshop（学员）

本目录包含学员操作页面、启动器、初始化脚本、工具安装包和实验文件。

## 默认使用 GitHub Codespaces

第一页默认显示 Codespaces 指南：创建或打开 Codespace、配置 `JFROG_URL` / `JFROG_ACCESS_TOKEN` / `JF_PROJECT` 三个 Secrets、验证 Agent Guard，并配置本人 CLI Server。按页面完成全部验证勾选后进入 Lab 01。后续命令均在 Codespaces 终端执行。

三种语言由 `instructions/locales/zh-CN.json`、`instructions/locales/zh-TW.json`、`instructions/locales/en.json` 管理。页面截图位于 `instructions/images/`。

通过启动器打开页面时，页面会读取启动器进程中的 `JF_PROJECT`，自动填入 Lab 02 的项目名、Skills 仓库名（`<JF_PROJECT>-workshop-skills`）和策略名。使用启动器打印的链接或 Codespaces 的端口转发链接均可；此接口仅返回项目名和可选用户名，不返回 Token。修改环境变量后，需要重启启动器并刷新页面。直接以文件方式打开 HTML 无法读取 Codespaces 环境变量。

### 在 HTML 中切换准备方式

在 `instructions/workshop.html` 搜索 `SETUP VISIBILITY`，找到两个容器。`hidden` 是布尔属性：**有 hidden 就隐藏，删除 hidden 就显示**。不要使用 `hidden="false"`，它仍会隐藏。

默认显示 Codespaces、隐藏原本机页面：

```html
<div class="setup-variant" id="setup-local" hidden>
<div class="setup-variant" id="setup-codespaces">
```

恢复原本机页面、隐藏 Codespaces：

```html
<div class="setup-variant" id="setup-local">
<div class="setup-variant" id="setup-codespaces" hidden>
```

保存 HTML 并刷新页面即可。JavaScript 不会重置这两个容器的 hidden 属性。两者都显示时，必须完成两套验证；两者都隐藏时不能进入下一步。原本机页面的内容完整保留，切回后继续使用下面的启动器流程。

Codespaces 第一页的验证勾选是学员对终端结果的确认，网页不会远程读取 Token 或代执行安装命令。讲师需提前准备符合版本要求的 Node.js、JFrog CLI、jq 和 curl；如工具缺失，先补齐讲师环境。

## 本机准备（可选）

1. 领取讲师分配的平台 URL、本人账号与密码，对应关系为 `userN → projectN`。
2. 将完整学员文件夹复制到自己的电脑并解压。
3. macOS 双击 `start-workshop.command`；Windows 双击 `start-workshop.cmd`；Linux / WSL 在本目录执行 `bash start-workshop.sh`。
4. 启动器自动打开浏览器后，填写平台 URL、本人账号与密码，点击 **初始化环境**。
5. 保持启动器窗口打开；工具、JFrog CLI 配置和 `jf rt ping` 全部通过后，点击 **Next**。

安装包位于 `tools/<系统>-<架构>`。已安装且符合版本要求的工具直接跳过；需要安装时优先使用 tools 中的包，缺包则自动从官网下载、校验并缓存后安装。已有包校验失败会停止，请替换损坏文件后重试。无需在本目录运行账号创建脚本。

## 文件位置

- `instructions/workshop.html`：逐步操作页面；直接打开为静态预览，使用初始化按钮需通过启动器打开。
- `scripts/`：本机页面服务及各系统的初始化实现。
- `tools/`：本地安装包与自动下载缓存。
- `lab_dir/`：保留的实验文件。

初始化程序默认把运行工具和新实验目录放在 `~/.jfrog-workshop`，实际位置以页面成功结果为准。

官网下载使用固定版本：Node 24.22.0（含 npx）、JFrog CLI 2.127.0、jq 1.8.2、curl 8.23.0。网络不可用时，只要本地包齐全且已通过校验，仍可安装。

macOS 通常复用系统 curl。Windows 缺少 curl 时自动下载官方二进制包；macOS / Linux 如需安装 curl 且没有便携包，则下载官方源码构建，需要事先具备 C 编译器、make 和 OpenSSL 开发文件，缺少依赖时会明确报错。

初始化自动创建并切换到本人 CLI Server：例如 `user1` 对应 `workshop-user1`，用户名为 `user1`。认证信息仅由 JFrog CLI 存储，不写入网页日志或 workshop 配置。重新初始化需要再次输入密码。新开终端后可执行：

```sh
jf rt ping --server-id workshop-user1
```

成功返回 `OK`。初始化验证 CLI 配置及 `jf rt ping`。项目和 MCP 工具权限在后续实验中验证。`ping` 验证 Artifactory 连通性，不单独证明项目访问权限。

## Access Token 认证

初始化使用本人密码自动签发 24 小时有效的本人权限 Token，并通过 `jf c add --access-token-stdin` 保存到 CLI 认证配置，替换临时密码配置。随后验证本人项目查询与 ping。Token 不写入网页、日志或 workshop 文件。签发期间密码会暂存于 JFrog CLI 认证存储；失败时脚本清理临时配置。Token 到期后重新初始化即可。

前提：内部用户、未启用 MFA，平台允许使用密码创建 Token。平台不允许时，请由管理员调整 Token 策略或使用浏览器登录流程；程序不会降级为密码认证跳过验证。
