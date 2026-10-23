# P139 認臉記名 V0.8 — 三區管理者工作台

本 ZIP 是基於 GitHub P139 V0.7 現有 RPC 與資料表的**增量升級包**，不重建資料表、不刪除既有人物、群組或照片。

## 安裝
1. 備份 GitHub 現有 `index.html`、`app.js`、`styles.css`、`config.js`，以及 Supabase P139 schema。
2. 在 Supabase SQL Editor 執行 `Database/04_P139_V08_Admin_UI.sql`。若失敗，請勿覆蓋網站，先確認既有 V0.7 schema 欄位名稱。
3. 將 ZIP 的 `index.html`、`app.js`、`styles.css` 上傳取代 GitHub P139 對應檔案。
4. **保留原有 `config.js`**，不要用 `config-sample.js` 覆蓋它。
5. 清除瀏覽器快取，重新整理，測試公開練習與管理者功能。

## 三區功能
- 人員管理：建立、搜尋、編輯姓名、別名及照片，允許尚未分組。
- 群組管理：建立群組、重新命名；允許空群組。
- 群組成員管理：跨群組指派、認識優先級、移出群組；人物與照片不刪除。

## 資料安全
- 原有 RLS/RPC-only 策略維持；新增四個 RPC 僅授權 `authenticated` 執行，函式內再次驗證 P139 系統管理者。
- 原有 `p139-public` 公開照片 bucket 與 Storage 寫入 policy 沿用 V0.7；請確保照片適合公開。
- 不包含 `config.js`、Service Role Key、任何真實照片。
- 原有資料表與函式不會在本包中被刪除或清空。

## 相容性提醒
本包已參考 GitHub `bagilu/P139` 的 V0.7 `index.html`、`app.js`、`README.md` 與現有 SQL 函式名稱設計；因無法在此環境直接連線到使用中的 Supabase 專案進行整合測試，部署前務必先在測試環境驗證。SQL 若因既有資料表欄位差異失敗，交易會回滾，應先比對現有 schema 再修正。

## 版本
V0.8 — 三區管理者介面與卡內基引言（1936）。
