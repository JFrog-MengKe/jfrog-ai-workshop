# JFrog MCP Server（Codespaces / GitHub Copilot CLI）

工作区级 `.vscode/mcp.json` 使用 Codespaces Secret `JFROG_URL` 生成 MCP 地址：

```json
{
  "servers": {
    "jfrog": {
      "type": "http",
      "url": "${env:JFROG_URL}/mcp"
    }
  }
}
```

`JFROG_URL` 必须是完整地址，例如 `https://yourcompany.jfrog.io`。不要使用旧的 `jfrog_platform_url`，也不要把地址写成 `https://mcp`。

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
