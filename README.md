# JFrog AI Security Workshop

本 Workshop 透過 GitHub Codespaces 學習 JFrog AI Security 的基本流程：設定 MCP Server 及工具權限、使用客戶端 Agent 驗證授權效果、上傳並掃描 Skills，並透過 Package Resolution 攔截惡意元件安裝。

## 環境準備
### 00 JPD 信息
JPD Workshop 平台訪問地址和帳號信息由 JFrog 講師發放。信息包括：
- JPD URL
- User Name
- Password
- Project Key

### 01 Fork Workshop 儲存庫
開啟以下 Workshop 儲存庫，使用本人的 GitHub 帳號並 Fork：
<https://github.com/slash-l/jfrog-ai-workshop>

### 02 設定 Codespaces Secrets
在本人 Fork 儲存庫中開啟 `Settings → Secrets and variables → Codespaces`，點擊 **New repository secret**，新增以下三個 Repository secrets：

| Secret | 填寫內容 |
| --- | --- |
| `JFROG_ACCESS_TOKEN` | 本人的 JFrog Access Token，不要填寫登入密碼 |
| `JFROG_URL` | JPD 平台完整位址，例如 `https://your-company.jfrog.io` |
| `JF_PROJECT` | 講師提供的 Project Key，例如 `project1` |

需要平台完整位址時使用 `JFROG_URL`；Codespaces 啟動腳本會讓 JFrog 插件直接使用該完整位址，不需要另行配置其他平台 URL Secret。

### 03 啟動 GitHub Codespaces
1. 開啟 Fork 後的 Workshop 儲存庫，點擊 **Code**。
2. 切換到 **Codespaces** 分頁，點擊 **Create codespace on main**。
3. 在 Codespaces 終端啟動 Workshop：
```bash
cd user
./start-workshop.command
```
4. 腳本會啟動並開啟 Workshop HTML 操作說明；如果沒有自動開啟，請使用終端輸出的連結。
5. 完成後，依照 HTML 操作說明繼續 Workshop。接著按頁面順序完成 Lab 01、Lab 02 和 Lab 03。
