# P139 新人的考驗 V0.1

以照片練習記住團體成員姓名的封閉式網頁遊戲。V0.1 提供登入、團體授權、人物與別名管理、照片自動壓縮、個人熟悉優先級、隨機循環問答及個人錯誤回饋。

## 安全與資料原則

- 遵循 SBI-P-SDS v3.3：RLS Always On → No Direct Table Access → RPC Only → Least Data → Least Privilege。
- P139 使用 P130 共用帳號；P139 保留自己的登入頁，不提供註冊、忘記密碼或密碼修改功能。
- P139 管理團體成員與角色。登入成功不代表有權限，必須被加入團體。
- 六張 P139 資料表均啟用 RLS，並撤銷 `anon` 與 `authenticated` 的直接資料表權限。前端資料操作只呼叫 P139 RPC。
- RPC 使用 P139 專屬函式、固定 `search_path`、`auth.uid()` 身分確認及團體角色檢查。具 `SECURITY DEFINER` 的函式只授予必要角色執行權。
- 照片放在非公開 `p139-private` Storage bucket。瀏覽器上傳的是先壓縮後的 JPEG；Storage policy 限定已授權成員讀取、管理者上傳或更換照片。
- 每位使用者只能修改與查看自己的優先級及答題錯誤回饋。一般使用者不會取得其他人的錯誤紀錄。
- ZIP 不含 `config.js`、Service Role Key 或真實照片。

## ZIP 內容

- `index.html`, `styles.css`, `app.js`：無建置步驟的前端。
- `config-sample.js`：Supabase URL、anon/publishable key 與 P130 網址範本。
- `Database/01_P139_Tables_Storage.sql`：P139 資料表、RLS 與私有照片 bucket。
- `Database/02_P139_Functions.sql`：P139 RPC 與 Storage 權限檢查。
- `Database/90_P139_Permissions.sql`：撤銷直接資料表存取並逐一授予 RPC 執行權。
- `Database/99_P139_HealthCheck.sql`：交付前權限與物件檢查。

## 安裝順序

### 1. 建立 P130 帳號

管理者與預計使用者先依機構流程在 P130 建立帳號並完成 Email 驗證。P139 不含註冊或密碼維護功能。

### 2. 安裝資料庫

在共用 Supabase Project 的 SQL Editor 依序貼上並執行：

1. `Database/01_P139_Tables_Storage.sql`
2. `Database/02_P139_Functions.sql`
3. `Database/90_P139_Permissions.sql`

這些檔案僅建立或調整 P139 命名的物件及 `p139-private` bucket；不變更其他 P 專案的資料表或全域權限。

### 3. 建立第一個團體與管理者

在 SQL Editor 執行以下呼叫，將名稱與 Email 換成實際資料。Email 必須已在 P130 註冊。呼叫由資料庫管理者在 SQL Editor 執行，不會開放給網站使用者。

```sql
SELECT public.p139_bootstrap_organization('慈濟大學經營管理學系', 'admin@example.com');
```

回傳的 `organization_id` 可留存作為管理紀錄。第一位管理者之後可在 P139「成員管理」加入已註冊的使用者，並指定一般成員或管理者角色。

### 4. 檢查資料庫

執行 `Database/99_P139_HealthCheck.sql`。每一列都應為 `PASS`。若出現 `FAIL`，先修正權限或缺少的 P139 物件，再部署前端。

### 5. 設定前端

1. 將 `config-sample.js` 複製成 `config.js`。
2. 填入 Supabase Project URL 和 anon/publishable key，以及 P130 Account Center 網址。
3. `config.js` 只放公開 anon/publishable key；絕不可填入 `service_role` key。
4. 將資料夾內容部署至靜態網站主機。未登入者只會看到登入頁；尚未加入團體的已登入者看不到人物資料。

P139 使用獨立 `storageKey: P139-auth`，且 V0.1 不持久保存登入 Session；重新載入頁面後需重新登入。

## 操作方式

### 管理者

登入後選擇團體，在「人物管理」輸入姓名與別名並上傳照片。瀏覽器會先將照片縮小至最長邊不超過 1200 px，再調整 JPEG 品質與尺寸，目標為 100 KB 以下；照片細節優先保留，個別圖片可能因內容差異略高於目標。上傳後可編輯資料或停用人物。

在「成員管理」輸入已註冊的 Email，將其加入目前團體。V0.1 不提供公開加入或自助註冊。

### 一般成員

在「我的優先級」為想熟悉的人物設定「最想熟悉」、「正在熟悉」或「之後再熟悉」。開始練習後，系統在該級別內隨機排列人物，完成一輪後重新洗牌，並盡量避免輪次交界連續出現相同人物。

玩家輸入姓名或管理者設定的別名。答錯時，系統顯示正確姓名、過去三筆個人錯誤答案；若答案符合名單內另一人的姓名或別名，另外提示人物混淆。答題資料保留在 P139，僅回傳給本人。

## V0.1 範圍與限制

- V0.1 為單一團體可運作的第一版骨架；管理者需由 SQL Editor 建立第一個團體，後續團體建立介面暫不提供。
- 人物資料採逐筆管理，尚未提供 Excel/CSV 批次匯入。
- 出題採自由回憶填答，不提供選擇題、排行榜或跨團體比較。
- 照片壓縮在瀏覽器完成；建議管理者使用清楚、適合辨識的正面照片。

## P-SDS v3.3 交付檢查

- [x] 所有 P139 資料表啟用 RLS。
- [x] 前端不直接讀寫 P139 資料表。
- [x] RPC 專案命名並驗證登入身分、團體成員資格與管理角色。
- [x] `anon` 不可呼叫管理或答題 RPC；`authenticated` 僅能執行列出的 P139 RPC。
- [x] 函式固定 `search_path`；不使用動態 SQL。
- [x] 照片 bucket 為 private，Storage policy 使用 P139 專屬命名與團體權限檢查。
- [x] ZIP 只含 `config-sample.js`，不含 `config.js`、Service Role Key 或使用者照片。
- [x] SQL 物件、政策、索引、RPC 均有 P139 命名；無 schema-wide GRANT/REVOKE 或 `ALTER DEFAULT PRIVILEGES`。
- [x] 提供 P139 permissions 與 health check SQL。

