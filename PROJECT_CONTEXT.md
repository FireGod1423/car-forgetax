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

尚未實作，不要在文件或程式裡標成已完成：

- 任務 03.2：背景自動競速。尚未實作。現在仍是單場，結束後不會自己開下一場，也沒有停止循環的按鈕。參賽中的車仍可被強化或報廢。
- 抽車動畫。
- 縮短賽道與競速視覺改善。

還沒有的正式系統：DataStore、正式經濟、重生流程、保護券背包、多人競賽、Robux。不要替這些系統發明規則。

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

## 概念原型

資料仍在各玩家自己的 `CarInventoryService` 與 `GoldWallet` 記憶體裡。Studio 才發 `GrantTestGold` 和起始車 `test_common_r0`。正式伺服器不會發測試金幣，也不發起始車。抽車用的重生階級由伺服器固定為 0，不讀客戶端。

### 地圖

`PlaygroundBuilder.build(parent)` 在場景外組好 `CarForgeTaxPlayground`，設好 `Complete` 與 `BuildVersion` 後才放進 `Workspace`。同名資料夾只有在 `Complete` 為真且 `BuildVersion` 等於 `PlaygroundBuilder.Version` 時才沿用；版本目前是 2。`BuildPlayground.server.lua` 與 `StartPlaySession.server.lua` 都會呼叫它。玩家加入時只設定出生點，不重建地圖。

場景含出生區、五台展示車、抽車機、強化工作台、車庫告示與八個展示台座、競速入口，以及橘色高架賽道。賽道有直線、垂直迴圈、跳台和終點。賽道長度約 176 studs：直線 48、迴圈圓周、迴圈後 24、跳台參數 20、終點 34。原點是 `(36, 5, 0)`。

`BossGate` 模型仍在，供以後重新啟用。它完全透明、不能碰撞，也沒有 `ProximityPrompt`。`GarageSign` 只做展示，站名是 `GarageDisplay`，沒有互動入口。競速入口標題是「競速」，提示文字是「開啟競速」。

展示車標記 `DisplayOnly`，不會寫進車庫。

### 3D 玩具車

`src/shared/CarVisualFactory.lua` 的 `build(spec)` 產生獨立 Model。約 3 × 1.6 × 1 studs，含車身、車頂、四個輪胎、車窗、前後燈。品質顏色：普通白、優良綠、稀有藍、史詩紫、傳說橘。傳說車有少量 `PointLight` 與 `ParticleEmitter`。`poseCFrame(pose, rideHeight, lateral)` 把車放到賽道姿態上。

視覺模型不是車庫權威。`CarCatalog.ModelAsset` 仍是 nil。參賽車由 `PlaygroundPresenter` 放進 `ActiveRaces`，名稱 `ActiveRaceCar`，屬性 `RaceId`。客戶端另把擁有的車放到 `LocalGaragePreview`，只在本機看得到。

### GUI

任務 03.1 已把功能拆開。`src/client/GarageUI.lua` 只建立一個 `ScreenGui`，名稱 `CarForgeTaxInterface`。裡面有四個獨立面板：`GaragePanel`、`GachaPanel`、`UpgradePanel`、`RacePanel`。同一時間只顯示一個。關閉面板不會中斷競速，也不會鎖滑鼠或鍵盤。

車庫按鈕固定在畫面左側，名稱 `GarageButton`，含簡易車形與「車庫」文字。再點一次或按關閉可收起。車庫面板顯示車輛、品質、強化等級、性能，並保留 ViewportFrame 的 3D 預覽。那個預覽相機不是玩家鏡頭。點選車輛會呼叫 `SelectCar`。

抽車、強化、競速面板只放自己的操作。抽車仍讀 `CarConfig.SinglePullPrice`。強化仍用 `UpgradeConfig` 顯示五種真實機率，並保留閃光。競速面板可選車、開始單場、查看狀態，並用小型 `RaceBanner` 顯示進行中。沒有 Boss 按鈕，也沒有抽車動畫。

`PlaygroundClient.client.lua` 負責 Remote、提示與世界車庫模型。競速期間不改 `CameraType`、不改 `CameraSubject`、不改寫 `Camera.CFrame`，也不移動或焊接角色。

地圖 `ProximityPrompt`：

| Station | 現況 |
|---|---|
| `GachaMachine` | 只打開抽車面板 |
| `UpgradeBench` | 只打開強化面板 |
| `RaceKiosk` | 只打開競速面板，不會立刻開賽 |
| `BossGate` | 已隱藏，沒有提示 |
| `GarageDisplay` | 只展示，沒有提示 |

### Remote

資料夾：`ReplicatedStorage.CarForgeTaxRemotes`。

- `Action`：`RemoteFunction`。客戶端只傳 `action`、可選 `attemptToken`、可選 `instanceId`。
- `RaceFinished`：`RemoteEvent`。只由伺服器 `FireClient`。伺服器若收到客戶端觸發，只警告，不發錢。

允許的 action：`GetState`、`Pull`、`Upgrade`、`SelectCar`、`StartRace`、`StartBoss`。其他 action，包括 `Credit`、`GrantTestGold`、`FinishRace`，回 `UnknownAction`，不改餘額。

玩家流程裡的 `StartBoss` 會回 `BossDisabled`，不開賽、不發錢。`PlaySessionService.new` 只有在伺服器建構選項 `bossEnabled == true` 時才會進入 Boss 演算法。`StartPlaySession.server.lua` 不傳這個選項。演算法、`RaceConfig` 的 Boss 參數與測試都保留。

客戶端的 `attemptToken` 只作為重送鍵。伺服器自己產生 `Pull:n` 這類 requestId，再交給既有抽車或強化服務。同一 token 重送會得到 `replayed = true`，不會再扣款或再發車。抽車最短間隔 1.5 秒，強化 0.75 秒。客戶端指定的品質、車款、重生、價格、結果、獎金、完賽時間都會被忽略。

### 單場競速

`PlaySessionService.beginRace` 確認這名玩家擁有該車，用 `CarConfig.calculatePower` 計算性能，再呼叫 `RaceConfig.describe`。`StartPlaySession` 的 Heartbeat 呼叫 `advanceAll`。時間到才 `Credit` 一次。`rewarded` 擋第二次發獎。進行中再開始另一場會回 `RaceInProgress`。

這不是自動連續競速。一場結束後伺服器不會自己開下一場，客戶端也不會自動再按開始。

玩家離線時 `removeSession` 把尚未發獎的比賽標成 `cancelled`，接著刪除 session，不會再發這場的測試金幣。

角色沒有被焊上玩具車，也沒有坐進 Seat。`StartPlaySession` 只在加入與重生時把 `HumanoidRootPart` 移到出生點。競速期間客戶端不切換、不跟隨鏡頭。參賽中的車沒有鎖定，仍可被強化或報廢。任務 03.2 的背景自動競速尚未實作。

`RaceConfig`：

- 一般競速時間 20 到 40 秒。性能 100 是 40 秒，目前公式的最高性能是 20 秒。
- 一般完賽獎勵 `NormalReward = 180` 測試金幣。
- Boss 基準 `BossTargetTime = 35`。賽程 40% 處速度變成 0.8，持續 3 秒。低於 35 秒才算贏。
- Boss 勝利 `BossWinReward = 450`，落敗 `BossLoseReward = 0`。
- 性能 100 的 Boss 賽約 40.6 秒，結果是落敗。

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

## 已通過的測試

2026-10-27，任務 03.1 完成後在已開啟的 `car-forgetax.rbxl` 按 Play。停止 Play 只會回到 Edit，不會改磁碟檔。

這一輪三組測試都是 0 FAIL：抽車與車庫 11 PASS，強化 17 PASS，概念原型 7 PASS。原型測試同時覆蓋「玩家 `StartBoss` 回 `BossDisabled`」與「`bossEnabled` 時 Boss 演算法仍可判定勝負」。Play 裡左側車庫可開關；抽車、強化、競速各自開自己的面板。單抽後 50000 變成 49500。另一台車強化 +0 到 +1，性能 110，金幣不變。單場 40 秒完賽後再加 180，餘額 49680。競速開始、走路、關面板、完賽與重生後，鏡頭都維持 `Custom`，主體是玩家 Humanoid。兩次玩家 `StartBoss` 都被拒絕。

抽車與車庫：11 PASS / 0 FAIL。一萬次模擬使用引擎隨機數，容差是 5 個標準差：普通 4949（±250）、優良 3040（±230）、稀有 1514（±179）、史詩 391（±98）、傳說 106（±50）。

強化：17 PASS / 0 FAIL。同一容差下，+8 報廢 5016、大成功 98；+9 報廢 8049、大成功 0。也覆蓋了 +0 損壞仍為 +0、+9 成功到 +10、+8 大成功到 +10、報廢移除、無效 ID、跨玩家拒絕、重複 requestId、重入拒絕、不扣金幣，以及 +4、R2、普通車性能 167。

概念原型：7 PASS / 0 FAIL。覆蓋競速時間與 Boss 緩速、Studio 起始車、抽車扣 500、重複請求、強化與報廢、+10、單場只發一次 180 金幣、不能操作別人的車、不能用 Remote 加金幣，以及場景可重複建立。

同一輪 Play 裡，玩家出生在出生點，車庫有一台普通測試車，性能 100，測試金幣 50000。打完一場普通競速後餘額變成 50180。比賽途中沒有先加錢。

Studio 場景另有既有警告：`rbxassetid://203785492` 的資源類型不符。不是這些測試腳本產生的。

## 已知問題

任務 03.1 已處理 GUI 分離、強制鏡頭與玩家可觸發的 Boss。下面這些仍在，下一個 Agent 再處理。

- 任務 03.2 背景自動競速尚未實作。只有單場競速，沒有自動連續比賽，也沒有停止循環的按鈕。
- 正在比賽的車仍可被強化或報廢。
- 賽道約 176 studs，一場要 20 到 40 秒，方塊軌道的速度感不足。
- 抽車沒有動畫。
- 重生階級固定為 0。性能用取得時的 `AcquiredRebirth`。
- 保護券沒有道具背包。
- 一萬次模擬是統計容差。冪等快取只在該伺服器行程的記憶體裡。
- `$ignoreUnknownInstances` 會讓檔案刪除後，Studio 裡的舊實例繼續留著。
- 磁碟上的 rbxl 沒有被這次開發寫入。關掉 Studio 時若不存檔，場所檔仍不含這些腳本，下次要靠 Rojo 同步。

## 尚未實作

- DataStore 與正式金幣經濟。不要把 `GrantTestGold` 接到客戶端。
- 保護券背包、特殊能力、`ModelAsset` 正式資源。
- 重生流程。目前只有加成表、車款 `UnlockRebirth`，以及伺服器固定傳入的 0。
- 多人競賽與 Robux。
- 任務 03.2 背景自動競速，以及下面尚未完成的賽道、抽車動畫項目。任務 03.1 已完成。

## 下一階段待開發需求

任務 03.1 已完成。任務 03.2 與後面的項目尚未實作，不要把它們寫成已完成功能。

### 任務 03.1（已完成）

- 抽車機器留在場景裡，打開獨立抽車 GUI。
- 強化工作台留在場景裡，打開獨立強化 GUI。
- 競速入口留在場景裡，打開獨立競速 GUI。
- 車庫取消地圖互動入口，改成畫面左側固定按鈕。
- 這些功能不再放進同一個操作面板。
- 競速不強制切換或跟隨鏡頭，角色可自由移動。
- Boss 入口已隱藏，玩家 `StartBoss` 會被伺服器拒絕。演算法與測試保留。

### 任務 03.2：背景自動競速（尚未實作）

- 玩家可選擇一台自己的車參加競速。選擇競速車已經有了，連續比賽還沒有。
- 啟動後自動連續比賽，每場結束就開始下一場，中間不用再手動按開始。
- 玩家可以隨時停止自動競速。
- 競速時角色可以自由移動。這項已在 03.1 達成，03.2 要保持。
- 不得把角色綁定、焊接或強制坐上玩具車。目前已遵守，03.2 要保持。
- 不得強制鎖定或切換玩家鏡頭。這項已在 03.1 達成，03.2 要保持。
- 玩家可以同時抽車，或強化其他汽車、管理車庫。
- 正在參賽的汽車不可被強化或報廢。目前還沒有這道鎖。
- 賽道上必須顯示這場真正參賽的 3D 玩具車。單場已經會顯示，連續比賽時也要維持。
- 伺服器負責比賽結果和金幣發放。
- 玩家離線後不得繼續發放在線獎勵。

### 3. 競速視覺改善

- 縮短初始賽道。
- 簡化賽道結構並改善外觀。
- 加強起跑加速、轉彎和衝線動畫。
- 提升速度感。
- 競速動畫不得影響玩家移動。
- 競速狀態用小型 UI 顯示，不要擋住操作。

### 4. 抽車動畫

- 抽車時增加動畫回饋。
- 展示抽中的車輛和品質。
- 動畫不可改到 `CarConfig` 的抽車機率，也不可讓客戶端指定結果。

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
- 任務 03.1 與這份交接更新一起提交，訊息是 `Separate GUI and remove forced race camera`。
- 不要自行 commit 或 push，除非使用者明確要求。
- 改完 Lua 後用已連線的 Rojo 同步。驗證時在 Studio 按 Play，看 `[CarForgeTax 測試]`、`[CarForgeTax 強化測試]` 與 `[CarForgeTax 原型測試]`。
- 停止 Play 不會刪除 `src` 裡的檔案。
