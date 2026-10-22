# P139 認臉記名（Faces & Names）V0.7

**認臉記名｜Faces & Names**

看見面孔，記住名字。*Recognize faces. Remember names.*

用照片練習記住群組成員姓名。玩家免登入；系統管理者登入後建立教師人物資料及群組。綠色標語區以中文呈現卡內基人際互動原則：「記住名字」。

## 品牌與首頁

正式名稱為「認臉記名｜Faces & Names」。綠色標語區只呈現中文卡內基原則與說明；網站名稱仍保留中英文。

## V0.7 更新

- 綠色標語區只顯示中文：「卡內基人際互動原則：『記住名字』」及「用心記住名字，讓每一次相遇更有溫度。」
- 群組載入失敗時顯示 Supabase 錯誤訊息與代碼。
- 移除舊版照片搬移功能及其 Storage 讀取政策。
- 採「先建人物資料，再加入群組」流程；同一教師可加入多個群組，姓名、別名與照片共用，各群組的優先級與啟用狀態分開管理。
- 新建的人物資料可先留在名冊，尚未指定群組。
- 管理者登入後一定會看到「建立群組」區；若尚未有系統管理者權限，畫面會指引執行管理者修復 SQL。

## 本版設計

- 公開練習：玩家免登入選擇群組及認識優先級，系統隨機循環出題。
- 管理者專用：`bagilu@gmail.com` 為第一位系統管理者；登入後可建立群組、教師人物資料，並將人物加入群組。
- 公開資料：此版本的群組、姓名、別名和照片都供公開學習使用。請只加入適合公開使用的人物資料及照片。
- 個人紀錄：練習次數和錯誤答案存在玩家自己的瀏覽器 `localStorage`，不會上傳到 Supabase。清除瀏覽器資料或使用不同裝置時，紀錄不會保留。
- 照片：瀏覽器先縮小至最長邊 1200 px，壓縮目標約 100 KB，照片檔案存入 Supabase Storage 的公開 `p139-public` bucket；人物資料表 `TblP139Person` 的 `photo_path` 欄位只存物件路徑。新人物路徑為 `<人物 UUID>/<人物 UUID>.jpg`。
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
- `Database/02_P139_Functions.sql`：公開練習 RPC、人物名冊／群組管理 RPC 與照片授權檢查。
- `Database/90_P139_Permissions.sql`：撤銷資料表直接權限並設定逐一 RPC 權限。
- `Database/03_P139_Admin_Repair.sql`：既有安裝的第一位管理者權限修復（選擇性，僅用於 `bagilu@gmail.com`）。
- `Database/99_P139_HealthCheck.sql`：交付權限檢查。

## 安裝順序

### 1. 建立管理者帳號

請先在 P130 註冊 `bagilu@gmail.com` 並完成 Email 驗證。管理者帳號只用於維護群組及名單；一般玩家不需註冊或登入。

### 2. 安裝資料庫

在共用 Supabase Project 的 SQL Editor 依序執行：

1. `Database/01_P139_Tables_Storage.sql`
2. `Database/02_P139_Functions.sql`
3. `Database/90_P139_Permissions.sql`

若已安裝過先前版本，請用本版檔案重新執行這三份 SQL。既有人物資料及群組關聯會保留；人物表現在允許尚未加入群組的人物。舊照片搬移功能已移除，若舊照片無法顯示，請重新建立人物資料並上傳照片。此版本不會刪除舊資料或私有 bucket 中的物件；若要清空既有 P139 名冊，請先備份並另行確認清理範圍。本版不會修改共用 P130 帳號資料。

### 3. 建立第一個群組與系統管理者

在 Supabase SQL Editor 執行以下指令。它會建立「行政主管群組」，並指定 `bagilu@gmail.com` 為系統管理者和該群組管理者：

```sql
SELECT public.p139_bootstrap_organization('行政主管群組', 'bagilu@gmail.com');
```

此初始化只能執行一次。若已建立過群組或系統管理者，請勿重跑。若登入後看不到新增群組表單，請在 SQL Editor 執行 `Database/03_P139_Admin_Repair.sql`。成功後重新登入。

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

點選「系統管理者入口」並登入。先建立教師人物資料（姓名、別名、照片），再選擇目前群組、設定該群組的認識優先級並加入。之後可在其他群組重複指派同一人物，不必重傳照片。人物姓名、別名與照片共用，各群組優先級及啟用狀態獨立。人物資料與照片會公開給所有玩家練習。

## SBI-P-SDS v3.4 交付檢查

- [x] P139 資料表啟用 RLS，前端無直接資料表權限。
- [x] 公開練習僅能呼叫已列出的公開 RPC；匿名使用者不能執行管理 RPC。
- [x] 建立群組 RPC 驗證系統管理者資格；人物管理 RPC 驗證群組管理者資格。
- [x] 函式固定 `search_path`，設定逐函式 `GRANT`／`REVOKE`。
- [x] 照片公開讀取、管理者登入後才可新增或更新；上傳前瀏覽器端壓縮。
- [x] 個人錯誤紀錄不送到伺服器，只保存在瀏覽器本機。
- [x] ZIP 僅含 `config-sample.js`，不含實際設定檔、Service Role Key 或人物照片。
- [x] 提供 P139 permissions 與 health check SQL。
- [x] 群組關聯表啟用 RLS 並禁止前端直接存取。
- [x] 教師跨群組指派僅由系統管理者 RPC 執行。
- [x] 不再提供舊版私有照片搬移；P139 不建立舊私有 bucket 的讀取政策。
