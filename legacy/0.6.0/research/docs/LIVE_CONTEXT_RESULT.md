> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# EXP02 實機結果

來源：`C4Context_20260919T215817Z_001.log`。原始封存與摘要 (`../evidence/live-exp02-C4Context_20260919T215817Z_001/summary.json`; local research artifact)。這輪探針沒有呼叫遊戲動作。

90 筆記錄中有 62 次 context 取樣；44 次選取 C4、18 次選取其他武器。磁碟 game.dll SHA256 與六處執行中程式指紋吻合。沒有 snapshot failure 或 probe error，最高記錄取樣成本約 1 ms。

| Lua callback tick | 觀察 |
| --- | --- |
| 8978 | 標記：主武器，slot 1，resource `a7ee1ebf58fcdf1f` |
| 9174 | 切到 C4，slot 3，resource `51f50d6321f52f3d` |
| 9601 | 標記：C4，selector 0 |
| 9927 | LMB pressed，可能對應投擲；畫面結果未確認 |
| 10369 | selector 從 0 變 1 |
| 10718 | LMB pressed，可能對應引爆；畫面結果未確認 |
| 11073 | selector 從 1 變 0 |
| 11261 | 標記：C4，selector 0 |
| 11840 | 標記：主武器，slot 1 |
| 12426 | 標記：再次選取 C4，selector 0 |

共五個 F7 標記，少了原流程的中間標記。原始狀態記錄仍完整包含 0 → 1 → 0 與換武器，因此不用因標記數量而重測整輪。標記順序不能單獨證明實際生成或爆炸。

本版 C4 功能 type 為 **10**，packed word 的 bit 8–9 是 selector；歷史 RawData 的 type 11 不適用。C4 模板的 descriptor 0 為 weapon ability **521**、消耗旗標 1；descriptor 1 為 ability **520**、消耗旗標 0。兩者的 owner／other ability 均為 0，restart 旗標均為 1。

descriptor 的 HUD resource 分別為 Deploy `38adabc6a32af014` 與 Detonate `55374383474193f8`。配合本版 native dispatch，521 在動畫事件中引用 C4 charge 資源，520 在動畫事件中進入原版 remote explosives 流程，已能辨識兩個動作的配置與 handler。

**可以進入測試鍵原型，但尚不能宣布 GO-A。** 原版畫面的投擲與爆炸結果仍未取得明確確認；EXP03 的独立呼叫也尚未實機執行。新原型與完整呼叫鏈見 [EXP03 紀錄](NATIVE_EXP03.md)。
