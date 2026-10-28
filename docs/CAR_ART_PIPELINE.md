# CarForgeTax 汽車美術流程

Cursor 不從零建模，也不再用 Blender Python 生成汽車。每台正式車由兩份現成模型組裝：

- `CarBody.glb`：不含四個輪胎的車身。
- `Wheel.glb`：一顆完整輪胎，包含輪框和橡膠胎。四輪都複製這一顆。

風格仍以這台 Tripo 紅色掀背的完成度為下限。它只是對照，不是要重製的檔案。不要修改、不要覆蓋：

`blender/exports/Tripo/red hatchback 3d model.glb`

這份文件不改抽車、強化或競速經濟。

## 尺寸與朝向

遊戲裡的車頭朝 Roblox **-Z**。現有展示車用 `CFrame.lookAt` 對齊賽道前進方向。

若模型在 Blender 裡製作，車頭朝 **-Y**，再以 glTF **Y-up** 匯出，進 Roblox 後車頭就會朝 -Z。輪軸沿 Blender **X**，匯出後仍是 Roblox X。現有車輪就是繞這個軸轉。

均勻縮放，不要單獨拉長或拉高。車長對齊現有玩具車，約 **2.65**。其他車用自己的實測車長算倍率。

貼地並放大之後：

- 車長 2.45～2.85
- 車寬 1.25～1.60，含後照鏡可到 1.75
- 車高 0.90～1.15
- 最低點在 0～0.02
- 四輪最低點貼地，不穿進車身，也不懸空

面數以進遊戲的模型計算。車身加四輪合計 8,000～12,000 三角面，上限 15,000。貼圖每張最長邊 1024。Base Color 用 sRGB。Roughness、Metallic、Normal 用 Non-Color。

## 外觀

- 車身是連續曲面，輪拱包住輪胎。
- 保險桿、進氣口和燈做在車身上。
- 輪胎有厚度。輪框內凹，看得到輪輻和輪轂。
- 車窗是深色不透明，坐在窗框裡。
- 烤漆是霧面或低反光，不是鏡面，也不是品質介面色。
- 不放廠牌、文字和標誌。
- 每台車是不同設計，不能只換烤漆。

減面在你自己的建模工具裡做完再交 GLB。不要把整台車用同一個比例硬減到破面。車門縫、輪拱、窗框和輪輻優先保留。

## Studio 組裝

遊戲只在 `ReplicatedStorage.CarMeshKit` 或 `ServerStorage.CarMeshKit` 找模型。最外層名稱必須等於 `CarCatalog` 的 MeshKey。找不到時只顯示 Not imported，不會用 Part 拼一台正式車。

用 Studio 的 3D Importer 匯入兩份 GLB。不要用腳本寫 MeshId。存檔由人在 Studio 裡儲存，不要從外面覆寫 `car-forgetax.rbxl`。

組裝後的模型：

```text
CarModel
- VehicleRoot    不可見，Anchored，模型的 PrimaryPart
- Body           車身 MeshPart
- WheelFL
- WheelFR
- WheelRL
- WheelRR
```

實例名稱不用底線。競速和車庫試跑已經用 `WheelFL`、`WheelFR`、`WheelRL`、`WheelRR` 找輪胎，也用 `Body` 掛煙塵和尾跡。

四輪是同一個 Wheel 模型的複製品。左右外側要朝外。輪距、軸距和輪胎半徑可以各自調整，並記在模型屬性上。車輪保持 Anchored，不要焊在車身上。

目前正式車的 MeshKey：

| 品質 | MeshKey |
|---|---|
| Common | `hatch_common` |
| Uncommon | `coupe_uncommon` |
| Rare | `sedan_rare` |
| Epic | `muscle_epic` |
| Legendary | `rally_legendary` |
| Mythic | `sports_mythic` |
| Divine | `gt_divine` |
| Celestial | `super_celestial` |
| Transcendent | `hyper_transcendent` |
| Eternal | `proto_eternal` |
| Immortal | `night_immortal` |
| Astral | `brake_astral` |
| Cosmic | `hyper_cosmic` |
| Primordial | `proto_primordial` |
| Singularity | `apex_singularity` |

## 車輪旋轉

競速車和車庫試跑車都是錨定的展示模型。伺服器每個模擬步用 `PivotTo` 放到賽道取樣點，不是物理驅動。

車輪角度使用已經在跑的算法：

```text
spin = 沿車軸的行駛距離 / 輪胎半徑
```

這就是 `角速度 = 線速度 / 半徑` 對時間的積分。距離不再增加時輪子停止。距離往回走時反轉。不要用固定轉速。

不要加 `WeldConstraint`、`HingeConstraint` 或馬達。那些約束會跟每個步進直接寫入的車輪 CFrame 打架。

展示中的靜止車可以另給一個預覽速度。速度為 0 時不轉。車輛刪除時要卸下這條更新。競速和試跑仍由現有的步進函式帶動，不另掛一套會重複旋轉的迴圈。

## 驗收

- 車身和四輪組成一台車，左右輪框朝外。
- 輪拱包住輪胎，四輪貼地。
- 車窗沒有破洞，烤漆不是鏡面。
- 尺寸落在上面的範圍內，車頭朝 -Z。
- 三角面不超過 15,000。
- 進遊戲後不再顯示 Not imported。
- 停止時輪子不動，前進正轉，倒車反轉，轉角跟實際行駛距離一致。
