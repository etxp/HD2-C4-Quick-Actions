Historical instructions for the named experiment; see ../../README.md for the current release.

C4 Dual Input EXP06 / v0.6.0 / build 24826606

拿著本機 C4 時自動啟用，不再需要 F6。
滑鼠：右鍵投擲、左鍵引爆。
Xbox：LT 投擲、RT 引爆。PlayStation：L2 投擲、R2 引爆。
R 仍交給遊戲原本的裝填流程；放開 R、補彈完成後，可直接繼續操作。
F7 保留為日誌標記。F6 不再控制本模組。

安裝
退出遊戲，由 Mod Manager 匯入 C4-Dual-Input-EXP06-Auto.zip 取代 EXP05。
只啟用一個 C4 版本；保留原有 Bingus Shared Loader v15+ / API 1。
不要直接覆蓋 Manager 合併中的 patch_0。

這輪最短測試
1. 拿出 C4，先放開左右鍵與兩個扳機，不按 F6，直接右鍵投擲、左鍵引爆。
2. 丟空 C4 → 拿補給 → 按 R 裝填 → 放開 R，等補彈完成 → 再右鍵投擲、左鍵引爆。
3. 開關一次選單，再切出／切回遊戲；放開左右鍵與扳機後，確認可直接繼續。
4. Xbox 再試一次 LT / RT，並確認切回主武器仍正常開火、瞄準。
若失效，按 F7 一次並描述當時操作，無須再按 F6。

自動恢復規則
失焦、顯示遊戲游標、按住 R／Esc／Enter／Tab／M 或手柄選單鍵時暫停本模組動作。
回到可操作狀態，滑鼠左右鍵與兩個扳機都放開後才重新接受新的按下。
暫停時取消尚未執行的 pending，避免關選單後突然投擲或引爆。
切換武器會恢復該把 C4 的原版 Fire；再次拿出 C4 後自動接管。
真實 I/O、原遊戲 callback 或記憶體核對錯誤仍會停用本次 session 並嘗試還原。
若遊戲不提供可讀取的 Window focus / cursor 狀態，會保留原版操作並記錄原因。

驗證範圍
EXP05 的 Xbox 操作已由使用者確認成功；這次修正 R 會被誤當永久停用的原因。
EXP06 自動啟用、補彈恢復與選單／失焦狀態目前已通過 mock 檢查，仍待本輪遊戲實測。
Window 訊號是否涵蓋所有選單尚未確認，尤其是未顯示游標的手柄 UI；請勿把本輪當成完整 UI 驗收。
PS profile 有離線檢查，尚無 PS 硬體實測。仍只支援遊戲能辨識的標準 Xbox／PS profile。
扳機 55% 觸發、25% 釋放，建立啟用基線時需回到 10% 以下。
長按不連發，同時按投擲與引爆時引爆優先；補彈等待、原生 Aim 與地面狀態限制沿用已測版本。
不新增補彈預觸發；多人、翻滾等完整矩陣尚未驗收。

日誌
%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/C4DualInput_<session>_part1.log ～ _part4.log
session version 應為 0.6.0-exp06；每段最多 4 MiB，保留最近四段。
gameplay_guard 記錄暫停與恢復及 Window 狀態；guard_input 保留確切按鍵／原始值。
capture_enabled 表示模組自動模式仍運作；fire_gate_active 表示當下是否接管本機 C4。
收集：python -B scripts/collect_actions.py --phase exp06
