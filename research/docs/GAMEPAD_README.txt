Historical instructions for the named experiment; see ../../README.md for the current release.

C4 Dual Input EXP05 / v0.5.0 / build 24826606

操作對照（目前拿著本機 C4 引爆器時）
Xbox：LT 投擲、RT 引爆。
PlayStation：L2 投擲、R2 引爆。
滑鼠：右鍵投擲、左鍵引爆。
F6 啟用／停用，F7 標記。預設仍為關閉。

安裝與這次實測
1. 退出遊戲，用 Mod Manager 匯入 C4-Dual-Input-EXP05-Gamepad.zip，取代 EXP04。
   只启用一个 C4 版本；保留原有 Bingus Shared Loader，勿覆蓋 Manager 合併中的 patch_0。
2. 先接好手柄，確認原版遊戲能使用它。拿出 C4，放開滑鼠左右鍵及兩個扳機，按 F6。
3. Xbox 按 LT 投一顆，動作結束後按 RT 引爆。PS 對應 L2 / R2。
4. 丟完最後一顆後仍可用 RT / R2 引爆；這次特別確認會不會再自行停用。
   若再次發生，當下按 F7 標記即可，不必反覆重新啟用收集大量資料。
5. 切回主武器，確認原本射擊與瞄準正常。

相容範圍
使用遊戲自己的 Pad1～Pad4 / PS4Pad1～PS4Pad4，依實際按鍵名稱辨識 Xbox 或 PS profile。
Xbox 或 Steam Input 提供的標準手柄介面使用 left_trigger / right_trigger；PS profile 使用 l2 / r2。
USB／藍牙交由遊戲與 Steam 處理。此版不安裝驅動、不調整 Steam Input、不模擬滑鼠。
PS 手柄若已由 Steam Input 轉成 Xbox 介面，仍是實體 L2 投擲、R2 引爆。
只有遊戲已識別的裝置才能讀取；未知按鍵 profile 會記錄 available_buttons，並保留原版操作。
目前沒有 Xbox／PS 實機回報，不能宣稱所有型號、連線方式都已驗證。若原生 PS 熱插拔未被遊戲偵測，先接好再啟動遊戲。
多把手柄同時連線時選擇第一個 active 裝置並維持選擇；優先一般 Pad 介面，避免 Steam Input／原生 PS 雙重觸發。

扳機與動作
扳機達 55% 行程視為一次按下，回到 25% 以下才重新接受下一次；啟用／還原時需放到 10% 以下。
長按不連發；LT / RT（L2 / R2）同時按時引爆優先。
滑鼠與手柄共用動作鎖及一格 pending；補彈等待維持先前決定，不新增預觸發功能。
斷線重連、換手柄或換回 C4 後，先放開滑鼠與扳機，再按新的一次。
換成其他武器即恢復原版 Fire。原版 Aim、姿態／視角行為保留。
仍保留原型的地面／本機角色限制；多人、翻滾等完整矩陣尚未驗收。

關於「丟空後自行關閉」
EXP04 沒有空彈自動停用設定；最新五組的停用原因均記為 menu_or_mode_key。
使用者已明確回報沒有按 R 或開選單，所以不能據此推論是使用者操作。
旧版沒有保存確切按鍵／原始值，目前來源仍未查明。
EXP05 記下鍵名、ID、原始 value / pressed / released。保留 down 狀態只暫停輸入；新的選單 pressed 邊緣才停用 F6。
Esc／Enter／Tab／R／M、手柄 Start／Back／Options／Share 的新按鍵邊緣，以及失焦，仍會停用；回來後按 F6。
另一個已確認問題是第一份長測日誌達 4 MiB，EXP04 因此停用。此版改用循環日誌，不再因容量滿而關閉功能。
這些是程式修正與診斷加強，空彈異常是否完全消失仍須這一版的實機資料。

日誌
%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/C4DualInput_<session>_part1.log ～ _part4.log
session version 應為 0.5.0-exp05。每個檔案最多 4 MiB，每次遊戲 session 保留最近四段；較早資料循環覆寫。
gamepad 記錄裝置／按鍵辨識；guard_input 記錄防護來源；capture 記錄具體停用原因；capture_enabled 表示 F6 狀態。
python -B scripts/collect_actions.py --phase exp05 會按 segment 序號合併保留段並保存原始檔案。
真實 I/O 或 memory 錯誤仍會停止新動作，並嘗試還原本把 C4 的 Fire gate。
