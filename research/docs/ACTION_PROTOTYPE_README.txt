Historical instructions for the named experiment; see ../../README.md for the current release.

C4 Action Prototype EXP03.2 / v0.3.2 — 等待原生補彈的單格緩衝 / build 24826606

EXP03.1 已記錄 7 次 Deploy、2 次 Detonate 完整生命週期，使用者回報測試成功；當時全程為 Deploy 模式。
本版修正排隊 Deploy 在動畫結束、下一顆尚未就緒時被丟棄的問題。
只保留一格 pending，等待原生補彈就緒，沿用原本 1.5 秒期限，不延長期限、不繞過彈藥限制。
114 項離線檢查已通過；本版緩衝修正仍待實機驗證。
先在單人場景、站立靜止時測試。
此輪依 PRD 分開驗證動作：F8 投擲、F9 引爆；左右鍵仍是原版行為。

安裝
1. 退出遊戲。
2. 在既有 Mod Manager 匯入 C4-Action-Prototype-EXP03.2.zip，取代 EXP03.1 或更舊版本。
   各版共用 GUID / Lua resource，只啟用 EXP03.2；不要手動覆蓋合併中的 patch_0。
3. 保留原有 Bingus Shared Loader v15+（runtime version >=16 / API 1），再啟動遊戲。

第一組：補齊 Detonate 模式中的獨立投擲
1. 補滿 C4 背包，拿出引爆器。各組之間如需補充，先按 F6 停用，再補充。
2. 用原版操作切到 Detonate 模式，關閉模式選單，放開所有按鍵。
3. 按一下 F6 啟用測試，放開；站著不動，按一下 F8。
4. 確認實際丟出一顆、數量減一、HUD 模式仍為 Detonate；完成動畫後按 F7 標記。
5. 如果投擲成功，按一下 F9，確認已部署 C4 實際爆炸，完成後按 F7。
6. 按 F6 停止。若 F8 沒動作或數量不正確，先停在此處，回報畫面結果即可。

第二組：長按不重複
第一組正常才做，維持 Detonate 模式。F6 啟用，放開所有按鍵。
長按 F8 約 3 秒 → 放開，應只投一顆、背包只少一顆。
等動作完成，再長按 F9 約 3 秒 → 放開，應只觸發一次引爆動作，之後仍能正常使用。
F7 標記 → F6 停用。

第三組：快速輸入與一格 pending
F6 啟用，放開所有按鍵；每個小測試前先等上一動作及補彈完成。
A. F8 按一下 → 約 0.2 秒內按一下 F9。應先完成投擲，再引爆，不重啟投擲動畫；F7 標記。
B. 確認至少兩顆可用，F8 快按兩下（約隔 0.2 秒），隨即完全放開。
   應共投兩顆；第二顆等待原生補彈完成才執行，兩次都只扣一顆。
   等動作完成，按 F9 清掉部署的 C4；F7 標記 → F6 停用。
本輪先不加更多連點；若第二顆沒出來、重複或卡住，就停在該項回報。

這三組之後才接正式 RMB / LMB，並安排換武器、真正空背包、移動狀態、同幀優先級及多人驗收。

觀察限制
- 按 Esc、Enter、Tab、R、M 或切出遊戲會自動停用測試，回來後須重新按 F6。
- 按滑鼠時不接受同時的測試鍵，避免與原版 Fire / Aim 重疊。
- 原版動作 active 時不重啟；最多保留一個 pending，1.5 秒後過期。
- 非 C4、身份變動、失焦、資料失效會丟棄 pending，不會强制中止原版動畫。
- 超過 8 秒未觀察到結束會鎖住本次 addon 的新呼叫；記錄日誌後重啟遊戲調查。
- Deploy 須通過原生彈藥就緒條件，保留已上膛最後一發與補彈中限制。Detonate 不受剩餘彈藥限制。
- 此版先限制在保守的本機角色地面狀態；翻滾、踉蹌等狀態另留後續驗收。

日誌
%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/C4Actions_*.log

NATIVE_CALL_RETURNED、NATIVE_ACTIVE_OBSERVED、NATIVE_LIFECYCLE_ENDED 都不是實際投擲／爆炸成功的宣告。
新日誌 session 的 version 應為 0.3.2-exp03.2。失敗時會保留 weapon_driver_flags、ammo_path、action_read_stage 與具體原因。
pending_waiting 表示保留單格請求、等待原生補彈，不是已執行动作。
請回報哪一組完成或異常，以及投擲數量、背包扣量、爆炸、模式是否正確。
F7 的精確先後不影響原始狀態紀錄。collector 預設只摘要最後有測試輸入的一組；全部原始 capture 仍保留。

此版本不改傷害、容量、物理或同步程式；透過原版 ability 生命週期、消耗與後續處理執行。
多人、快速交替、空背包引爆及右鍵／左鍵正式映射仍待後續驗證。
