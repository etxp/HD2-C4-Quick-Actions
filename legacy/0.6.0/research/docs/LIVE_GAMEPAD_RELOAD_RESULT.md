> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP05 手柄成功與 R 補彈停用

使用者確認 Xbox 操作正常。最新一次明確重現：丟空 C4 與拾取補給後，滑鼠映射仍正常；按 R 拿出一顆 C4 後，需 F6 重新啟用。新日誌可確認這次停用由 R 的新按下邊緣觸發。

## 最新一輪為主要證據

`C4DualInput_20260920T003259Z_001_part1.log`，版本 `0.5.0-exp05`，267 筆記錄：

- tick 5753 啟用，Deploy 7 次、Detonate 11 次，18 次皆有完整 native 生命週期；沒有 action_fault / probe_error。
- **tick 6941（2026-09-20 00:34:42 UTC / 08:34:42 台北）**，鍵名 `r`、ID 82，`raw_value=1`、`raw_pressed=true`、`fresh_menu_edge=true`。
- 同一 tick 記錄 `capture enabled=false`，`reason=menu_key_edge`、`input=r`。
- tick 6951 已放開 R，但舊程式不會自行恢復，符合使用者必須重新按 F6 的描述。

因此這次有明確的按鍵與程式路徑證據。EXP05 的 `dual_input_tick.lua` 會在 `InputGuard` 回傳新選單按鍵邊緣時設 `M.capture=false`；R 原本列在選單／模式防護鍵內，實際上也會用來裝填。空彈與拾取補給本身不在這條永久停用條件中。

原始與合併檔：最新一輪 (`../evidence/live-exp05-C4DualInput_20260920T003259Z_001-dc0b45c8446d/summary.json`; local research artifact)。

## 前一輪用於佐證手柄

`C4DualInput_20260920T002528Z_001_part1.log`，1238 筆、5 個 capture。全 session 有 Deploy 54 / 54 完成、Detonate 32 / 32 完成，無 native action / probe fault。Pad1 識別為 Xbox，LT / RT 按下分別 34 / 10 次；實際 native action_call 來源含 LT 25 次、RT 9 次。輸入與動作不必一對一：動作鎖、pending、原生狀態仍可限制執行。

這一輪也有四次 R 同 tick 停用（8700、10244、11111、22758），另一次是 Esc。使用者的手柄成功回報補足實際操作結果；不能據此推定 PS 硬體或所有連線方式都完成驗收。

原始與合併檔：手柄一輪 (`../evidence/live-exp05-C4DualInput_20260920T002528Z_001-a5e043203dfa/summary.json`; local research artifact)。其 collector 預設只分析最後一個 capture；上述次數由保留的完整 session 計算，見 兩輪完整核對 (`../evidence/live-exp05-reload-result.json`; local research artifact)。

先前 EXP04 的模糊 `menu_or_mode_key` 記錄仍無法追溯確切來源；本次新證據只解決這次明確的 R 補彈重現，不改寫舊回報。

## EXP06 修正

新 [自動版本](AUTOMATIC_README.txt) 依目前裝備的本機 C4 自動接管，取消 F6 啟用需求。R 與可觀測的 UI／失焦訊號只暫停輸入，回到可操作狀態且按鍵放開後恢復；取消暫停期間尚未執行的 pending。補彈仍由原版流程控制，不增加預觸發。

EXP06 的恢復與 Window 訊號目前只有離線檢查，待實機驗證。詳細實作與限制見 [自動啟用設計](AUTOMATIC_IMPLEMENTATION.md)。
