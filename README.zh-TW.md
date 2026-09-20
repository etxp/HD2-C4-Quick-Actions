![HD2 C4 Quick Actions — C4 實機畫面封面](assets/cover.png)

# HD2 C4 Quick Actions

[English](README.md)

讓《絕地戰兵 2》的 C4 **投擲與引爆分開操作**，支援滑鼠與手柄，拿出 C4 即自動啟用。

| 輸入裝置 | 投擲 C4 | 引爆 C4 |
| --- | --- | --- |
| 滑鼠 | 右鍵 | 左鍵 |
| Xbox 手柄 | LT | RT |
| PlayStation 手柄 | L2 | R2 |

拿出 C4，先放開滑鼠左右鍵與兩個扳機，即可使用。**不需要按 F6。** R 維持原版補彈流程，補彈完成後可繼續操作；切回其他武器時恢復原本開火操作。

## 安裝

1. 退出遊戲。
2. 安裝 [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader) **v15+ / API 1**，已安裝者保留原有版本。
3. 將 [HD2-C4-Quick-Actions-v0.6.0.zip](dist/HD2-C4-Quick-Actions-v0.6.0.zip) 匯入 Mod Manager，啟用本模組與 Loader，再部署。
4. 取代先前 C4 實驗版本（EXP01～EXP06），同時只啟用一個 C4 版本。

`dist/` 內的 ZIP 是安裝包；GitHub 的 Source code ZIP 則是開發資料。Loader 需另外安裝。移除時，由 Mod Manager 停用本模組並重新部署。

## 操作細節

- 投擲、引爆各自對應固定按鍵，不受目前 C4 射擊模式影響。
- 長按不連發；同時按投擲與引爆時，引爆優先。
- 補彈時間、動畫與原版動作限制保留，不新增補彈預觸發。
- R／選單鍵、失焦或顯示游標時暫停動作；回到操作狀態並放開按鍵後自動恢復。
- 暫停會取消尚未執行的 pending，避免回來後突然觸發。
- 扳機達 55% 行程視為按下，25% 以下釋放；重新接管時需回到 10% 以下。
- 原版 Aim 保留，滑鼠與手柄共用動作鎖。

## 相容範圍與驗證

**已測遊戲 build：`24826606`。** 模組會核對遊戲模組雜湊與原生函式指紋，其他 build 需重新驗證。

使用者已回報滑鼠、Xbox 及自動版本正常。最新一輪記錄 **31 次投擲、52 次引爆**，全部觀察到原生動作完成，沒有 action fault 或功能停用事件。

PS profile 已有離線測試，**尚無 PS 硬體實測**。相容性取決於遊戲暴露的手柄介面，不代表所有型號、USB／藍牙組合都已測過。多人、完整移動／受擊中斷與所有選單尚未全面驗收；沒有游標的 UI 仍需個別確認。詳見 [驗證紀錄](docs/VALIDATION.md)。

## 開源內容

完整 Lua 程式、組裝與打包腳本、測試、原生版型核對資料、歷史研究筆記及去識別化日誌均收錄於本專案，採 [MIT 授權](LICENSE)。第三方依賴另列於 [THIRD_PARTY.md](THIRD_PARTY.md)。

```bash
python -B scripts/check_automatic.py
python -B scripts/build.py --loader /path/to/BingusSharedLoader
```

需要 Python 3.10+ 與 LuaJIT；詳見 [建置方法](docs/BUILDING.md)、[架構說明](docs/ARCHITECTURE.md)、[研究索引](research/README.md)。

公開安裝包沿用已測成功的 EXP06 Lua 內容。內部 `EXP06`、`C4DualInput` 與 `c4_boundary_probe` 名稱保留以延續升級與日誌比對，Mod Manager 顯示名稱為 **HD2 C4 Quick Actions**。

研究、程式、測試與文件有 AI 協助；文件會區分 mock 檢查、實機記錄與使用者回報。
