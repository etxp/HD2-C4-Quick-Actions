Historical instructions for the named experiment; see ../../README.md for the current release.

C4 Dual Input EXP04 / v0.4.0 — 右鍵投擲、左鍵引爆 / build 24826606

安裝
1. 退出遊戲，在既有 Mod Manager 匯入 C4-Dual-Input-EXP04.zip，取代先前 C4 測試版。
2. 各版共用 GUID / Lua resource，只啟用 EXP04；保留原有 Bingus Shared Loader v15+。
   不要手動覆蓋 Mod Manager 合併中的 patch_0。
3. 重新啟動遊戲。此版預設關閉；F8 / F9 不再是動作測試鍵。

操作
- 拿出 C4 引爆器，放開左右鍵，按一下 F6 啟用，再放開 F6。
- RMB：投擲一顆。LMB：引爆。兩個原版模式均使用這個映射，不切換模式。
- 再按 F6 停用。若正按住滑鼠，等左右鍵放開才還原原版 Fire，避免把長按重播成射擊。
- 長按只算一次新動作；同一個 callback 同時按左右鍵時，左鍵引爆優先。
- 補彈未完成時仍不能投下一顆。沿用既有一格 pending / 1.5 秒期限，不保證補彈中的按鍵會預觸發。
- 換其他武器時恢復原版射擊與瞄準。切回 C4 後先放開左右鍵，再按新的一次。
- Esc、Enter、Tab、R、M 或切出遊戲會自動停用；關閉選單、回到遊戲後重新按 F6。
- F7 可以標記觀察時點。

這次只需確認新的滑鼠整合
1. 單人場景、站立靜止、備有 C4：F6 啟用後，右鍵按一下。
   應只有一次投擲、背包少一顆。等動作結束後左鍵按一下，應引爆已投出的 C4。
2. 換回主武器，確認左鍵射擊與右鍵瞄準正常。
3. F6 停用。回報投擲／引爆、是否多丟一顆、主武器是否正常即可。
前一輪的模式與長按測試已記錄，不要求重做。這次首次實機驗證滑鼠路由與 Fire 消重。

實作範圍
沿用已測到的原生 Deploy 521 / Detonate 520 與原生扣彈、動畫、後續流程。
只在本機目前持有的同一把 C4 上暫時停用原版 Fire 動作分支，停用或換武器時還原。
原生 Aim 保留，所以右鍵原有的姿態／視角處理仍可能存在；這次沒有重寫 Aim mapping。
不修改模式、傷害、容量或同步程式。原版地面狀態、動作鎖與彈藥限制仍生效。
地面以外的角色狀態、多人及完整壓力測試尚未完成。
模組或程式碼指紋不符時不啟用；發生記憶體、日誌或動作故障時停止新呼叫並記錄原因。
短暫還原失敗會在後續 update 重試；若 C4 操作異常，先放開滑鼠並停用，再提供日誌。

日誌
%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/C4DualInput_*.log
session version 應為 0.4.0-exp04。
fire_gate_status=owned 表示本把 C4 的原版 Fire 已暫停；native_aim_behavior=UNCHANGED。
NATIVE_LIFECYCLE_ENDED 表示觀察到原生生命週期結束，不單獨證明實際投擲／爆炸。
本機收集指令：python -B scripts/collect_actions.py --phase exp04
