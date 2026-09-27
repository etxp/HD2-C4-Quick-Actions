# HD2 C4 Quick Actions 1.1

[English](README.md)

在 Helldivers 2 中，用獨立按鍵投擲與引爆 C4。透過 Mod Bindings Menu 設定按鍵與觸發方式，支援鍵盤、滑鼠、Xbox 與 PlayStation 手柄，不需要按 F6 啟用。

## 1.1 更新內容

- **手動／接觸引爆**：在原本的 C4 武器設定選單切換。接觸模式碰撞後自動引爆，飛行途中仍可手動引爆。
- **自訂操作**：投擲與引爆分別設定，支援放開投擲，不再區分 Standard／Reversed 安裝包。
- **趴下與飛撲**：趴下、飛撲及離地過渡時可以投擲和引爆。
- **載具乘客**：支援 FRV 與坦克乘客座位，自動探身並維持到完整投擲動作結束。
- **自動裝填**：投擲後及打空補給後自動裝填；其他操作可中斷，並處理車內裝填被打斷後的下車恢復。
- **流暢操作**：抑制綁定鍵重疊的原生瞄準／開火輸入，避免打斷奔跑。放開投擲時，按住期間保留瞄準。
- **避免誤觸**：介面、地圖、武器設定與布娃娃狀態不接受新的投擲／引爆；切換模式不會消耗手中的 C4。

載具功能適用於乘客座位，不包含駕駛位。已投出的接觸 C4 保留原模式，在切槍或開啟地圖後仍會依碰撞引爆。

## 需求與安裝

- Bingus Shared Loader **v17+／API 1**。
- 官方 Mod Bindings Menu **v2+／API 1**。
- **HD2 Mod Manager 1.3** 或 **HD2 Arsenal**，共用同一個 V1 manifest ZIP。

停用舊版 C4 Quick Actions，匯入 `HD2-C4-Quick-Actions-1.1.zip`，選擇 **Installation → C4 Quick Actions — MBM controls** 後部署。在 MODS 按鍵頁設定 **Throw C4** 與 **Detonate C4**。詳見[安裝說明](docs/INSTALL.txt)。

此次倉庫更新只提供 1.1 原始碼與文件，沒有建立 GitHub Release 或加入 1.1 安裝 ZIP。原有 `dist/HD2-C4-Quick-Actions-v0.6.0.zip` 是歷史檔案，不是目前版本。開發者可依[建置說明](docs/BUILDING.md)自行產生 1.1。

## 開發與文件

- [建置及離線測試](docs/BUILDING.md)
- [程式架構](docs/ARCHITECTURE.md)與[驗證範圍](docs/VALIDATION.md)
- [完整中文介紹](docs/release-1.1/MOD-DESCRIPTION.zh-TW.md)／[English description](docs/release-1.1/MOD-DESCRIPTION.en.md)
- [更新紀錄](CHANGELOG.md)與[貢獻指南](CONTRIBUTING.md)
- [舊版公開原始碼與研究資料](legacy/0.6.0/README-HISTORY.md)

本模組不以遊戲版本號或整個檔案雜湊鎖定版本，而是核對實際使用的內部函式與資料結構。若遊戲更新改動相關結構，仍可能需要更新模組。離線測試不代表已完成遊戲實測。

本專案自行撰寫的程式碼與文件採 [MIT 授權](LICENSE)。第三方依賴與遊戲素材保留原權利，詳見[第三方說明](THIRD_PARTY.md)。
