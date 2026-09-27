> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# PRD 驗收矩陣

離線測試只覆蓋本探針，不把 mock 的 `input` 當原版 C4 的 `action`。

EXP01 已實機驗證獨立左右鍵；EXP02 確認裝備／模式／descriptor；EXP03.1 的兩輪已補齊兩種 mode 的獨立動作與長按。[四組結果](LIVE_FOUR_CAPTURES.md) 的空組忽略，補彈等待由使用者接受。EXP04 滑鼠版已由使用者確認多輪正常，149 次 call、148 次完整生命週期觀察，末尾一次受日誌上限截斷。EXP05 的 Xbox 已由使用者確認正常，最新日誌確認 R 補彈會永久停用，詳見 [本輪結果](LIVE_GAMEPAD_RELOAD_RESULT.md)。EXP06 改為自動模式，離線通過，使用 [新版流程](AUTOMATIC_README.txt) 驗證。指定壓力序列／幀率／多人仍不可由一般成功回報推定全部驗收。

| 項目 | 輸入觀察器（假引擎） | 原版／Prototype 實機 | 驗收重點 |
| --- | --- | --- | --- |
| RMB ×4 | 通過 | 未測 | 四次投擲是否依原版限制完成 |
| LMB ×3 | 通過 | 未測 | 引爆 timer／state 是否被重置 |
| RMB → LMB | 通過 | 未測 | 不把投擲誤當引爆 |
| LMB → RMB | 通過 | 未測 | 不把引爆誤當投擲 |
| RMB／LMB 交替 ×6 | 通過 | 未測 | 動作種類、數量、完成順序 |
| 同幀 LMB+RMB | EXP04 Detonate 優先、只呼叫一次通過 | 未測 | 同 callback 固定左鍵引爆優先 |
| Hold LMB／RMB | 雙鍵各自長按、RMB 已持續按住開始採集通過 | 未測 | 不額外重複引爆；原版 hold 行為另測 |
| 同幀按下與放開 | 通過 | 未測 | pressed／released flag 不丟棄；同幀多次邊緣無法由 boolean 完整還原 |
| 30／60／144 Hz callback | 通過 | 未測 | 只驗證 dt 與合成輸入紀錄；不代表實際 FPS／input latency |
| 立刻換武器、回到 C4 | EXP04 還原 flags、原版 Fire / Aim 放行、重建放開基線通過 | 未測 | identity guard、取消 pending、非 C4 不改動 |
| 零彈、補充／裝填 | EXP06 空彈→補給→R→投擲／引爆，不用 F6，mock 通過 | 使用者確認丟空／補給後映射正常，R 會停用；EXP06 修正待實測 | 使用原版 Empty／ammo／backpack 限制 |
| sprint／dive／prone／vault | 未測 | 未測 | 原版動作限制及完成訊號 |
| stagger／ragdoll／死亡 | 未測 | 未測 | 不強制取消動畫，不延遲誤觸 |
| throwing 未完成即引爆 | EXP04 沿用一格 pending、等待 native active / refill，離線通過 | 快速組完成 Deploy 4 / Detonate 1；補彈中投擲 4 次被拒絕，使用者接受 | 不再以預觸發功能阻擋實作；EXP03.2 refill pending 修正未獲實機證明 |
| Solo | 未測 | 未測 | C4 消耗、投擲、附著、爆炸 |
| Host／Client／高 ping | 未測 | 未測 | 原版 network path，無重複生成、消耗或引爆 |
| 原 callback／I/O 錯誤 | 通過 | 未測 | 多回傳值保留；探針失效不阻斷原遊戲 update |
| Test Key → Deploy | F8 已實作、離線通過 | Deploy / Detonate mode 都成功，長按各一次動作；使用者確認 | 已確認基礎跨模式；背包精確扣量未獨立量測 |
| Test Key → Detonate | F9 已實作、離線通過 | 兩種 mode 都成功且 mode 未變，長按無重複；使用者確認 | 真正零背包仍待驗收 |
| RMB Deploy / LMB Detonate | EXP05 延續既有滑鼠整合回歸通過 | EXP04 使用者確認多輪基本動作正常；有獨立的自動停用待查問題 | 原生 Aim 保留，精確壓力矩陣仍須分項證據 |
| Xbox LT / RT、PS L2 / R2 | EXP05／EXP06 兩種命名、兩種 mode × 30 / 60 / 144 Hz 與共用 edge／動作鎖通過 | EXP05 Xbox 使用者確認正常，有原生生命週期；PS 未測 | 不宣稱所有型號／USB／藍牙均驗證 |
| 日誌上限與 guard stop | EXP05 四段循環；EXP06 guard 暫停恢復與跨版本收集通過 | EXP05 最新 R 原始 pressed 與停用同 tick；EXP04 歷史模糊訊號仍未知 | 不將本次 R 證據追溯解釋舊的模糊事件 |
| 自動啟用、R／選單／失焦恢復 | EXP06 無 F6、held input 不重播、原 update 後再核對，mock 通過 | 待測 | 尤其需確認無游標的手柄 UI，Window 訊號不等同完整 UI 狀態 |
| Route C 狀態機／buffer | 未實作 | 未測 | 只有 A／B 都不可行才進入此階段 |

## 完整研究交付狀態

| PRD §24 | 狀態 |
| --- | --- |
| A：完整實際架構圖 | 配置、Action / Fire 原生鏈見 NATIVE_EXP03 / NATIVE_EXP04；基本跨模式已實機通過 |
| B：Deploy／Detonate YES／NO | 兩個原生入口在兩種 mode 均實機完成，使用者確認正常；基本獨立呼叫為 YES |
| C：Lua LMB／RMB／Fire／Aim | LMB／RMB 及 EXP05 Xbox 基本操作已實機成功，Aim 保留；PS 硬體待測 |
| D：兩個 Test Key Action Prototype | EXP03.1 基本實機成功，使用者接受補彈等待，不要求預觸發；EXP03.2 pending 修正仍僅離線證據 |
| E：實際雙鍵動作壓力測試 | 未完成；已完成離線與實機输入觀察，不是 C4 動作驗收 |
| F：A／B／C／NO-GO 最終選擇 | 採 Route A 實作 EXP06；自動恢復、完整壓力、移動、多人及 PS 驗收尚未結案 |
