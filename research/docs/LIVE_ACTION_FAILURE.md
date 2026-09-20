> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# 最後一輪 EXP03 失敗診斷與 EXP03.1 修正

原因已定位在原型自己的 `unsupported_c4_weapon_driver_flags` 檢查。最後一輪 21 次 F8/F9 請求全部被拒絕，原版動作一次都沒有呼叫，與使用者回報「沒有生效」一致。這輪沒有證據指向按鍵順序，也尚未測到原版動作入口是否有效。

主證據是 C4Actions_20260919T224134Z_001.log (`../evidence/live-exp03-C4Actions_20260919T224134Z_001-765da50179c1/C4Actions_20260919T224134Z_001.log`; local research artifact)，SHA256 `765da50179c1bbd9d10de57d27e50055c4b8281589dfdc712e639005d780e0a9`。收集摘要 (`../evidence/live-exp03-C4Actions_20260919T224134Z_001-765da50179c1/summary.json`; local research artifact) 可重現計數。

| 最後實測資料 | 結果 |
| --- | --- |
| 版本／完整日誌 | `0.3.0-exp03`／114 列 |
| capture 起點 | 2026-09-20 06:43:23 台北時間，tick 7498 |
| 按鍵 pressed | F8 12 次、F9 9 次 |
| 動作拒絕 | 21 次 `no_fresh_c4_context` |
| 底層原因 | 12 次 context 樣本皆為 `mods/etxp/c4_boundary_probe.lua:324: unsupported_c4_weapon_driver_flags` |
| 原版呼叫／返回／active 觀察 | 全部 0 次 |
| 實際畫面結果 | 使用者回報未生效 |

較晚的 `C4Actions_20260919T224455Z_001.log` 只有啟動、binding 與 shutdown 資料，沒有 F6 capture 或 F8/F9；不能用它取代最後一輪實測。收集器現在會列出這類略過檔案，且同檔多次 capture 也以最後有測試活動的一組為主。

舊版假設 `flags & 0x799 == 0x408`，只支援 AbilityWeapon + WeaponResource。這個條件沒有實機依據；先前的合成 fixture 也只提供該值，因此 95 項離線檢查全過仍無法發現錯誤。斷言丟出後，外層又把部分 row 全丟掉，導致實際旗標值、已驗證的 C4 身分與模式從日誌消失，只剩 UNKNOWN 和泛稱拒絕。兩處都是原型的問題。

目前 binary 的 `0x73cf80` 明確有 WeaponRounds 路徑，歷史 C4 配置亦包含 WeaponRounds component；EXP03.1 已依目前 binary 實作此路徑，包括 entity override、resource template、selected magazine、chamber token 與補彈阻擋，消耗仍交給原版四函式流程。**因舊日誌未保留 flags，不能聲稱已在實機讀到 0x108，也不能在重新實測前宣稱問題已全部排除。**

修正版保留 flags、ammo 分支、讀取階段、具體錯誤。已讀資料不一致時仍丟棄整份 snapshot；動作擴充失敗時不產生可呼叫 capability。新增回歸涵蓋 chamber 與 magazine 不同狀態、空彈引爆、override、hash collision、非法索引、錯誤診斷落盤及多輪資料選擇，共 108 項離線檢查通過 (`../evidence/action-offline-tests.json`; local research artifact)。這些是合成環境與靜態檢查，不是遊戲成功證據。

EXP03.1 套件 (`../dist/C4-Action-Prototype-EXP03.1.zip`; local research artifact) 使用相同 GUID 取代旧版；[操作步驟](ACTION_PROTOTYPE_README.txt) 先只做 F6 → 放開 → F8 一次，確認投擲、扣彈、模式不變，成功才繼續 F9。無須再連按 21 次。舊版套件保留，原始程式／檢查／審計另存於 失敗版本封存 (`../evidence/exp03-v0.3.0-failed-release/manifest.json`; local research artifact)。
