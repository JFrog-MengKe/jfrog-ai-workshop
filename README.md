# JFrog AI Catalog Workshop

- [管理员操作](manager/README.md)：执行 `manager/init-users.sh`，创建 Project / User 并导出账号 Excel。
- [用户操作](user/README.md)：启动本机页面，点击“初始化环境”，按步骤完成实验。

管理员内容在 `manager`，用户内容在 `user`。现场只分发用户目录。

在 HTML 中搜索 SETUP VISIBILITY，即可切换：
显示 Codespaces：
```
<div class="setup-variant" id="setup-local" hidden>
<div class="setup-variant" id="setup-codespaces">
```

显示 OpenCode 配置：
```
<div class="setup-variant" id="setup-local">
<div class="setup-variant" id="setup-codespaces" hidden>
```
