> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP04：本機 C4 的雙滑鼠原生動作路由

採用 Route A，基礎跨模式動作的實機依據見 [四組結果](LIVE_FOUR_CAPTURES.md)。EXP04 新增的滑鼠映射與 Fire 消重尚待實機驗證；離線結果不能證明畫面、動畫時序或網路行為。

## 原生 Fire 分支

build `24826606`，`game.dll` SHA-256 `cc75948d90fdfde259dcb519e9933db7ffa3ccb281ce4fb89e6b1b011557470c`。沿用同 build 的既有唯讀 native code capture，新增六個完整函式指紋；總共 34 段、17,295 bytes，記於 [mouse-layout.json](../../evidence/mouse-layout.json)。

- `0x738260` 初始化 Weapon flags。`0x738929` 附近選擇正常 input driver bit 12，另一分支使用 bit 13。
- `0x738be0` 更新 weapon input。`0x738c5a` 的 `bt eax,12` 控制是否進入普通 Fire 路由；C4 為 ability 型（bit 3），在 `0x738e13` 呼叫 `0x7cd310`，再寫入 AbilityWeaponDriver Fire latch。
- 當 bit 12 / bit 13 均未設，跳過此 Fire 動作分支並繼續其餘 weapon bookkeeping。實機 C4 flags 是 `0x1148`；暫改為 `0x148` 保留 ability、WeaponRounds 與 exclusion bits。
- 原生 `0x7397e0` / `0x739ba0` Fire set / release 改輸入狀態，沒有直接呼叫 `0x7cd310` 或 ability start。它们保留原版 bookkeeping。
- 另一個 `0x73a1e0` 觸發路徑需要 projectile 元件，不是這個 C4 型別的普通 Fire 分支。`0x7cd6f0` 獨立 Fire edge 函式也已納入指紋；目前 capture 中未發現其直接 call / jump / RIP 引用，這不代表證明所有間接入口均不存在。

這是本 build 的靜態推導；首次滑鼠實測仍需排除其他引擎時序或入口造成的重複動作。沒有更改 Aim；右鍵的原生姿態／視角處理保留。

## 寫入與還原邊界

[fire_gate_windows.lua](../../src/fire_gate_windows.lua) 是唯一 memory write site：以本程序 WriteProcessMemory 寫入 **1 byte**，位址是當前 C4 Weapon state flags 的第二個 byte，僅允許 `0x1148 ↔ 0x148`。寫入前比較完整 flags，寫入後重新讀回。沒有 executable page patch、VirtualProtect、OS input injection、mode / ammo / animation state write。

[weapon_fire_gate.lua](../../src/weapon_fire_gate.lua) 使用既有 ContextReader 驗證 mission、本機角色、裝備欄、owned C4 entity、完整 descriptor 與 mode，另核對 WeaponManager / AbilityWeaponDriver registry 的 24-byte entity。必須左右鍵都放開，且原生 Fire latch 已釋放，才取得本把 C4 的 gate。首次寫入前重驗全部 guarded code 及 identity，先 flush 意圖日誌，再保留還原 ownership 並寫入。

換武器後，還原使用保存的 entity ID、24-byte identity、owner / manager epoch 重新查找現在的 component index / state pointer，能跟隨 compaction。已消失或被重用的 entity 不接受舊 pointer 寫入。讀寫暫時失敗保留 ownership 供後續 update 重試；未知 flags 不強制覆蓋。停用時若同一把 C4 的滑鼠仍按住，等釋放後還原，避免原版 Fire 將同一次長按視為新射擊。

正常每個 callback 在原 update 前後核對 gate；停用且沒有還原工作時不取樣記憶體。保留原 callback 的多回傳值及例外；shutdown / logging failure 嘗試還原，失敗則停止新動作。遊戲退出、entity 已移除或 foreign flags 改變等情況不能承諾永久失效的記憶體一定可以還原。

## 動作與输入

實體 RMB pressed → Deploy 521，LMB pressed → Detonate 520；與目前 mode 無關。僅保留四個已審查的 native callable pointers：`0x7c21a0`、`0x73ca00`、`0x73bf20`、`0x74b220`。Deploy 沿用原版 start / consume / count / after；Detonate 沿用原版 start。沒有直接呼叫 spawn phase 10 或 explosion phase 15。

物理 edge router 要求 context / focus / 啟用後的釋放基線，不把已長按的按鍵當新事件；同 callback 的雙 pressed 固定由 Detonate 優先。action lock、最多一格 pending、原 1.5 秒期限、原生補彈限制與保守地面 scope 保持不變。不新增補彈後預觸發承諾。

F6 預設关闭／手動啟用，F7 marker。Esc / Enter / Tab / R / M / 失焦自動停用。F8 / F9 不再綁定動作。其他武器沒有新增 mapping；原生 Aim 保留。非 C4、失焦或身份失效會清除 pending。

## 驗證與交付

`python -B scripts/check_mouse.py` 組裝後檢查完整 addon：兩種 mode、30 / 60 / 144 Hz 長按、模擬原生 Fire 的消重、Aim 保留、雙鍵優先、切武器、F6、選單／失焦、零 ready ammo、既有 pending、單 byte Windows write、compaction、舊 entity 拒絕、日誌／讀寫錯誤及還原重試、原 callback 例外、多回傳值、程式指紋變動。測試使用 synthetic memory / mock Windows / mock native calls。

結果為 mouse-offline-tests.json (`../evidence/mouse-offline-tests.json`; local research artifact)。既有 action / context / probe 回歸另記 action-offline-tests.json (`../evidence/action-offline-tests.json`; local research artifact)。先前出貨 EXP03.2 原始 source / audit / package 指紋保留於 `evidence/exp03.2-v0.3.2-tested-release/`（離線已測，這輪日誌並非此版本）。

`python -B scripts/build_probe.py --phase exp04` 使用已鎖定 Loader helper，封裝同一 addon GUID / 單 Lua resource；比對 archive 內完整明文與測試 source hash。僅產出 ZIP，不寫入遊戲安裝目錄或覆蓋 Mod Manager 合併 archive。
