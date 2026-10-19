# 工具安装包与下载缓存

初始化按以下顺序执行：

1. 工具已安装且符合版本要求：跳过。
2. 需要安装或升级：先查本目录下对应的系统和架构子目录，有包直接使用。
3. 没有包：自动从工具的官方来源下载到本目录，校验 SHA256 后安装。
4. 保留安装包、.sha256 和 checksums.json，供下次使用或分发给其他学员。

系统目录：darwin-arm64、darwin-x64、linux-arm64、linux-x64、win32-arm64、win32-x64。

包名：Node 为 node.tar.gz（Windows 为 node.zip）；OpenCode 为 opencode.zip 或 opencode.tar.gz，也支持直接放 opencode / opencode.exe；JFrog CLI 为 jf / jf.exe；jq 为 jq / jq.exe。curl 支持 curl/bin/curl 便携包；自动下载时 Windows 使用 curl.zip，Unix 使用 curl.tar.gz 官方源码。

官网下载包会核对上游 SHA256。手动放入的本地包优先使用 checksums.json 或同名 .sha256；如果都没有，记录本地文件的完整性哈希，并在安装时验证实际工具版本。本地包与已有校验记录不符时停止，不会覆盖后继续安装。

首次启动即使未安装 Node，也会先查本地包，缺少时从 Node 官网下载并保存。Unix 启动时需要系统已有 curl、wget 或 Python 3 之一作为 HTTPS 下载器；Windows 使用系统 PowerShell。

官方来源：

- [OpenCode Releases](https://github.com/anomalyco/opencode/releases)
- [Node.js](https://nodejs.org/download/release/)
- [JFrog CLI](https://docs.jfrog.com/integrations/docs/download-and-install-the-jfrog-cli)
- [jq Releases](https://github.com/jqlang/jq/releases)
- [curl](https://curl.se/download.html)

macOS 通常已有符合要求的 curl。Unix 自动构建 curl 源码需要 C 编译器、make 与 OpenSSL 开发文件；缺少构建依赖时请联系讲师准备便携包或依赖。
