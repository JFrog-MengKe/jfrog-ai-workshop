# JFrog AI Security Workshop

本 Workshop 透過 GitHub Codespaces 學習 JFrog AI Security 的基本流程：設定 MCP Server 及工具權限、使用客戶端 Agent 驗證授權效果、上傳並掃描 Skills，並透過 Package Resolution 攔截惡意元件安裝。

## 啟動操作說明

1. 使用本人的 GitHub 帳號 Fork 本儲存庫，並開啟儲存庫的 Codespace。
2. 在 Codespaces 終端啟動 Workshop：

   ```bash
   cd user
   ./start-workshop.sh
   ```

3. 腳本會啟動並開啟 Workshop HTML 操作說明；如果沒有自動開啟，請使用終端輸出的連結存取。
4. 開啟頁面後，先填寫 JPD 平台位址和使用者名稱，點擊「確定」；Project 會自動取得。
5. 按頁面順序設定儲存庫 Codespaces Secrets，並完成 Lab 01、Lab 02 和 Lab 03。
