> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# 四組實機資料與使用者決定

來源 C4Actions_20260919T231639Z_001.log (`../evidence/live-exp03-C4Actions_20260919T231639Z_001-151089176853/C4Actions_20260919T231639Z_001.log`; local research artifact)，SHA-256 `15108917685392429f8b16f4517350296c01c1d43b337a3139cfb97e757fffee`，171 筆。session 明確記為 **0.3.1-exp03.1**；不能把這批資料當成 EXP03.2 pending 修正的實機證據。各組摘要與使用者回報分開存於 live-four-captures.json (`../evidence/live-four-captures.json`; local research artifact)。

| 組別（台北 2026-09-20） | 日誌結果 | 使用者回報／處理 |
| --- | --- | --- |
| 1，07:18:28 | F8 / F9 各 1 次；Deploy / Detonate 各 1 次完成；全程 Detonate mode，呼叫前後不變 | 正常；補齊 Detonate 模式中的獨立投擲 |
| 2，07:18:39 | F8 / F9 各 1 次 pressed；各持續 128 ticks；各 1 次動作完成 | 正常；長按未重複 |
| 3，07:18:51 | F8 8 次 / F9 1 次；Deploy 4 次、Detonate 1 次完成；4 次投擲被 rounds_chamber_blocked 拒絕 | 第二次投擲要等補彈，使用者接受沒有預觸發，不再以此阻擋後續實作 |
| 4，07:19:17 | 沒有動作輸入或呼叫 | 空組，忽略 |

前三組無 action fault。合併前輪 [Deploy 模式成功結果](LIVE_ACTION_SUCCESS.md)，已在兩種模式完成兩個獨立原生動作，使用者均確認基本行為正常，因此採 Route A 接上 EXP04 的 **RMB Deploy / LMB Detonate**。

保留原生補彈限制與已有一格 pending，不增加預觸發功能或延長期限。EXP03.2 那段等待 refill 的程式仍隨 EXP04 沿用，但只有離線證據，不能宣稱本次實機已驗收。這些 ammo 欄位是 selected magazine / chamber，沒有單獨量測背包；未據此宣稱背包、多人、移動及滑鼠映射已全部通過。

接下來僅驗證 [EXP04 滑鼠整合](DUAL_INPUT_README.txt)，不要求重做這三組測試。
