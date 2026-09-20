> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP04 多輪實測與自行停用調查

> 最新進度：EXP05 Xbox 已由使用者確認正常，最新 R 補彈停用原因已查明；EXP06 自動版本見 [LIVE_GAMEPAD_RELOAD_RESULT.md](LIVE_GAMEPAD_RELOAD_RESULT.md)。以下保留當時版本的調查／設計。

使用者確認滑鼠版多次測試動作正常，同時回報丟完背包與手中 C4 後像是自行停用，並明確表示沒有按 R 或開選單。分析保留這兩項回報，不能用舊版模糊的 stop reason 反推使用者操作。

兩份原始日誌已各自封存，逐組統計見 live-exp04-mouse-results.json (`../evidence/live-exp04-mouse-results.json`; local research artifact)。

| session（UTC） | capture 數 | Deploy 呼叫／生命週期結束 | Detonate 呼叫／生命週期結束 | 診斷 |
| --- | --- | --- | --- | --- |
| 20260919T234858Z | 9 | 45 / 44 | 66 / 66 | 末尾達 4 MiB 的 bounded_log_limit；最後一個 Deploy 未留下完整結束觀察，不能當作遊戲動作失敗 |
| 20260919T235729Z | 5 | 29 / 29 | 9 / 9 | 沒有 action_fault／probe_error／limit；五組都以 menu_or_mode_key 停用 |

兩份合計 149 次 native action call、148 次完整生命週期結束觀察，沒有 action_fault。第一份另有使用者 F6、失焦、選單類 stop，以及換出 C4 後再自動取得原 C4 gate；換出 C4 的 outside_c4 並不等於 F6 被關閉。

最新資料至少六次 Detonate 呼叫發生在 deploy_ammo_ready=false、chamber token 0 的狀態，含最後一組。由此可以確認 addon 的 Detonate 不以投擲就緒為前提；不能將 selected magazine 欄位獨自當成精確背包量測。使用者的「全部丟完」是額外的畫面回報。

## 能確認與不能確認的原因

EXP04 的 M.capture=false 分支沒有彈藥歸零條件。最新五次停用走的是 tick 裡 `down or pressed` 的選單鍵檢查，當時 C4 gate 仍是 owned。實際 binding ID：Escape 27、Enter 13、Tab 9、R 82、M 77，名稱也與引擎回報一致，因此不是已證實的按鍵名稱解析錯誤。

舊版只記 menu_or_mode_key，沒有保存是哪一鍵、原始值、pressed 邊緣或僅保留 down；無法區分殘留狀態、遊戲／其他軟體產生的訊號、或其他原因。使用者否認操作，所以目前應記為 **防護訊號來源未明**，不能寫成「使用者按了 R」，也不能說「丟空自動停用是正常」。

第一份長測的 4 MiB 容量限制則有直接證據：檔案 4,193,548 bytes，最後是 bounded_log_limit；EXP04 的該分支確實把整個 addon disabled。這是另一個獨立問題，不拿它解釋最新五組。

## EXP05 的處理

- 將永久停用條件改為有釋放基線的新選單 pressed 邊緣；單純保留 down 只暫停輸入，放開後重建動作基線。真實選單邊緣與失焦仍停用。
- 每個防護訊號保存 input、button_id、raw_value、raw_pressed、raw_released、previous_down、fresh_menu_edge；每個 capture stop 也附上觸發鍵。
- 循環保留四個各 4 MiB 的日誌，寫滿只換段，不停用功能。真實讀写失敗仍停止新呼叫並嘗試還原。
- 增加空 chamber 後保持啟用、允許引爆的離線回歸，以及 Xbox／PS 扳機路由。

這些修正不等同於空彈問題已實機排除。下一輪 Xbox 測試同時重現一次丟空狀態；如再發生，以 F7 及新 guard_input 確認具體來源。
