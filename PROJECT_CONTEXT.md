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

已完成並可在 Studio 遊玩的是概念原型，不是正式營運版本。關服後車庫與金幣會消失。

已完成：

- 車輛資料、抽車機率、記憶體車庫、測試錢包、免費強化。
- 程式生成的 3D 玩具車與概念場景。
- 車庫、抽車、強化、單場競速與 Boss 演算法都已接到既有服務。
- 單場競速：玩家按一次，伺服器跑完一場、發一次測試金幣，然後停止。沒有自動連續比賽。
- 任務 03.1：車庫、抽車、強化、競速分成獨立面板；車庫是左側固定按鈕；競速不再強制切換鏡頭；Boss 入口已隱藏，玩家不能從 GUI 或 Remote 開始 Boss。
- 任務 03.2：背景自動競速。伺服器為每位玩家維持一個工作階段，狀態是 `Idle`、`Running`。一場結束後由伺服器自動開下一場。客戶端不會反覆呼叫 `StartRace`。目前每場發放 45 測試金幣。
- 任務 03.2.1：停止會立刻取消未完成場次且不發獎；強化必須由玩家明確點選車輛；車庫 Viewport 預覽依模型外框放大。
- 任務 03.3：短圈玩具賽道、左右同時墊高的內凹軌道、沿路線行駛的展示車動畫。普通車約 10 秒，完賽獎勵 45 測試金幣。起點與終點沒有文字。
- 任務 03.4：R0 乞丐車商「老破」、獨立抽車 GUI、橫向抽車動畫、五種品質音效、車款圖鑑。舊抽車機入口已移除。
- 任務 03.4.1：老破身高約 5.46 studs；抽車音效改為 Creator Store 可播放素材；新增依品質篩選的自動販賣。

尚未實作，不要在文件或程式裡標成已完成：

還沒有的正式系統：DataStore、正式經濟、重生流程、保護券背包、多人競賽、Robux。不要替這些系統發明規則。圖鑑、自動販賣設定、車庫與金幣都只在這次伺服器記憶體，關服或重進會消失。

## Rojo 對應

`default.project.json`：

| 磁碟 | Roblox | 腳本類型 |
|---|---|---|
| `src/server` | `ServerScriptService` | `.lua` 為 ModuleScript，`.server.lua` 為 Script，`.client.lua` 不在這裡 |
| `src/client` | `StarterPlayer.StarterPlayerScripts` | `.lua` 為 ModuleScript，`.client.lua` 為 LocalScript |
| `src/shared` | `ReplicatedStorage.Shared` | ModuleScript |

`ServerScriptService`、`StarterPlayerScripts`、`ReplicatedStorage` 與 `ReplicatedStorage.Shared` 都設了 `$ignoreUnknownInstances: true`。Rojo 不會刪掉 Studio 裡已有、但檔案裡沒有的物件。執行時建立的 `ReplicatedStorage.CarForgeTaxRemotes` 因此可以留在 Studio。刪掉一個 lua 檔也不會自動清掉 Studio 裡的同名實例。

在專案根目錄執行 `rojo serve`，再用 Studio 的 Rojo 插件 Connect。不要執行 `rojo build -o car-forgetax.rbxl`。

## 已完成模組

核心服務沒有全域單例。伺服器服務都要呼叫 `.new()`，測試必須自己建立實例。玩家鍵是非空字串，或大於 0 的整數。核心模組不接受 Player 實體。概念原型的 `StartPlaySession.server.lua` 才把 `Player.UserId` 轉成字串鍵。

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

`CarUpgradeService.new(options)` 必填 `inventory`。可選 `catalog`、`rng`、`getServerProtection`、`guard`。服務不讀錢包，也不扣金幣。

`guard(playerKey, instanceId)` 由 `PlaySessionService` 注入。它回傳原因字串時，強化在抽取前，以及 `RemoveCar`、`SetUpgradeLevel` 之前，都會停止寫入。參賽車的原因是 `CarRacing`。沒有 guard 時，舊的強化測試行為不變。

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

## 概念原型

資料仍在各玩家自己的 `CarInventoryService` 與 `GoldWallet` 記憶體裡。Studio 才發 `GrantTestGold` 和起始車 `test_common_r0`。正式伺服器不會發測試金幣，也不發起始車。抽車用的重生階級由伺服器固定為 0，不讀客戶端。

### 地圖

`PlaygroundBuilder.build(parent)` 在場景外組好 `CarForgeTaxPlayground`，設好 `Complete` 與 `BuildVersion` 後才放進 `Workspace`。同名資料夾只有在 `Complete` 為真且 `BuildVersion` 等於 `PlaygroundBuilder.Version` 時才沿用；版本目前是 10。`BuildPlayground.server.lua` 與 `StartPlaySession.server.lua` 都會呼叫它。玩家加入時只設定出生點，不重建地圖。`StartPlaySession` 的 Heartbeat 另外呼叫 `PlaygroundBuilder.stepDealer`，只讓老破輕微搖晃。

場景含出生區、五台展示車、R0 乞丐車商、強化工作台、車庫告示與八個展示台座、競速入口，以及貼地的橘色短圈。沒有名為 `GachaMachine` 的抽車機。沒有垂直迴圈，也沒有跳台。路線是起跑半直線、東側彎、回頭直線、西側彎，再衝刺回同一條起終線，並重複兩圈。單圈約 104 studs，兩圈展示長度約 207 studs。原點是 `(46, 2.2, 1)`。中心線保持水平。路面中間是寬 5.2 的槽底，左右各有墊高的護邊，所以彎道是淺凹槽，不是單側屋頂。直線有白色中線。起終線有綠色起跑線、小型黃色拱門和三個白色箭頭。拱門開口高過玩具車。起點與終點都沒有「起跑」或「終點」文字，也沒有貼在賽道上的 BillboardGui。強化台和競速入口的站名仍保留。

R0 車商資料夾是 `R0Dealer`，原點 `(-28, 0.8, -18)`，地板頂面 y=0.8。NPC 模型名 `LaoPo`。頭、身體、四肢、帽子、鬍子、衣服和工具袋一起放大兩倍，鞋底貼地。帽頂到鞋底約 5.46 studs，和一般玩家角色同一級身高。旁邊有木桌、棚子、紙箱、直立舊輪胎、價格牌「500 金幣一台」和「老破的攤」。攤上的二手車仍是玩具尺寸。`ProximityPrompt` 在頭部，按 E，`Station` 是 `R0Dealer`，`MaxActivationDistance` 14。待機只上下約 0.03 studs 並輕微左右轉，不會追玩家。

`BossGate` 模型仍在，供以後重新啟用。它完全透明、不能碰撞，也沒有 `ProximityPrompt`。`GarageSign` 只做展示，站名是 `GarageDisplay`，沒有互動入口。競速入口標題是「競速」，提示文字是「開啟競速」。

展示車標記 `DisplayOnly`，不會寫進車庫。

### 3D 玩具車

`src/shared/CarVisualFactory.lua` 的 `build(spec)` 產生獨立 Model。約 3 × 1.6 × 1 studs，含車身、車頂、四個輪胎、車窗、前後燈。品質顏色：普通白、優良綠、稀有藍、史詩紫、傳說橘。傳說車有少量 `PointLight` 與 `ParticleEmitter`。`poseCFrame(pose, rideHeight, lateral)` 把車放到賽道姿態上。

視覺模型不是車庫權威。`CarCatalog.ModelAsset` 仍是 nil。參賽車由 `PlaygroundPresenter` 放進 `ActiveRaces`，名稱 `ActiveRaceCar`，屬性 `RaceId`。客戶端另把擁有的車放到 `LocalGaragePreview`，只在本機看得到。

### GUI

任務 03.1 已把功能拆開。`src/client/GarageUI.lua` 只建立一個 `ScreenGui`，名稱 `CarForgeTaxInterface`。裡面有四個獨立面板：`GaragePanel`、`GachaPanel`、`UpgradePanel`、`RacePanel`。同一時間只顯示一個。關閉面板不會中斷競速，也不會鎖滑鼠或鍵盤。

車庫按鈕固定在畫面左側，名稱 `GarageButton`，含簡易車形與「車庫」文字。再點一次或按關閉可收起。車庫面板顯示車輛、品質、強化等級、性能，並保留 ViewportFrame 的 3D 預覽。那個預覽相機不是玩家鏡頭。點選車輛會呼叫 `SelectCar`。

抽車、強化、競速面板只放自己的操作。抽車仍讀 `CarConfig.SinglePullPrice`，價格仍是 500。強化仍用 `UpgradeConfig` 顯示五種真實機率，並保留閃光。沒有 Boss 按鈕。自動販賣只在抽車面板，不在強化面板。

抽車面板標題是「老破的二手車攤」，由 `src/client/GachaBoard.lua` 建在既有的那一個 `ScreenGui` 裡。內容有金幣、單抽 500、抽一台車、跳過動畫、音效開關、查看機率、車款圖鑑、自動販賣設定。機率文字直接讀 `CarConfig` 權重：普通 50、優良 30、稀有 15、史詩 4、傳說 1。品質顯示名稱用 `CarConfig`，優良不是另寫的「非凡」。

橫向卡片動畫在伺服器回傳結果之後才播放，約 4.2 秒，由快到慢，停在中央指針。停住的卡片必須是伺服器的 `ModelId` 與品質。客戶端不會再抽一次。跳過會停在已經決定的結果，並只播一次該品質的揭曉音。關閉面板會停音效，不會停止自動競速，也不控制角色或主鏡頭。

圖鑑只列 `UnlockRebirth == 0` 的五款 R0 車。已發現顯示真名、品質色和基礎性能。未發現是黑色方塊剪影、名稱「???」、標成未解鎖。圖鑑用 `ModelId`，車庫用 `InstanceId`。自動販賣把車移出車庫後，圖鑑仍保持已發現。

自動販賣預設關閉。選項是普通以下、優良以下、稀有以下、史詩以下、所有品質。「以下」包含該品質。所有品質包含傳說，必須再按一次確認。選定後會列出會賣的品質、保留的品質和售價。動畫結束後，若伺服器回 `sold`，結果仍是原本抽到的車，並顯示「已自動販賣，獲得 XXX 金幣」。

強化面板的選取只存在客戶端，初始是 `nil`。開啟強化面板，或從強化面板切到其他面板時，都會清掉選取。未選車時按鈕停用並顯示「請先選擇汽車」，客戶端不送 `Upgrade`。玩家點選後，說明顯示車名、品質、強化等級與 `InstanceId`，按鈕顯示「強化：車名 +等級」。成功、損壞、維持會保留該車。車輛消失時清掉選取，顯示「汽車已報廢，請重新選擇汽車」，不會自動改選下一台。參賽中與 +10 的按鈕維持停用。連點由客戶端處理中狀態擋下，伺服器仍做頻率與 `CarRacing` 驗證。

競速面板顯示選擇的車、是否自動競速、當前場次、完成場次、本次累積金幣，以及「開始自動競速」和「停止自動競速」。右上角有小型可收合的 `RaceStatus`。關閉競速面板不會停止循環。停止由伺服器立刻取消未完成場次。

車庫 `Preview` 的 Viewport 相機視野角是 32 度，從斜前上方看向模型中心。距離依每個零件的外框角點計算，車身約佔預覽高度七成，旋轉時不裁切。這只影響車庫預覽，不改變玩具車零件尺寸，也不改變地圖展示車或賽道上的 `ActiveRaceCar`。

`PlaygroundClient.client.lua` 負責 Remote、提示與世界車庫模型。競速期間不改 `CameraType`、不改 `CameraSubject`、不改寫 `Camera.CFrame`，也不移動或焊接角色。

地圖 `ProximityPrompt`：

| Station | 現況 |
|---|---|
| `R0Dealer` | 按 E 只打開抽車面板。舊的 `GachaMachine` 已移除 |
| `UpgradeBench` | 只打開強化面板 |
| `RaceKiosk` | 只打開競速面板，不會立刻開賽 |
| `BossGate` | 已隱藏，沒有提示 |
| `GarageDisplay` | 只展示，沒有提示 |

### Remote

資料夾：`ReplicatedStorage.CarForgeTaxRemotes`。

- `Action`：`RemoteFunction`。客戶端只傳 `action`、可選 `attemptToken`、可選 `instanceId`。
- `RaceFinished`：`RemoteEvent`。只由伺服器 `FireClient`。伺服器若收到客戶端觸發，只警告，不發錢。

允許的 action：`GetState`、`Pull`、`Upgrade`、`SelectCar`、`StartRace`、`StartBoss`、`StartAutoRace`、`StopAutoRace`、`SetAutoSell`。其他 action，包括 `Credit`、`GrantTestGold`、`FinishRace`、`Discover`、`SellCar`，回 `UnknownAction`，不改餘額。

`SetAutoSell` 只接受啟用與否、品質上限，以及所有品質時的 `confirmAll`。沒有確認就選傳說上限會回 `NeedsConfirm`，設定不變。客戶端傳的售價、金幣數量或假品質都會被忽略。售價只讀 `src/shared/AutoSellConfig.lua`。目前只有重生 0：普通 100、優良 175、稀有 300、史詩 650、傳說 2000。

玩家流程裡的 `StartBoss` 會回 `BossDisabled`，不開賽、不發錢。`PlaySessionService.new` 只有在伺服器建構選項 `bossEnabled == true` 時才會進入 Boss 演算法。`StartPlaySession.server.lua` 不傳這個選項。演算法、`RaceConfig` 的 Boss 參數與測試都保留。

客戶端的 `attemptToken` 只作為重送鍵。伺服器自己產生 `Pull:n` 這類 requestId，再交給既有抽車或強化服務。同一 token 重送會得到 `replayed = true`，不會再扣款或再發車。抽車最短間隔 1.5 秒，強化 0.75 秒。客戶端指定的品質、車款、重生、價格、結果、獎金、完賽時間都會被忽略。

### 單場與背景自動競速

`StartRace` 仍是單場。`beginRace` 確認玩家擁有該車，用 `CarConfig.calculatePower` 計算性能，再呼叫 `RaceConfig.describe`。客戶端不能指定時間或獎金。`StartPlaySession` 的 Heartbeat 呼叫 `advanceAll`。時間到才 `Credit` 一次 `NormalReward` 45。`rewarded` 擋第二次發獎。進行中再開始另一場會回 `RaceInProgress`。原型測試「單場競速發獎」仍保留。

`StartAutoRace` 建立該玩家唯一的自動競速工作階段，狀態是 `Idle` 或 `Running`。列舉裡仍留著 `Stopping`，但停止操作不會停在這個狀態。開始後立刻跑第一場。完賽並發放 45 後，若玩家仍在線、車輛仍在、狀態仍是 `Running` 且世代相符，伺服器自己開下一場。客戶端收到 `RaceFinished` 只更新畫面，不會再呼叫開始。關閉面板或離開競速區域都不會停止。重複開始回傳目前工作階段，不建立第二個循環，也不清掉累積場次。新的開始在 `Idle` 時有 1 秒間隔；成功停止後會清掉這個間隔，所以可以立刻再開始。

`StopAutoRace` 立刻生效。它先增加工作階段世代，把尚未結算的自動競速標成 `cancelled`，清掉該場 `ActiveRaceCar`，回到 `Idle`，並解除 `InstanceId` 鎖定。取消的場次不發獎。已經 `rewarded` 的場次保留金幣，不會扣回。不再啟動下一場。重複停止回傳目前的 `Idle`，不會再次結算。舊場次的完賽回呼若世代不符，不能發獎，也不能影響之後的新競速。

每位玩家同時只有一個有效工作階段。自動競速進行中，以及單場進行中，都以 `InstanceId` 鎖定參賽車。`PlaySessionService` 在強化入口直接回 `CarRacing`。`CarUpgradeService` 在刪除或改等級前再查一次。其他車仍可強化，抽車與車庫也不受影響。完賽發獎前會再確認車還在車庫；車已經不在就不發獎並停止循環。

`PlaygroundPresenter` 在完賽或取消時立刻 `Destroy` 該場模型。下一場重新建立展示車。展示模型不是車庫或金幣的權威來源。成功完賽的 `onRaceFinished` 會多帶一個 `true`，展示端只在這時放短促的衝線效果。取消與缺車不帶這個旗標，也不發獎。

展示車用 `RaceConfig.sample` 沿可見路面移動，車頭跟著行進方向，不會瞬移或直角轉向。`visualAlpha` 只影響起步快慢：起跑先慢，再拉到巡航，終點仍落在正式距離。它不改變伺服器完賽秒數。車輪依行進距離轉動，車身有輕微起伏，起步時略為抬頭。起步塵土與速度拖尾是展示效果，不改發獎時機。兩圈展示會在普通車的約 10 秒內跑完，車在整段時間都看得到。角色沒有被移到賽道上，鏡頭也不跟著展示車。

玩家離線時 `removeSession` 增加世代、取消尚未發獎的比賽、清掉展示模型，再刪除 session。未完成場次不發獎。重新加入會建立新的記憶體工作階段，不繼承舊的循環。

角色沒有被焊上玩具車，也沒有坐進 Seat。`StartPlaySession` 只在加入與重生時把 `HumanoidRootPart` 移到出生點。競速期間客戶端不切換、不跟隨鏡頭，也不禁止走動。

`RaceConfig`：

- 一般競速時間 5 到 10 秒。性能 100 是 10 秒。`calculatePower` 沒有改，公式上限仍是 520，對應 5 秒，不會接近 0 秒。
- 一般完賽獎勵 `NormalReward = 45` 測試金幣。這是配合 10 秒場次的概念測試值，不是正式經濟。03.3 之前是 180。
- Boss 基準 `BossTargetTime = 10`。賽程 40% 處速度變成 0.8，持續 3 秒，所以普通車 Boss 約 10.6 秒，仍然落敗。低於 10 秒才算贏。
- Boss 勝利 `BossWinReward = 450`，落敗 `BossLoseReward = 0`。玩家入口仍關閉。
- 短圈 `visualLaps = 2`。圈數只決定展示車繞幾圈，完賽仍看經過的秒數，不按圈發獎。

### 原型測試

- `src/server/PrototypeTests.lua`
- `src/server/RunPrototypeTests.server.lua`

只在 Studio 執行，使用自己的記憶體 session，不寫入線上玩家資料。

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

## 抽車圖鑑、音效與自動販賣

`src/server/CarDiscoveryService.lua` 只在伺服器記憶體記錄 `ModelId`。成功發車時記錄，包含 Studio 起始測試車。重複的 `ModelId` 不會增加次數。客戶端不能自行宣稱解鎖。玩家離開時清除。關服後消失。

`src/shared/GachaSoundConfig.lua` 與 `src/client/GachaSound.lua` 使用固定數量的 Sound，不會每幀新建。音效都在 Studio Play 確認 `IsLoaded`。來源是 Creator Store 免費素材：Pro Sound Effects 與 APM Music。

| 用途 | SoundId | 名稱 |
|---|---|---|
| 啟動 | `9125626478` | Lever Mechanism Crank Clicks Big Metal Clunk |
| Tick | `9119717523` | Switch Click On Or Off Toggle Button 2 |
| 鎖定 | `9116673944` | Metal Impact Heavy Clunking Hits Scraping 4 |
| 普通 | `9114132743` | Door Chime 12，播約 0.65 秒 |
| 優良 | `9114132743`、`9114132738` | Door Chime 12 與 11 |
| 稀有 | `1844278029` | Cartoon Time 3 (b) Link 2，播約 1.35 秒 |
| 史詩 | `9116673678`、`9043151109` | Metal Impact 1 與 Get Up And Go - Hit |
| 傳說 | `9116673678`、`9125665716`、`83315768373322` | 金屬聲後接 Conquering Heroes Link 前 2.6 秒 |

Tick 跟卡片經過中央指針同步。跳過只播一次揭曉。音效開關把 SoundGroup 音量設為 0 並停止播放。傳說旋律不是把電子提示音改音高。完整勝利音檔長 13.86 秒，遊戲只播開頭 2.6 秒。

自動販賣只處理這次成功抽到的新車。順序是：既有抽車服務決定結果並扣 500、發車、記入圖鑑、依設定判斷、確認持有且不是參賽車、`RemoveCar` 成功後才 `Credit`。同一個抽車請求重送不會再入帳。同一個 `InstanceId` 不會第二次入帳。不會賣起始測試車、原本就有的車、強化過的車，或正在競速的車。車輛紀錄沒有品質欄位，伺服器用抽車結果的品質對圖鑑。

## 已通過的測試

2026-10-27，任務 03.4 與 03.4.1 完成後，在已開啟的 `car-forgetax.rbxl` 按 Play。停止 Play 只會回到 Edit，不會改磁碟檔。

這一輪三組測試都是 0 FAIL，合計 37 PASS：抽車與車庫 11 PASS，強化 17 PASS，概念原型 9 PASS。原型 9 項包含原本的 8 項，另加自動販賣。自動販賣測試覆蓋預設關閉、普通淨支出 400、優良在「普通以下」時保留、史詩售出 650、未確認不能賣傳說、確認後傳說售出 2000、同一請求不重複入帳、圖鑑保留已售車款、起始車與參賽車不被賣掉、金幣不足不能抽。場景檢查確認老破身高在 5 到 6 studs、鞋底貼地、只有一個按 E 的車商提示。Play 裡玩家站在攤位旁，角色含頭髮約 5.96 studs，老破約 5.46 studs。實抽一台普通測試車後，金幣由 50000 變成 49600，結果文字是「已自動販賣，獲得 100 金幣」，車名仍是普通測試車。

2026-10-27，任務 03.3 完成並移除起終點文字後，在已開啟的 `car-forgetax.rbxl` 按 Play。停止 Play 只會回到 Edit，不會改磁碟檔。

這一輪三組測試都是 0 FAIL：抽車與車庫 11 PASS，強化 17 PASS，概念原型 8 PASS。原型測試確認普通車 10 秒、45 金幣、Boss 緩速仍生效、單場只發一次獎、自動競速立即停止不發獎、場景可重複建立。場景檢查確認沒有起跑或終點文字，彎道中心是平的，左右護邊都高於槽底且高度一致。Play 畫面裡終點只剩小型黃色拱門、綠色起跑線和白色箭頭，沒有「起跑」或「終點」。賽道上沒有文字介面。鏡頭維持 `Custom`。

2026-10-27，任務 03.2 與 03.2.1 完成後的較早一輪 Play 結果仍是當時的紀錄。下面提到的 180 金幣與 40 秒，是 03.3 改時長與獎勵之前的結果。

這一輪三組測試都是 0 FAIL：抽車與車庫 11 PASS，強化 17 PASS，概念原型 8 PASS。原型測試保留「單場競速發獎」，並新增「背景自動競速」：連續三場累積 540、參賽車鎖定、其他車仍可強化、立即停止不發獎、重複停止安全、缺車不發獎、離線不發獎、重進不繼承舊循環。`StartBoss` 仍回 `BossDisabled`。

同一輪 Play 裡，按下停止後狀態立刻是 `Idle`，展示車被清掉，鎖定解除，未完成場次沒有把 50000 測試金幣增加。兩場正常完賽累積 360 後，取消下一場，8 秒後餘額仍是 50360。強化面板開啟時沒有預選車；點選後按鈕顯示目標車名與等級；關掉再打開必須重選。參賽車強化回 `CarRacing`。稀有車報廢後顯示「汽車已報廢，請重新選擇汽車」，沒有自動改選剩下的普通車。車庫預覽車身置中，最大約佔預覽高度 71%，八個角度都沒有超出畫面。預覽、地圖展示車與賽道 `ActiveRaceCar` 的車身尺寸都仍是約 `1.28 × 0.42 × 2.7`。

2026-10-27，任務 03.1 完成後的較早一輪 Play 結果仍有效，當時原型測試是 7 PASS。下面的抽車 11 項與強化 17 項分布，在 03.2.1 這輪也再次通過。

03.1 那一輪三組測試都是 0 FAIL：抽車與車庫 11 PASS，強化 17 PASS，概念原型 7 PASS。原型測試同時覆蓋「玩家 `StartBoss` 回 `BossDisabled`」與「`bossEnabled` 時 Boss 演算法仍可判定勝負」。Play 裡左側車庫可開關；抽車、強化、競速各自開自己的面板。單抽後 50000 變成 49500。另一台車強化 +0 到 +1，性能 110，金幣不變。單場 40 秒完賽後再加 180，餘額 49680。競速開始、走路、關面板、完賽與重生後，鏡頭都維持 `Custom`，主體是玩家 Humanoid。兩次玩家 `StartBoss` 都被拒絕。

抽車與車庫：11 PASS / 0 FAIL。一萬次模擬使用引擎隨機數，容差是 5 個標準差：普通 4949（±250）、優良 3040（±230）、稀有 1514（±179）、史詩 391（±98）、傳說 106（±50）。

強化：17 PASS / 0 FAIL。同一容差下，+8 報廢 5016、大成功 98；+9 報廢 8049、大成功 0。也覆蓋了 +0 損壞仍為 +0、+9 成功到 +10、+8 大成功到 +10、報廢移除、無效 ID、跨玩家拒絕、重複 requestId、重入拒絕、不扣金幣，以及 +4、R2、普通車性能 167。

概念原型在 03.1 是 7 PASS / 0 FAIL。03.2.1 起是 8 PASS / 0 FAIL，多了背景自動競速，原本的單場發獎仍在。03.3 這一輪仍是 8 PASS / 0 FAIL。覆蓋競速時間與 Boss 緩速、Studio 起始車、抽車扣 500、重複請求、強化與報廢、+10、單場只發一次完賽金幣、不能操作別人的車、不能用 Remote 加金幣，以及場景可重複建立。03.3 之前單場獎勵斷言是 180；目前是 45。

同一輪 Play 裡，玩家出生在出生點，車庫有一台普通測試車，性能 100，測試金幣 50000。打完一場普通競速後餘額變成 50180。比賽途中沒有先加錢。

Studio 場景另有既有警告：`rbxassetid://203785492` 的資源類型不符。不是這些測試腳本產生的。

## 已知問題

任務 03.1、03.2、03.2.1、03.3、03.4 與 03.4.1 已處理 GUI 分離、強制鏡頭、玩家可觸發的 Boss、背景自動競速、立即停止、參賽車鎖定、強化選車、車庫預覽、短圈賽道、內凹軌道、展示車動畫、起終點文字、R0 車商、抽車動畫、圖鑑、音效與自動販賣。下面這些仍在，下一個 Agent 再處理。

- 卡片 Tick 使用 Pro Sound Effects 的開關聲，原檔偏小。播放音量已設為 1.6，連續喀噠仍可能比揭曉鈴聲輕。
- 傳說旋律是 APM「Conquering Heroes Link」的前 2.6 秒，完整音檔 13.86 秒。它不是單獨製作的短勝利曲。
- 自動販賣清單較長。較矮的視窗裡，「所有品質」可能要在設定區稍微捲動才看得到。
- 車庫預覽因俯視透視，靠近鏡頭的一側會先接近畫面邊緣，所以車身大約佔預覽高度 71%。再拉近會裁到車輪。
- 近看賽道接縫仍能看到淡淡的分段。這不改變行車路線。
- 重生階級固定為 0。性能用取得時的 `AcquiredRebirth`。自動販賣售價目前也只有 R0。
- 保護券沒有道具背包。
- 圖鑑、自動販賣設定、車庫與金幣都沒有 DataStore。重進或關服後會消失，自動販賣回到關閉。
- 一萬次模擬是統計容差。冪等快取只在該伺服器行程的記憶體裡。
- `$ignoreUnknownInstances` 會讓檔案刪除後，Studio 裡的舊實例繼續留著。舊的 `GachaMachine` 若還留在未重建的場景裡，要把 `BuildVersion` 升過 9 才會換成車商。目前版本是 10。
- 磁碟上的 rbxl 沒有被這次開發寫入。關掉 Studio 時若不存檔，場所檔仍不含這些腳本，下次要靠 Rojo 同步。
- Studio 既有警告：`rbxassetid://203785492` 的資源類型不符。不是這次抽車音效。

## 尚未實作

- DataStore 與正式金幣經濟。不要把 `GrantTestGold` 接到客戶端。
- 保護券背包、特殊能力、`ModelAsset` 正式資源。
- 重生流程。目前只有加成表、車款 `UnlockRebirth`，以及伺服器固定傳入的 0。
- 多人競賽與 Robux。
- 手動販賣已經持有的車。目前只會自動販賣剛抽到的新車。

## 下一階段待開發需求

任務 03.1、03.2、03.2.1、03.3、03.4 與 03.4.1 已完成。DataStore、正式重生、保護券背包、手動販賣與 Robux 尚未實作。

### 任務 03.1（已完成）

- 抽車機器留在場景裡，打開獨立抽車 GUI。03.4 已把這個入口換成 R0 車商。
- 強化工作台留在場景裡，打開獨立強化 GUI。
- 競速入口留在場景裡，打開獨立競速 GUI。
- 車庫取消地圖互動入口，改成畫面左側固定按鈕。
- 這些功能不再放進同一個操作面板。
- 競速不強制切換或跟隨鏡頭，角色可自由移動。
- Boss 入口已隱藏，玩家 `StartBoss` 會被伺服器拒絕。演算法與測試保留。

### 任務 03.2：背景自動競速（已完成）

- 玩家選擇自己的車後，伺服器建立唯一自動競速工作階段並立刻開始第一場。
- 每場由伺服器結算並發放當時的 180 測試金幣，接著自動開始下一場。03.3.1 已把這個測試獎勵改成 45。
- 關閉面板或離開競速區域不會停止。客戶端不會用反覆 `StartRace` 製造循環。
- 角色可自由移動，不被焊接或坐下，鏡頭也不被強制切換。
- 競速中可以抽車、強化其他車、打開車庫。
- 參賽車以 `InstanceId` 鎖定，強化或報廢會回 `CarRacing`。
- 每場建立對應的 `ActiveRaceCar`，完賽後清掉，下一場重新建立。
- 玩家離線後未完成場次不發獎，重新加入不繼承舊工作階段。

### 任務 03.2.1：立即停止、強化選車與車庫預覽（已完成）

- 按下停止後，未完成場次立刻取消、不發獎，已完成獎勵保留，參賽車立刻解鎖。
- 重複停止是安全的。停止後可以立刻重新選車並開始，舊場次不會干擾新場次。
- 強化面板不預選車輛。沒有明確 `InstanceId` 時客戶端不送強化請求。
- 報廢或車輛消失後清除選取，不自動改選下一台。重新開啟強化面板必須再選一次。
- 車庫 3D 預覽依模型外框放大並置中。真實車輛、地圖展示車與賽道展示車的尺寸沒有改。

### 3. 競速視覺改善（03.3 已完成）

- 賽道改成可重複的短圈，沒有大型垂直迴圈或高跳台。
- 路面是中間低、左右護邊高的內凹槽，展示車沿槽底行駛。
- 展示車有起步加速、沿路線轉向、車輪轉動和輕量速度效果。效果不改變伺服器發獎時間。
- 普通車約 10 秒，完賽獎勵 45 測試金幣。性能越高時間越短，最短 5 秒。
- 起點與終點不放文字。小型拱門、起跑線和箭頭保留。
- 競速動畫不移動角色，也不強制鏡頭。競速狀態仍用既有的小型 UI。

### 4. 抽車動畫、車商、圖鑑與自動販賣（03.4 與 03.4.1 已完成）

- 舊抽車機入口已移除。按 E 與 R0 車商「老破」互動，打開「老破的二手車攤」。
- 老破全身等比例放大，身高約 5.46 studs，鞋底貼地。
- 伺服器先決定抽車結果並扣 500。客戶端再播橫向卡片動畫，停在真正抽到的車。
- 五種品質有不同揭曉音。傳說另有金屬聲和約 2.6 秒的勝利旋律。
- 圖鑑記錄已發現的 R0 `ModelId`。未發現顯示黑色剪影。關服後消失。
- 自動販賣預設關閉。售價集中在 `AutoSellConfig`：普通 100、優良 175、稀有 300、史詩 650、傳說 2000。
- 只出售剛抽到的新車。移除成功後才入帳。客戶端不能指定售價。所有品質需要額外確認。

### 5. Boss 系統（03.1 已停用玩家入口）

- 不再繼續開發 Boss 玩法。
- Boss 入口已隱藏，玩家從 GUI 或 Remote 開始 Boss 會被拒絕。
- 保留現有 `StartBoss`、`RaceConfig` 的 Boss 參數和測試，供以後使用。

沿用 `CarCatalog`、`CarInventoryService`、`CarGachaService`、`CarUpgradeService` 和 `CarConfig`。不要另寫一套抽車或強化演算法，也不要改既有機率與性能公式。視覺化只能顯示伺服器車庫已有的車。不要覆蓋 `car-forgetax.rbxl`。

## Git 與 Rojo 注意事項

- `.gitignore` 忽略 `*.rbxl.lock`、`*.rbxlx.lock`、`sourcemap.json` 和系統暫存檔。`*.rbxl` 與 `*.rbxlx` 要保留在版本庫。
- Studio 開啟場所時會產生 `car-forgetax.rbxl.lock`，這個檔不要提交。
- 免費強化系統在 `6d3e77d`，訊息是 `Implement free car upgrade system`。
- 上一份交接文件在 `a913f7f`，訊息是 `Add updated AI project context`。那份內容還停在原型之前。
- 概念原型與當時的交接文件在 `de4f1d8`，訊息是 `Save prototype before agent handoff`。
- 任務 03.1 與當時的交接更新一起提交，訊息是 `Separate GUI and remove forced race camera`。
- 任務 03.2、03.2.1 與當時的交接更新一起提交，訊息是 `Implement auto racing and interaction fixes`。
- 任務 03.3 與當時的交接更新一起提交，訊息是 `Improve toy race track and racing experience`。
- 任務 03.4、03.4.1 與這份交接更新一起提交，訊息是 `Implement R0 merchant gacha audio and auto sell`。
- 不要自行 commit 或 push，除非使用者明確要求。
- 改完 Lua 後用已連線的 Rojo 同步。驗證時在 Studio 按 Play，看 `[CarForgeTax 測試]`、`[CarForgeTax 強化測試]` 與 `[CarForgeTax 原型測試]`。
- 停止 Play 不會刪除 `src` 裡的檔案。
