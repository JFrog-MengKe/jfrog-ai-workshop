# 创建 Workshop 项目和用户

前提：讲师电脑已安装 `jf`（2.x ≥2.100.0）、`jq`、Python 3.9+，并已用平台管理员凭据配置好 JFrog CLI Server。

## 执行脚本

进入本目录，替换下面的 Server ID、平台地址和邮箱域名后，直接执行：

```bash
cd /Users/jingyil/work/jfrog/jfrog-ai-workshop/manager

bash init-users.sh \
  --server-id SERVER_ID \
  --platform-url https://YOUR-PLATFORM.jfrog.io \
  --email-domain YOUR-COMPANY.com \
  --count 10 \
  --apply
```

- `--server-id`：已配置的平台管理员 CLI Server ID。
- `--platform-url`：该 Server 对应的平台根地址，不含 `/artifactory`。
- `--email-domain`：讲师控制的有效邮箱域名，用户邮箱为 `userN@该域名`。
- `--count`：创建人数，默认 10；需要 3 人时改为 `3`。


## 执行结果

平台创建 `project1/user1` 到 `projec10/user10`。每个用户使用独立的 24 位随机密码，包含大小写字母、数字与符号，并成为对应项目的 **Project Admin**。

账号、密码、Project、角色及创建状态写入本目录的 **`workshop_users.xlsx`**。状态为 `READY` 表示创建和权限验证均已成功。

已有同名 Excel 会在正式创建前自动另存备份；若远端已有同名项目或用户，脚本停止，不修改既有账号。

若执行中断，保留自动生成的 `workshop_users.state.json`，使用原命令再加 `--resume` 恢复；遇到 `IN_FLIGHT` 状态先核对平台结果。Excel 和恢复记录包含密码，由讲师保管。

## 卸载本机工具

先关闭 OpenCode，在本目录执行：

```bash
bash uninstall-local-tools.sh
```

会卸载 OpenCode、JFrog CLI、jfcm，并删除专属配置、凭据、缓存、会话记录及 workshop 中的 OpenCode 配置；保留操作文档、账号 Excel 和创建状态记录。删除系统目录中的程序时需输入 macOS 管理员密码。


## Workshop 结束后清理平台

使用平台管理员的 Access Token CLI Server，在本目录执行。脚本仅操作 `workshop_users.state.json` 中记录为已创建的测试项目和用户，并核对平台 URL、项目 workshop 标记、仓库归属以及用户身份。

先预览（不执行删除）：

```bash
bash cleanup-workshop.sh \
  --server-id workshop \
  --platform-url https://alexwangtrial.jfrog.io
```

确认清单后执行。默认撤销这些项目的 MCP 准入、删除这些项目拥有的所有仓库及其中的 MCP/Skills 包和缓存；保留测试用户和项目：

```bash
bash cleanup-workshop.sh --server-id workshop --platform-url https://alexwangtrial.jfrog.io --apply
```

额外删除所有记录中的测试用户：

```bash
bash cleanup-workshop.sh user --server-id workshop --platform-url https://alexwangtrial.jfrog.io --apply
```

额外删除所有记录中的测试项目：

```bash
bash cleanup-workshop.sh project --server-id workshop --platform-url https://alexwangtrial.jfrog.io --apply
```

同时删除测试用户和项目：

```bash
bash cleanup-workshop.sh user project --server-id workshop --platform-url https://alexwangtrial.jfrog.io --apply
```

**仓库和仓库内容会永久删除。** 不加 `--apply` 始终只预览；`user`、`project` 参数不提供时，两者都保留。默认范围来自创建记录，不按模糊名称全平台删除，也不包含 `workshopadmin`。非 workshop 项目、无项目归属的公共仓库及共享给其他项目的仓库不清理；发现目标仓库跨项目共享或为 Federated 时停止。保留本地 Excel 和创建记录。

前提：`jf`、`jq`、Python 3.9+，以及已安装的 Agent Guard。脚本自动查找 PATH 或 npm 现有缓存中的 Agent Guard，不下载软件。找不到时使用 `--agent-guard /已安装路径/agent-guard`（也支持其 `bin/cli.js`）；删除失败时停止，不会自动更换服务器或猜测接口。平台 MCP 撤销使用官方登记的 unregister 接口；如果租户版本不支持该接口，需核对版本或在平台手动 Block，本次不会继续删仓库。

执行记录保存在 `cleanup-时间-进程号.jsonl`，不含密码或 Token。若中断，先核对已记录结果，再重新预览并执行。学员电脑上的 MCP/Skills 安装、下载目录和本地缓存无法由讲师平台脚本远程清除，需要在各学员电脑另行处理。Skills 在 Catalog 中的元数据可能随制品删除异步更新；脚本不清空平台级历史扫描与审计日志。
