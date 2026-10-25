# JFrog MCP Server（Codespaces / GitHub Copilot CLI）

## 启动 JFrog 插件

在 Codespaces 终端执行：

```bash
copilot plugin list
copilot plugin enable jfrog
copilot
```

如果列表中没有 `jfrog`，先执行：

```bash
copilot plugin marketplace add jfrog/vscode-plugin
copilot plugin install jfrog@jfrog-agent-plugins
copilot plugin enable jfrog
```

## 检查 Agent Guard 可用的 MCP

```bash
npx --yes \
  --registry "https://releases.jfrog.io/artifactory/api/npm/coding-agents-npm/" \
  @jfrog/agent-guard \
  --list-available \
  --project "$JF_PROJECT"
```

VS Code 左侧的 MCP 面板是另一套配置机制，需要单独的 `.vscode/mcp.json`；它不会读取 Copilot CLI 的插件安装状态。
