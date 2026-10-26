# CarForgeTax 開發交接

這份文件給新的 Cursor Agent 使用。請先讀它，再讀 `default.project.json` 與 `src`。內容以目前原始碼為準。

## 技術環境

- 遊戲名稱：CarForgeTax
- 場所檔：專案根目錄的 `car-forgetax.rbxl`。這是 Git 追蹤的遊戲檔，不要用 Rojo build 覆蓋它。
- Roblox Studio 已安裝 Rojo 插件。開發時開這個 rbxl，再用 Rojo 同步，不要把腳本直接存進 rbxl 當唯一來源。
- Rojo 7.7.1。Windows CLI 在 `%LOCALAPPDATA%\rojo\bin\rojo.exe`，已加入使用者 PATH。新終端機才看得到 `rojo`。
- 編輯器：Cursor。語言：Luau。
- Git 已初始化並連接 GitHub。不要重新 `git init`，不要自行 commit 或 push。
- 作業系統：Windows。

## 遊戲設計範圍

已寫進程式的只有車輛資料、抽車、記憶體車庫、測試錢包和免費強化。

目標裡還有、但原始碼完全沒有的系統：AI 自動競速、Boss、多人競賽、重生流程、正式經濟、UI、3D 車模。不要替這些系統發明規則或 API。

## Rojo 對應

`default.project.json`：

| 磁碟 | Roblox | 腳本類型 |
|---|---|---|
| `src/server` | `ServerScriptService` | `.lua` 為 ModuleScript，`.server.lua` 為 Script |
| `src/client` | `StarterPlayer.StarterPlayerScripts` | 目前是空資料夾 |
| `src/shared` | `ReplicatedStorage.Shared` | ModuleScript |

三個對應都設了 `$ignoreUnknownInstances: true`。Rojo 不會刪掉 Studio 裡已有、但檔案裡沒有的物件。刪掉一個 lua 檔也不會自動清掉 Studio 裡的同名實例。

在專案根目錄執行 `rojo serve`，再用 Studio 的 Rojo 插件 Connect。不要執行 `rojo build -o car-forgetax.rbxl`。

## 已完成模組

沒有全域單例。伺服器服務都要呼叫 `.new()`，測試必須自己建立實例。沒有 RemoteEvent，也沒有 `PlayerAdded` 啟動流程。

玩家鍵是非空字串，或大於 0 的整數。模組不接受 Player 實體。

### `src/shared/CarConfig.lua`

`ReplicatedStorage.Shared.CarConfig`

常數：

- `MinUpgradeLevel = 0`
- `MaxUpgradeLevel = 10`
- `MaxRebirthLevel = 10`
- `BasePower = 100`
- `PowerPerUpgradeLevel = 10`
- `SinglePullPrice = 500`
- `TestStartingGold = 50000`，只給測試發錢，不是正式經濟

品質由低到高：`Common`、`Uncommon`、`Rare`、`Epic`、`Legendary`。每筆有 `Id`、`DisplayName`、`ColorName`、`Weight`、`Bonus`、`AvailableFromRebirth`。五種品質的 `AvailableFromRebirth` 都是 0。

方法：

- `getQualities()`
- `isValidQuality(qualityId)`
- `getQuality(qualityId)`
- `sumWeights()`
- `getQualityBonus(qualityId)` → `bonus, reason`
- `getRebirthBonus(rebirthLevel)` → `bonus, reason`。只接受整數 0 到 10。
- `isValidUpgradeLevel(upgradeLevel)`
- `isInteger(value)`
- `calculatePower(upgradeLevel, qualityId, rebirthLevel)` → `power, reason`
- `rollQuality(rng)` → `qualityId, reason`。`rng` 必須有 `NextInteger(min, max)`，範圍含兩端。

### `src/shared/CarCatalog.lua`

`ReplicatedStorage.Shared.CarCatalog`

| ModelId | 顯示名稱 | 品質 | UnlockRebirth |
|---|---|---|---|
| `test_common_r0` | 普通測試車 | Common | 0 |
| `test_uncommon_r0` | 優良測試車 | Uncommon | 0 |
| `test_rare_r0` | 稀有測試車 | Rare | 0 |
| `test_epic_r0` | 史詩測試車 | Epic | 0 |
| `test_legendary_r0` | 傳說測試車 | Legendary | 0 |
| `test_common_r1` | 一階重生測試車 | Common | 1 |

`AbilityId` 與 `ModelAsset` 預留但目前是 nil。同品質車型沒有額外性能欄位。

方法：

- `getAll()`
- `getByModelId(modelId)`
- `getEligible(qualityId, rebirthLevel)`：該品質且 `UnlockRebirth <= rebirthLevel` 的車，依目錄順序。條件不合時回傳空陣列，不改抽其他品質。

### `src/shared/UpgradeConfig.lua`

`ReplicatedStorage.Shared.UpgradeConfig`

結果 id：`Destroy`、`Damage`、`Keep`、`Success`、`GreatSuccess`。顯示名稱是報廢、損壞、維持、成功、大成功。

保護券 id：`None`、`Basic`、`Advanced`。還沒有道具背包。

方法：

- `getOutcomes()`
- `isOutcome(outcomeId)`
- `getBand(upgradeLevel)` → `band, reason`
- `getWeights(upgradeLevel)` → `weights, reason`
- `sumWeights(upgradeLevel)` → `total, reason`
- `rollOutcome(upgradeLevel, rng)` → `outcomeId, reason`
- `applyProtection(rawOutcome, protectionId)` → `finalOutcome, consumed, reason`
- `nextLevel(currentLevel, outcomeId)` → `level, reason`。報廢回傳 `nil, "Destroyed"`。

`Basic` 只在原始結果為報廢時改成損壞，並標記消耗。`Advanced` 只在報廢時改成維持，並標記消耗。其他結果不改、不消耗。

### `src/shared/RandomSource.lua`

`RandomSource.new(seed?)`。Studio 裡用引擎 `Random`。沒有 `Random` 全域時才用 Park-Miller 後備產生器，供 Studio 外的 Luau 測試使用。

### `src/server/CarInventoryService.lua`

`ServerScriptService.CarInventoryService`。伺服器記憶體，關服後消失。沒有 DataStore。

`CarInventoryService.new(options?)`。可選 `catalog`、`now`、`rng`、`newId`。

`Reason`：`InvalidPlayer`、`UnknownModel`、`InvalidQuality`、`InvalidRebirth`、`LockedModel`、`IdCollision`、`UnknownCar`、`InvalidUpgradeLevel`、`InvalidRecord`、`DuplicateInstanceId`、`InvalidInstanceId`、`InvalidTimestamp`。

方法：

- `CreateCar(playerKey, modelId, acquiredRebirth)` → `car, reason`。等級固定為 0。InstanceId 只由服務產生，碰撞會重試，最多 8 次。
- `GetCar(playerKey, instanceId)` → `car, reason`
- `ListCars(playerKey)` → 凍結陣列, reason
- `SetUpgradeLevel(playerKey, instanceId, upgradeLevel)` → `car, reason`。只改該玩家自己的車，並換成新的凍結複本。
- `RemoveCar(playerKey, instanceId)` → `success, reason`。刪除後不回收 InstanceId。
- `ValidateCar(data)` → `success, reason`

車輛欄位只有 `InstanceId`、`ModelId`、`UpgradeLevel`、`AcquiredRebirth`、`CreatedAt`。回傳值都是凍結複本，修改回傳表不會改到庫存。

### `src/server/GoldWallet.lua`

`ServerScriptService.GoldWallet`。記憶體錢包，關服後餘額消失。`GoldWallet.new()` 的起始餘額是 0，不會自動發 50,000。

`Reason`：`InvalidPlayer`、`InvalidAmount`、`InvalidRequest`、`InsufficientGold`、`DuplicateDebit`、`TestGoldAlreadyGranted`。

方法：

- `GetBalance(playerKey)` → `balance, reason`
- `TryDebit(playerKey, amount, requestId)` → `success, reason`。同一個 `requestId` 不能扣第二次。
- `Credit(playerKey, amount)` → `success, reason`。伺服器退款或測試加值，沒有客戶端入口。
- `GrantTestGold(playerKey)` → `success, reason`。每位玩家只能領一次 `TestStartingGold`。

### `src/server/CarGachaService.lua`

`ServerScriptService.CarGachaService`

`CarGachaService.new(options)` 必填 `inventory` 與 `wallet`。可選 `config`、`catalog`、`rng`。

`Reason`：`InsufficientGold`、`NoUnlockedModel`、`InvalidRequest`、`InvalidRebirth`、`InvalidPlayer`、`InvalidPrice`、`RequestInProgress`、`GrantFailed`、`InternalError`。

`Pull(playerKey, rebirthLevel, requestId)`：

- `rebirthLevel` 必須由伺服器傳入，而且是大於等於 0 的整數。
- 價格讀 `CarConfig.SinglePullPrice`。金幣不足時不抽取、不扣款。
- 先抽品質。該品質沒有已解鎖車款時回傳 `NoUnlockedModel`，不改抽其他品質，也不扣款。
- 有車才扣款並 `CreateCar`。發車失敗會退款。
- 冪等鍵是 `playerKey .. "\0" .. requestId`。完成後重送同一請求會帶 `replayed = true`，不會再扣款或再發車。
- 扣款時傳給錢包的也是這組冪等鍵。
- 成功結果包含 `ok`、`requestId`、`quality`、`modelId`、`car`、`price`、`balance`、`charged = true`。

### `src/server/CarUpgradeService.lua`

`ServerScriptService.CarUpgradeService`

`CarUpgradeService.new(options)` 必填 `inventory`。可選 `catalog`、`rng`、`getServerProtection`。服務不讀錢包，也不扣金幣。

`getServerProtection(playerKey, instanceId)` 只能在伺服器建立服務時注入。`Upgrade` 不接受保護券、結果、機率或目標等級。多傳的參數會被忽略。

`Reason`：`InvalidPlayer`、`InvalidRequest`、`InvalidInstanceId`、`UnknownCar`、`InvalidUpgradeLevel`、`MaxUpgradeLevel`、`UpgradeInProgress`、`RequestInProgress`、`InvalidProtection`、`UpdateFailed`、`InternalError`。

`Upgrade(playerKey, instanceId, requestId)`：

- 只能強化該玩家 `GetCar` 查得到的車。別人的車回 `UnknownCar`。
- +10 回 `MaxUpgradeLevel`，不抽取。
- 報廢時 `RemoveCar`。結果的 `car` 與 `power` 為 nil，`removed = true`。
- 損壞為等級 -1，最低 0。維持不變。成功 +1。大成功 +2。最高 10。
- 等級有變才呼叫 `SetUpgradeLevel`。
- 性能使用 `CarConfig.calculatePower(新等級, 車款品質, car.AcquiredRebirth)`。目前沒有「目前重生階級」服務，所以用取得時的 `AcquiredRebirth`。
- 同一 `requestId` 只保留第一次結果。同一台車已在強化中時，另一個請求回 `UpgradeInProgress`，而且不寫入完成快取。
- 結果一律 `charged = false`。成功時還有 `rawOutcome`、`outcome`、`protection`、`protectionConsumed`、`previousLevel`、`upgradeLevel`、`power`。

### 測試腳本

- `src/server/CarSystemTests.lua`，`Tests.run()`
- `src/server/RunCarSystemTests.server.lua`
- `src/server/CarUpgradeTests.lua`，`Tests.run()`
- `src/server/RunCarUpgradeTests.server.lua`

兩個 `.server.lua` 只在 `RunService:IsStudio()` 時執行，並各自建立測試庫存。正式伺服器會直接 return。

`src/server/HelloWorld.server.lua` 只印 `Rojo sync successful`，是早期同步檢查，與玩法無關。

## 機率與性能

抽車權重，合計 100：

| 品質 | 名稱 | 顏色 | 權重 | 性能加成 |
|---|---|---|---|---|
| Common | 普通 | 白色 | 50 | 0 |
| Uncommon | 優良 | 綠色 | 30 | 8 |
| Rare | 稀有 | 藍色 | 15 | 20 |
| Epic | 史詩 | 紫色 | 4 | 38 |
| Legendary | 傳說 | 橘色 | 1 | 65 |

重生加成：R0=0、R1=12、R2=27、R3=45、R4=66、R5=90、R6=117、R7=147、R8=180、R9=216、R10=255。

`Power = 100 + (10 × UpgradeLevel) + QualityBonus + RebirthBonus`

強化權重，每一列合計 100。權重 0 的結果抽不到，機率也不會分給其他結果。

| 等級 | 報廢 | 損壞 | 維持 | 成功 | 大成功 |
|---|---|---|---|---|---|
| +0～+2 | 0 | 5 | 10 | 70 | 15 |
| +3～+4 | 3 | 12 | 20 | 55 | 10 |
| +5～+6 | 12 | 20 | 25 | 37 | 6 |
| +7 | 30 | 25 | 25 | 17 | 3 |
| +8 | 50 | 25 | 16 | 8 | 1 |
| +9 | 80 | 12 | 5 | 3 | 0 |
| +10 | 不能再強化 | | | | |

## 已通過的測試

2026-10-26，在已開啟的 `car-forgetax.rbxl` 按 Play。Studio Output 沒有這兩份測試腳本的 Luau 錯誤。停止 Play 只會回到 Edit，不會改磁碟檔。

抽車與車庫：11 PASS / 0 FAIL。一萬次模擬使用引擎隨機數，容差是 5 個標準差：普通 4949（±250）、優良 3040（±230）、稀有 1514（±179）、史詩 391（±98）、傳說 106（±50）。

強化：17 PASS / 0 FAIL。同一容差下，+8 報廢 5016、大成功 98；+9 報廢 8049、大成功 0。也覆蓋了 +0 損壞仍為 +0、+9 成功到 +10、+8 大成功到 +10、報廢移除、無效 ID、跨玩家拒絕、重複 requestId、重入拒絕、不扣金幣，以及 +4、R2、普通車性能 167。

Studio 場景另有既有警告：`rbxassetid://203785492` 的資源類型不符。不是這兩份測試腳本產生的。

## 尚未驗證的風險

- 沒有客戶端，也沒有真正的玩家操作流程。Playtest 只跑隔離測試。
- 一萬次模擬是統計容差，不是要求次數剛好等於期望值。
- 並行強化測試是同一條 Luau 執行緒裡的重入，不是多執行緒。服務本身不 yield。
- 冪等快取只存在該服務實例的記憶體。關服、換伺服器或重建服務後，舊 requestId 不再有效。
- 抽車的 `rebirthLevel` 由呼叫端傳入。目前沒有重生服務可證明這個數字屬實。
- 強化性能用的是 `AcquiredRebirth`，不是玩家當下的重生階級。
- `calculatePower` 拒絕 R11 以上與 +11 以上。
- 保護券規則有測試，但沒有道具、持有數量或消耗紀錄。
- `$ignoreUnknownInstances` 會讓檔案刪除後，Studio 裡的舊實例繼續留著。
- 磁碟上的 rbxl 在這次開發中沒有被寫入。Studio 裡看到的腳本來自 Rojo 同步。關掉 Studio 時若選擇不存檔，rbxl 仍不會包含這些腳本；下次仍應靠 Rojo 同步。

## 尚未實作

- DataStore 與任何跨伺服器存檔。
- 正式金幣經濟。不要把 `GrantTestGold` 接到客戶端。
- 抽車與強化的 Remote、UI。
- 保護券背包。
- 3D 模型。`ModelAsset` 仍是 nil。
- 特殊能力。`AbilityId` 仍是 nil。
- 強化以外的車輛培養。
- 重生流程。目前只有加成表、車款 `UnlockRebirth`，以及抽車參數。
- AI 自動競速、Boss、多人競賽。
- Robux 付款。

## 下一個任務

下一個任務是 3D 汽車模型與可視化車庫。

沿用 `CarCatalog`，不要另做一套車款表。模型參照應填進既有的 `ModelAsset`，不要把性能算進模型檔。`src/client` 目前是空的，對應 `StarterPlayerScripts`。現有 `default.project.json` 沒有模型資料夾；若要同步 `.rbxm` 或其他模型檔，必須明確加 Rojo 路徑，並繼續保持 `$ignoreUnknownInstances`，避免清掉場景裡已有的物件。

視覺化只能顯示伺服器車庫已有的車。等級、擁有者和性能仍由 `CarInventoryService` 與 `CarConfig.calculatePower` 決定。不要在客戶端抽車、強化或改等級。不要覆蓋 `car-forgetax.rbxl`。

## Git 與 Rojo 注意事項

- `.gitignore` 忽略 `*.rbxl.lock`、`*.rbxlx.lock`、`sourcemap.json` 和系統暫存檔。`*.rbxl` 與 `*.rbxlx` 要保留在版本庫。
- Studio 開啟場所時會產生 `car-forgetax.rbxl.lock`，這個檔不要提交。
- 免費強化系統的 5 個檔案已提交：`6d3e77d`，訊息為 `Implement free car upgrade system`。內容是修改 `src/server/CarInventoryService.lua`，以及新增 `src/shared/UpgradeConfig.lua`、`src/server/CarUpgradeService.lua`、`src/server/CarUpgradeTests.lua`、`src/server/RunCarUpgradeTests.server.lua`。`main` 與 `origin/main` 已同步。
- 目前唯一未追蹤的檔案是 `PROJECT_CONTEXT.md`。`car-forgetax.rbxl.lock` 已由 `.gitignore` 排除。不要自行 commit 或 push。
- 提交前不要把 `PROJECT_CONTEXT.md` 以外的生成檔加進去，除非使用者明確要求。
- 改完 Lua 後用已連線的 Rojo 同步。驗證玩法時在 Studio 按 Play，看 Output 的 `[CarForgeTax 測試]` 與 `[CarForgeTax 強化測試]`。
- 停止 Play 不會刪除 `src` 裡的檔案。
