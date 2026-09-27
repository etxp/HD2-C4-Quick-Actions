> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP03.1 實機動作結果與下一轮

此頁保留 07:08 那輪結果與當時的下一步。後續 07:18 的四組資料已补齊反向跨模式與長按，補彈等待由使用者接受，見 [最新結果](LIVE_FOUR_CAPTURES.md)。目前直接進入 [EXP04 滑鼠映射](DUAL_INPUT_README.txt)，下面的「下一輪 EXP03.2」不再是目前測試要求。

使用者回報「測試成功」。最新實測為 C4Actions_20260919T230700Z_001.log (`../evidence/live-exp03-C4Actions_20260919T230700Z_001-f2aaf94bb1c2/C4Actions_20260919T230700Z_001.log`; local research artifact)，版本 `0.3.1-exp03.1`，capture 從台北時間 2026-09-20 07:08:43 開始。摘要 (`../evidence/live-action-success.json`; local research artifact) 同時保留使用者畫面回報與可由日誌確認的範圍。

- F8 pressed 16 次、F9 pressed 2 次。
- Deploy 7 次、Detonate 2 次，均觀察到 call、returned、active、finished，無 action fault。
- 全程為 Deploy 模式，9 次呼叫前後 mode 均未改變。已觀察到 2 次跨模式 Detonate；**Detonate 模式下的 Deploy 尚未測到**。
- 真實 flags 為 `0x1148`，ammo path 為 WeaponRounds，resource template 的 chambered 非零。這次實機確認了 EXP03.1 新補的分支；舊錯誤條件會把 `0x1148 & 0x799 == 0x108` 拒絕。
- selected magazine count 全程為 0；就緒時 chamber token 為 55。它不是背包數量，不能用日誌中的 ammo delta 0 推斷沒有扣彈，也不能據此宣布已通過零背包測試。精確背包扣量與網路角色尚未回報。

9 次 Deploy 拒絕均因 `rounds_chamber_blocked`。其中 5 次是直接請求遇到尚未就緒狀態；另 4 次原本已進入 pending，卻在 native active 轉 false 時立即出列，再因 chamber 尚未就緒而被丟掉。這是緩衝處理的缺口；不能把它們全歸類為正常限速。

| 排隊 tick | 出列後拒絕 tick | 等待時間 |
| --- | --- | --- |
| 7531 | 7551 | 約 294 ms |
| 7663 | 7683 | 約 294 ms |
| 7731 | 7751 | 約 288 ms |
| 7799 | 7819 | 約 291 ms |

EXP03.2 保留這一個 pending Deploy，直到原生 chamber ready 或原有 1.5 秒期限到期；不修改遊戲補彈狀態，不重啟動畫，不因重複按鍵延長期限。武器切換、失焦、原版滑鼠輸入、無效 snapshot、原生排斥條件或其他 action 仍會取消請求。114 項離線檢查通過，包含依本輪「magazine 0、chamber 就緒 → 投擲 → active 結束但 chamber 未就緒」時序建立的回歸；此修正尚未實機驗收。

下一輪用 EXP03.2 (`../dist/C4-Action-Prototype-EXP03.2.zip`; local research artifact)，按 [操作流程](ACTION_PROTOTYPE_README.txt) 做三組：Detonate 模式下投擲、長按、投擲中快速排隊。這些測試補齊動作條件後，再接 RMB Deploy／LMB Detonate；Fire/Aim 消重、真正空背包、換武器、移動、同幀及多人矩陣仍待驗收。尚不把基本成功擴張成整份 PRD 結案。
