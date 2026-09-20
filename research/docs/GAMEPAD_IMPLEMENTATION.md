> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP05：滑鼠與 Xbox／PS 的共同原生動作路由

> 最新進度：EXP05 Xbox 已由使用者確認正常，最新 R 補彈停用原因已查明；EXP06 自動版本見 [AUTOMATIC_IMPLEMENTATION.md](AUTOMATIC_IMPLEMENTATION.md)。以下保留當時版本的調查／設計。

EXP04 的 Fire gate 與四個 native Action ABI 原樣沿用，遊戲 build / hash / 34 段 signature 與 [NATIVE_EXP04](NATIVE_EXP04.md) 相同。新增內容是引擎手柄輸入、鍵盤防護診斷及循環日誌，沒有新增 native game function pointer、記憶體寫入位置、OS 輸入注入或裝置全域 dead-zone 設定。

本機既有 live API catalog 已列出 Pad1～Pad4 的 active / button_id / button_name / button 等方法；尚沒有本輪手柄的 runtime value 證據。官方 [Pad API](https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/ns_stingray_Pad1.html) 與 [PS4Pad API](https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/ns_stingray_PS4Pad1.html) 提供兩套 trigger 名稱與 active 語意；這些一般引擎文件是實作線索，不取代 Helldivers 2 的實測。

`gamepad_input.lua` 優先第一個 active Pad，再檢查 PS4Pad，維持選定裝置直到斷線。使用 `active()` 判斷連線存續；不把只代表本幀接入事件的 connected() 當持續連線。button_id 必須通過 button_name 反查，兩個 trigger ID 必須不同。所有 trigger 值有限且在 0..1，55% 按下、25% 放開、10% 啟用基線。未知裝置 profile 保留原版操作並記錄有界 button catalog；沒有猜測數字 ID。

`dual_input_tick.lua` 將 LMB / RT / R2 合併成 Detonate edge，RMB / LT / L2 合併成 Deploy edge，使用既有 MouseRouter。相同動作的鏡像輸入共用 held 狀態，不額外送第二個請求；兩個動作同 callback 則 Detonate 優先。action_controller 的 input label 可由請求攜帶，pending 另保存 original_input，仍保持原有 action lock、容量一及期限。

裝置 epoch 變動立即清除 pending，並使 router 重新等待全放開。整個 Fire gate 的取得／還原均考慮滑鼠與手柄；停用時 RT 還未放開，不立刻把同一扳機長按重播成原版 Fire。原生 Aim 保留。Xbox／PS 介面若同時鏡像同一把手柄，只選一個，不同時路由兩個來源。

PS 介面是否存在、原生 PS 熱插拔與 USB／藍牙可用性由遊戲／Steam 決定；沒有呼叫新的硬體掃描函式。Steam Input 將 PS 提供為標準 Xbox pad 時可走相同 trigger profile。實作覆蓋的是遊戲提供的標準介面，不能據此保證所有第三方手柄／任意重映射配置都相容。

`input_guard.lua` 保存原始 guard 值並區分 fresh press、持續按住與變動；詳見 [停用調查](LIVE_MOUSE_RESULT.md)。`rolling_log.lua` 每 session 四個 slot，段首寫單調遞增 segment；collector 按序號合併，保留原始 parts 及各自 SHA-256，標明早期資料已覆寫、缺段與尾端不完整寫入。跨段的 native lifecycle 仍可合併，不能按 part 檔名排序推斷新舊。

離線檢查：`python -B scripts/check_gamepad.py`。覆蓋 Xbox／PS 兩種 mode × 三種 callback rate、持續按住與類比抖動、鍵鼠鏡像、雙鍵優先、裝置重連、原 Fire 還原、空 chamber 引爆、guard 診斷，以及日誌循環／collector 跨段。結果見 gamepad-offline-tests.json (`../evidence/gamepad-offline-tests.json`; local research artifact)，全為 synthetic memory／mock Windows／mock native API；Xbox／PS 都仍待實機驗證。

封裝：`python -B scripts/build_probe.py --phase exp05`，單 Lua resource／原 GUID，ZIP 不含 Loader 或原遊戲 payload，不自動安裝。
