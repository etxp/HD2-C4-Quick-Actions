> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP06 自動 C4 路由

## 原因與行為

EXP05 將 R 的新 pressed 邊緣轉成永久 `capture=false`。最新實機 tick 6941 與使用者補彈描述吻合，詳見 [重現證據](LIVE_GAMEPAD_RELOAD_RESULT.md)。EXP06 不再讀取 F6；啟動時開啟自動模式，每次 callback 依本機裝備與輸入狀態決定是否接管 C4。

共用原版 action、ammo、動作鎖、一格 pending、滑鼠 edge 與手柄類比處理，這些核心模組與使用者已測的 EXP05 相同。滑鼠 RMB／LMB、Xbox LT／RT、PS L2／R2 映射保留；原生 Aim 不改動。EXP05 的 ZIP 及來源證據已 保留 (`../evidence/exp05-v0.5.0-tested-release/manifest.json`; local research artifact)。

## 暫停與恢復

`gameplay_guard.lua` 讀取同進程前景視窗、引擎鍵盤焦點與游標可見狀態，配合既有按鍵 guard。R／選單鍵不再清除 capture，僅在 down／pressed 時暫停。暫停或失去 C4 identity 時取消 pending，重設 router；回來後需放開兩個滑鼠鍵與扳機，再按下一次才產生動作。

`automatic_tick.lua` 在原 update 前讀取狀態並處理輸入；原 update 後再次檢查視窗與裝備，避免原 update 開啟 UI 後仍保留 pending。Fire gate 的原有 entity 查找與還原機制不變：非 C4 恢復原版，held input 尚未放開時延後還原，避免將同一次長按重送為原版 Fire。

`Window.has_focus()` 與 `Window.show_cursor()` 可省略 window 參數讀取主視窗，回傳焦點及游標狀態。`Window.mouse_focus()` 只紀錄，不作必要條件，以保留手柄輸入。API 語義依據 [Autodesk 官方 Window 文件](https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Window.html)；本機 API catalog 已列出這些函式，但尚未實測 HD2 在各種 UI 中的值。

**已知限制：游標可見並非完整的遊戲 UI 狀態。** 未顯示游標的手柄選單／聊天等 UI 是否還需額外訊號，仍待本輪實測；不將 mock 的 cursor 行為當成 HD2 全選單驗證。API 缺少、拋錯或回傳不支援的值時不自動接管，日誌記錄 `window_state_unavailable`。不改游標、焦點或引擎綁定。

`M.capture` 現在只表示自動模式仍在運作；`gameplay_guard.runtime_state` 說明暫停原因，`fire_gate_active` 才表示目前接管本把 C4。錯誤停用仍會 latch：真實記憶體／I/O 核對錯誤或原 update 例外會還原並停止本次模組，不能自動重新呼叫 native action。原 update 的例外與多回傳值仍原樣傳回。

## 檢查與打包

```bash
python -B scripts/check_automatic.py
python -B scripts/build_probe.py --phase exp06
python -B scripts/collect_actions.py --phase exp06
```

[離線結果](../../evidence/automatic-offline-tests.json) 覆蓋無 F6 啟用、三種輸入 × 兩種 mode × 三種 callback rate、空彈→補給→R→兩種動作、暫停取消 pending、held input、UI／焦點恢復、熱插拔、未知裝置、原 callback／日誌錯誤。既有核心回歸與循環日誌／collector 也通過。新狀態以 mock 提供，無法證明真實遊戲的 UI 或動畫效果。

封裝會核對本次檢查的來源與檔案指紋，仍只有原本一個 Lua addon resource，沿用同一 GUID 以替換舊版。只產生 ZIP，不直接安裝或修改 Manager 合併結果。
