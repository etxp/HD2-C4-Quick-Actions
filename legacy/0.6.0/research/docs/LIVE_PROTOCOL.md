> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# 下一輪實機研究

EXP01 輸入與 EXP02 裝備／模式資料均已收到，見 [輸入結果](LIVE_INPUT_RESULT.md) 與 [裝備／模式結果](LIVE_CONTEXT_RESULT.md)。目前下一步是換用 EXP03 套件 (`../dist/C4-Action-Prototype-EXP03.zip`; local research artifact)，按 [測試鍵流程](ACTION_PROTOTYPE_README.txt) 先驗 F8 投擲，再驗 F9 引爆。

下面保留完整原版基準與後續 Action 驗收流程，並非這次要求全部重測。EXP03 目前仍是 F8/F9 測試鍵，尚未接上双滑鼠。

## 先收原版基準

1. 依 [探針說明](PROBE_README.txt) 使用既有 Mod 管理器啟用探針及 Bingus Shared Loader v15+。probe 不含 Loader；已存在的 Loader 不必重複安裝。
2. 進入單人、可自行控制的測試場景，取得 B/MD C4。记录遊戲 build、角色是否持有 C4、模式、可用數量、地上已部署數量；這些都不會由探針自動判定。
3. F6 開始記錄。先保持原版 Deploy 模式，依次單擊、長按與放開 LMB／RMB；再手動切 Detonate 模式重複。此時按鍵仍完全遵循原版設定。
4. 逐項做 [測試矩陣](TEST_MATRIX.md) 的六組快速輸入，使用 F7 標示每組開始。先觀察同幀雙鍵原版結果，不制定正式動作優先級。
5. 另外測選單、失去焦點／回到遊戲、換武器、零彈與動畫中輸入。檢查探針是否仍取得正確邊緣；不要將未知 current_weapon 自動補成 C4。
6. F6 停止，正常退出以 flush。保留日誌與人工紀錄；若沒有產生日誌，檢查 BingusSharedLoader.log 的 addon discovery／初始化錯誤。

本機預期日誌目錄：

```text
<local-home>/.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Local/CowboyBingus/Helldivers2/Logs/
```

輸入 API 顯示存在，不代表 pressed flag 在我們選定的 update 前階段一定有效。若實機僅看到 `DOWN_WITHOUT_PRESSED`，先調查引擎更新階段及焦點，保持觀察，不加入輸入注入補救。

## Action 研究的進入條件

先有可驗證的 local player／weapon instance／generation，再定位目前 build 的 Deploy 和 Detonate 候選入口。對每個候選保留呼叫簽章、原版 call site、native ammo／動畫／network path 證據。

Prototype A 只做一個測試鍵呼叫 Deploy；完成後 Prototype B 才加入 Detonate。兩者都要觀察**实际生成／消耗與引爆完成**，不能用函式回傳或動畫播放充當成功。直接路線亦需處理原 Fire／Aim 是否重複執行、action lock 與一格 pending buffer。

接雙鍵前明確記錄換武器、失焦、UI、死亡／ragdoll、未完成 action 的取消規則。未拿到動作完成訊號不能以固定幀數當完成。若需 Route C，等待 mode confirmation 時須核對同一 weapon instance 與請求身分；不能用 `set_mode(); fire()`。

## 人工觀察欄位

| 欄位 | 範例／規則 |
| --- | --- |
| session / F7 marker tick | 對應 `C4Boundary_*.log`；不要填 MOCK trace |
| build / game version | 由目前遊戲或檔案確認 |
| Solo / Host / Client / high ping | 真實測試條件；未知就填未知 |
| 原版模式 / 當前武器 | 每組測試開始與結束各記一次 |
| C4 charge count / deployed count | 前後數值，觀察來源寫明 |
| 測試輸入 | 點按、長按、交替、同時 |
| 實際結果 | 投擲／引爆／沒有動作／失敗及時間 |
| animation / sprint / ragdoll | 真實狀態及能否再次使用 |
| duplicate / wrong action / sync | 逐項記錄，不以 log 無 error 推定通過 |
