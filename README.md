# P139 認臉記名（Faces & Names）V0.4

**認臉記名｜Faces & Names**

看見面孔，記住名字。*Recognize faces. Remember names.*

用照片練習記住群組成員姓名。玩家免登入；系統管理者登入後建立群組並維護公開學習名單。首頁以中英文呈現 Dale Carnegie 人際互動原則：「記住一個人的名字」／“Remember a person's name.”

## V0.3 名稱與首頁更新

## V0.4 修正

- 群組載入失敗時顯示 Supabase 錯誤訊息與錯誤代碼，並提示可能需要重新執行 SQL。
- 加入管理者專用「搬移本群組舊照片」功能，透過 Supabase Storage API 將 V0.1 私有照片複製到公開 bucket；不會刪除舊檔。
- 資料庫保留僅供群組管理者讀取舊照片的政策，以支援遷移。

## 本版設計

- 公開練習：玩家免登入選擇群組及認識優先級，系統隨機循環出題。
- 管理者專用：`bagilu@gmail.com` 為第一位系統管理者；登入後可建立群組，管理姓名、別名、照片及認識優先級。
- 公開資料：此版本的群組、姓名、別名和照片都供公開學習使用。請只加入適合公開使用的人物資料及照片。
- 個人紀錄：練習次數和錯誤答案存在玩家自己的瀏覽器 `localStorage`，不會上傳到 Supabase。清除瀏覽器資料或使用不同裝置時，紀錄不會保留。
- 照片：瀏覽器先縮小至最長邊 1200 px，壓縮目標約 100 KB，存入公開讀取的 `p139-public` bucket。
- 群組範例：行政主管群組、各系教師群組。每個群組有自己的名單。
- 本版不含學生班級私密群組。未來若納入學生照片，需增加私人群組、成員授權及私有照片存取控制，不能直接使用本版公開群組。

## 安全與資料原則

- 遵循 SBI-P-SDS v3.4：RLS Always On → No Direct Table Access → RPC Only → Least Data → Least Privilege。
- 玩家使用 anon key 呼叫三個唯讀／答案比對 RPC；`anon` 無法直接讀寫任何 P139 資料表，也不能上傳、更換或刪除照片。
- 管理者使用 P130 共用帳號。只有 `TblP139SystemAdmin` 中的系統管理者能建立群組；群組管理 RPC 另檢查管理者資格。
- 關係資料表皆啟用 RLS，前端資料庫操作使用 P139 RPC。照片設為公開讀取是本版明確的產品設定，照片修改仍須管理者登入。
- ZIP 不含 `config.js`、Service Role Key 或真實照片。

## ZIP 內容

- `index.html`, `styles.css`, `app.js`：公開練習介面與管理者介面。
- `config-sample.js`：Supabase URL、anon/publishable key 與 P130 網址範本。
- `Database/01_P139_Tables_Storage.sql`：P139 資料表、RLS 與公開照片 bucket。
- `Database/02_P139_Functions.sql`：公開練習 RPC、管理 RPC 與照片授權檢查。
- `Database/90_P139_Permissions.sql`：撤銷資料表直接權限並設定逐一 RPC 權限。
- `Database/99_P139_HealthCheck.sql`：交付權限檢查。

## 安裝順序

### 1. 建立管理者帳號

請先在 P130 註冊 `bagilu@gmail.com` 並完成 Email 驗證。管理者帳號只用於維護群組及名單；一般玩家不需註冊或登入。

### 2. 安裝資料庫

在共用 Supabase Project 的 SQL Editor 依序執行：

1. `Database/01_P139_Tables_Storage.sql`
2. `Database/02_P139_Functions.sql`
3. `Database/90_P139_Permissions.sql`

若已安裝過先前版本，請用本版檔案重新執行這三份 SQL，以確保公開練習 RPC、權限及照片 bucket 政策更新。原有人物資料不會刪除。若照片仍在 V0.1 的 `p139-private`，請以管理者登入、選取群組，按「搬移本群組舊照片」；只有確認適合公開的群組才執行。檔案會複製至 `p139-public`，原私有檔案保留。V0.2/V0.3 新增的照片本來就在 `p139-public`，不需要搬移。

### 3. 建立第一個群組與系統管理者

在 Supabase SQL Editor 執行以下指令。它會建立「行政主管群組」，並指定 `bagilu@gmail.com` 為系統管理者和該群組管理者：

```sql
SELECT public.p139_bootstrap_organization('行政主管群組', 'bagilu@gmail.com');
```

此初始化只能執行一次。若 V0.1 已建立群組，且 `bagilu@gmail.com` 已是該群組管理者，這個呼叫會把該帳號升級為系統管理者，不會重複建立群組。成功後，請以 `bagilu@gmail.com` 的 P130 帳號登入 P139 管理區，再建立「各系教師群組」等其他群組。管理者會自動取得新群組的管理權限。

### 4. 檢查資料庫

執行 `Database/99_P139_HealthCheck.sql`，每一列都應為 `PASS`。若有 `FAIL`，先檢查資料表、RPC 權限與 `p139-public` bucket 設定。

### 5. 設定網站

1. 將 `config-sample.js` 複製為 `config.js`。
2. 填入 Supabase Project URL、anon/publishable key 和 P130 Account Center 網址。
3. 只能在網站放 anon/publishable key，絕不可放 `service_role` key。
4. 將資料夾內容部署到靜態網站主機。

## 使用方式

### 玩家

開啟網站後選擇群組和認識優先級即可開始。每輪盡量不重複，完成一輪再洗牌。錯答會顯示正確姓名；如果答成同群組內另一人的姓名，會提示人物混淆。此前錯誤及答題統計保留在同一瀏覽器的本機資料。

### 系統管理者

點選「系統管理者入口」並登入。系統管理者可新增群組；選擇群組後可新增、編輯或停用人物，設定姓名、別名、照片與認識優先級。照片及名單會公開給所有玩家練習。

## SBI-P-SDS v3.4 交付檢查

- [x] P139 資料表啟用 RLS，前端無直接資料表權限。
- [x] 公開練習僅能呼叫已列出的公開 RPC；匿名使用者不能執行管理 RPC。
- [x] 建立群組 RPC 驗證系統管理者資格；人物管理 RPC 驗證群組管理者資格。
- [x] 函式固定 `search_path`，設定逐函式 `GRANT`／`REVOKE`。
- [x] 照片公開讀取、管理者登入後才可新增或更新；上傳前瀏覽器端壓縮。
- [x] 個人錯誤紀錄不送到伺服器，只保存在瀏覽器本機。
- [x] ZIP 僅含 `config-sample.js`，不含實際設定檔、Service Role Key 或人物照片。
- [x] 提供 P139 permissions 與 health check SQL。
- [x] 舊版私有照片只允許群組管理者讀取遷移；匿名使用者不能讀取舊私有 bucket。
