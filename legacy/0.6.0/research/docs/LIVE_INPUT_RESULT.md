> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# 第一輪實機輸入結果

2026-09-20（台北時間）。使用者回報已完成指定測試。

探針確實取得本次左右鍵輸入，記錄區間約 31.151 秒（update dt 累計），F6 開／關各一次、F7 標記一次，共 50 筆 input record。

| 項目 | 實際觀察 |
| --- | --- |
| 右鍵 | 8 次 PRESSED、8 次 HELD 狀態轉變、8 次 RELEASED，另有 1 次初始 BASELINE |
| 左鍵 | 8 次 PRESSED、8 次 HELD 狀態轉變、8 次 RELEASED，另有 1 次初始 BASELINE |
| 單独長按右鍵 | 約 2.896 秒，期間只有一次 PRESSED |
| 單独長按左鍵 | 約 2.294 秒，期間只有一次 PRESSED |
| 六次交替 | RMB → LMB → RMB → LMB → RMB → LMB，順序符合指示 |
| 最後雙鍵 | LMB 在 tick 13537，RMB 在 13538，差約 14.334 ms；兩鍵都有收到，之後同一 callback 放開 |
| 錯誤／不一致 | 未見 probe_error、log limit、重複 pressed、缺 pressed 的 down transition，或缺 released 的 up transition |

最後雙鍵是**相鄰 callback**，不標成精確同幀測試通過。人手近乎同時按下可能跨越採樣邊界，這次記錄本身没有顯示漏鍵。

本次證實 Lua Mouse API 在目前探針的 update 前階段可以取得獨立 pressed／released／button 狀態。這不能證明遊戲級 Fire／Aim mapping、當前武器、可獨立執行的 C4 Action、動作完成、彈量或同步。所有執行 Action 欄位仍是 NONE，下一研究重點仍為 C4 Action 邊界。

原始日誌與解析結果保存在 live-001-input (`../evidence/live-001-input/summary.json`; local research artifact)；tick 是 Lua callback 次數，時間差由 update dt 累計，非獨立量測的渲染幀號或實際輸入延遲。
