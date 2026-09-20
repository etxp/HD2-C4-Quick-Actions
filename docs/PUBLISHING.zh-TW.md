# 上傳 GitHub

建議 repository 名稱：`hd2-c4-quick-actions`。

英文 description：`Independent C4 deployment and detonation controls for mouse and controller in Helldivers 2.`

1. 建立 repository，將本資料夾內的檔案放在 repository 根目錄。`README.md`、`LICENSE`、`src/` 等應直接位於根目錄。
2. 若使用 GitHub 網頁上傳，先解開整份資料 ZIP 再上傳內容；整份資料 ZIP 不是遊戲安裝包。保留 `.gitignore` 與 `.gitattributes`。
3. 建立 tag／Release `v0.6.0`，附上 `dist/HD2-C4-Quick-Actions-v0.6.0.zip` 與 `dist/SHA256SUMS.txt`。
4. Release 內容可使用下方文字。程式、文件採 MIT，Loader 為另外安裝的依賴。

## Release 文字

HD2 C4 Quick Actions v0.6.0

- Independent C4 deploy and detonate controls: mouse RMB/LMB, Xbox LT/RT, PlayStation L2/R2.
- Automatic activation while C4 is equipped; no F6 required.
- Reload no longer permanently disables the mapping.
- Tested on Helldivers 2 build 24826606. Mouse/Xbox basic gameplay confirmed; PlayStation hardware and the full multiplayer/UI matrix remain unverified.
- Requires Bingus Shared Loader v15+ / API 1, installed separately.

Download the mod ZIP attached to this release, import it into your mod manager, enable it alongside the loader and deploy. Replace earlier C4 experiment packages.

完整驗證範圍與研究資料已放在 repository。原始碼上傳與 Release 發布是分開的步驟；建立 Release 時請附上 dist/ 內的模組 ZIP 與校驗檔。
