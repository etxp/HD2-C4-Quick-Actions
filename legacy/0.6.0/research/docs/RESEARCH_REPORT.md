> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# 第一輪研究報告 — EXP01

日期：2026-09-20。狀態：已開始研究，PRD 第 24 節的完整交付條件尚未達成。

## 結論

已定位 C4 原版資源和可供觀察的 Lua 輸入 API；尚未取得可驗證的獨立 Deploy／Detonate 呼叫入口。維持 PRD 的 Route A 優先順序，沒有跳到自動切模式、OS 滑鼠攔截或自行生成炸藥。

| 問題 | 本輪答案 | 證據限制 |
| --- | --- | --- |
| Deploy 能否獨立呼叫？ | **未證實** | 沒有可驗證的函式、參數、所有權與完成訊號；不能填 YES，也不能因搜尋未命中就填 NO |
| Detonate 能否獨立呼叫？ | **未證實** | `WeaponFunctionType_Detonate` 是配置枚舉線索，不是函式位址或 Action ID |
| Fire Mode 是 Action 選擇器還是 weapon state？ | **未證實；有新線索** | 舊配置的 `primary_fire_mode=Single`，`function_info.left=Detonate`，顯示選單概念可能不同於 FireMode enum；尚無現版執行流程證據 |
| Lua 可取得 LMB／RMB？ | **API 表面存在；本探針實機讀取未驗收** | 本機先前實機 catalog 列出 Mouse API，但沒有本輪左右鍵讀值、時序或焦點測試 |
| Lua 可取得 Fire／Aim？ | **未證實** | 滑鼠按鍵不等於重新綁定後的遊戲 Action；API catalog 未提供已確認的 Fire／Aim reader |
| Current Player／Weapon／Mode／Ammo／Animation？ | **本探針未取得** | 記錄為 UNKNOWN，沒有以場景內存在 C4 模型冒充玩家正持有 C4 |
| 建議 Route？ | **研究順序仍為 A → B → C；最終決策待定** | A／B 都未排除，因此現在選 GO-C 或 NO-GO 沒有根據 |

PRD 要求研究結束時給 YES／NO 與最終路線；本輪不是研究結案，因此保留未知，避免誤報。

## EXP-001：目前遊戲的資源擷取

使用已存在的 SQLite 索引定位，再向**目前遊戲**重新讀取相應 archive TOC，逐一核對 build 與 SHA256。共核對 6 個 archive（含 vanilla Lua 啟動 archive），找到 22 個 C4 相關 resource occurrence，擷取 17 個 TOC payload。未擷取大型 GPU／stream 渲染內容。

引爆器 `51f50d6321f52f3d.unit` 在 `+0x20` 引用同 ID 的 `.state_machine`。該 572-byte 檔案解出一個 layer、兩個 clip state：`idle` 與 `idle_hellpod`。它連到兩個動畫資源，**不是已找到投擲／引爆 gameplay state machine**。此外解讀僅涵蓋動畫索引與事件部分，沒有把未知欄位當成操作入口。

詳見 資源列表與 SHA256 (`../evidence/local-resources.json`; local research artifact)、有格式依據的解碼結果 (`../evidence/state-machine.json`; local research artifact)、[關係圖](RESOURCE_MAP.md)。`raw_reference_candidates` 僅為 byte-match 線索，與 `schema_decoded` 分開標示。

## EXP-002：配置與 Lua 邊界

固定版本 RawData 的 metadata 是 **2026-07-07 / 1.006.301**，不是目前遊戲 runtime。從中取出 C4 的四個 component record 和兩個相關 settings record，保留 JSON pointer 與版本資訊。

- 引爆器 WeaponData：`primary_fire_mode = 2 / FireMode_Single`，secondary／tertiary 為 None；`function_info.left = 11 / WeaponFunctionType_Detonate`。這個 `left` 是 weapon function 欄位，沒有證據表示滑鼠左鍵。
- C4 本體具有 Throwable 配置；animation hash 對照候選為 `arm_grenade`、`throw_far`、`throw_short`。這些動畫名稱不能當完整原版 Action 呼叫。
- 引爆器 WeaponRounds 指向 projectile type 54；相關 settings 的 `projectile_unit_path=0`，不能直接宣稱它會生成 C4 unit。背包到 Throwable 的實際建立與消耗流程仍待追蹤。
- Lua 歷史 catalog 共 2,567 項，範圍為 `stingray` 兩層；包含 Mouse 的 `button_id / button / pressed / released` 以及 `Input.event_queue`，未找到已確認的遊戲級 Deploy／Detonate API。範圍不含全部 global、native code、方法語意與可呼叫性。

Autodesk 的 [Mouse API 文件](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/ns_stingray_Mouse.html) 說明如何按名稱取得按鍵 ID，以及查詢本幀按下、放開與目前數值。HD2 的實際更新階段與焦點行為仍需測試。[Input.event_queue 文件](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/ns_stingray_Input.html) 可作未來同幀多次邊緣研究依據；目前探針沒有呼叫或消耗 queue。

完整摘取結果：RawData C4 記錄 (`../evidence/rawdata-c4.json`; local research artifact)、歷史 API 分析 (`../evidence/historical-api-analysis.json`; local research artifact)。

## EXP-003：唯讀 runtime 探針與离線驗證

實作 [c4_probe.lua](../../src/c4_probe.lua)，封裝為 Loader v15+ 可 discovery 的單一 Lua addon。初始化時有界列舉 API 名稱與型別；F6 開／關輸入紀錄；F7 做人工標記。僅呼叫文件化的裝置查詢，不執行搜尋到的候選函式。

每筆主要事件含 PRD 要求的時間、tick、武器、模式、輸入、請求、執行、pending、lock、result 欄位。無資料的武器／模式是 UNKNOWN，`executed_action=NONE`。同時按下保留兩筆按鍵事件及一筆 simultaneous 記錄，不預設動作優先級。持續長按只記錄狀態轉變；同幀 pressed+released 另行保留。

probe 每次 Lua update 前觀察裝置；tick 是 callback 次數，時間精度不得冒稱引擎 Frame ID 或單調系統時鐘。`elapsed_ms` 僅為有效 update dt 累計。日誌有界、每 60 callbacks flush，I/O／API 出錯會停用探針並繼續原 callback。沒有 OS hook、遊戲記憶體寫入、action adapter、Aim 改寫或 mode switching。

**31 項離線測試通過**，包含各種點按、雙鍵各自長按、同幀雙鍵、同幀按下放開、已按住時開始採集、30／60／144 Hz 假 callback 時序、數字 0 的 Lua truthiness、I/O 故障、初始化失敗、callback 多回傳值及日誌上限。最後一組 JSONL 另外驗證可解析性與必要欄位；數量見測試 evidence。這些不驗證 C4 動作、timer、ammo、動畫或 networking。

封裝檢查確認只有 `mods/etxp/c4_boundary_probe`，無原版 boot／Wwise resource override；plaintext 與來源逐 byte 相同，sidecar 為空。此包不包含 Loader，未做實機安裝與 Mod 管理器部署測試。

證據：離線測試 (`../evidence/offline-tests.json`; local research artifact)、封装結果 (`../evidence/package.json`; local research artifact)。

## 尚待完成

1. 以 [實機流程](LIVE_PROTOCOL.md) 記錄原版 C4 行為及新探針的輸入時序，核對前後更新階段與 UI／焦點影響。
2. 找到可靠的 local player、當前武器 instance 與 generation；只識別模型或背包並不足以建立 C4 guard。
3. 追蹤 `WeaponFunctionType_Detonate` 的現版消費者，分清選單狀態、動作 dispatcher、完成回報與網路所有權。
4. 先完成「測試鍵 → 原版 Deploy」，再完成「測試鍵 → 原版 Detonate」。動作未驗證前不接左右鍵路由。
5. 只有 A 失敗才試 B；只有 A／B 都不可行才建立 C 的 mode-confirm 狀態機。不得使用固定延時假裝 Mode Confirmed。

正式 Action 測試必須另外觀察原版 LMB／RMB 是否仍觸發 Fire／Aim，避免原輸入與新呼叫各執行一次。能力探針並未解決這個問題。
