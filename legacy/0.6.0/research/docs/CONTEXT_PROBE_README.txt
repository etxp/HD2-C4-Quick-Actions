Historical instructions for the named experiment; see ../../README.md for the current release.

C4 Context Probe EXP02 — 唯讀研究版

用途：確認本機玩家、目前選取武器、C4 武器功能值與原生 ability 配置。
本版仍然使用遊戲原有的按鍵和 Deploy/Detonate 切換方式。
尚未提供右鍵投擲、左鍵引爆，也不會呼叫原生遊戲函式或寫入遊戲記憶體。

支援 Steam build 24826606；启动時核對 game.dll SHA256 與六處原生程式碼。
需要 Bingus Shared Loader v15 / API 1，沿用已安裝的 Loader。

安裝：退出遊戲後，用 Mod Manager 匯入本 ZIP，取代舊 C4 Boundary Probe EXP01。
兩版使用相同 addon resource 與 GUID，不要同時部署兩份。保留 Shared Loader，重新部署後啟動。

建議在單人低難度任務做以下原版操作：
1. 帶 C4 背包進任務，拿到 C4，先切主武器，按 F6 開始錄製。
2. 主武器停 2 秒，按 F7，接著切到 C4，停 2 秒。
3. 用原版武器功能選單選 Deploy，關閉選單，按 F7，停 2 秒，再投擲 1 顆。
4. 投擲動畫結束後，用原版選單選 Detonate，關閉選單，按 F7，停 2 秒，再引爆。
5. 用原版選單切回 Deploy，關閉選單，按 F7，停 2 秒。
6. 切主武器，按 F7，停 2 秒；再切回 C4，按 F7，停 2 秒；按 F6 結束。

F7 的六個標記依序代表：主武器、Deploy、Detonate、Deploy、主武器、C4 返回。
標記是測試者註記；日誌不會把註記自動當作原生模式驗證。
若流程做錯，按 F6 結束後重新開始即可，分析時依 capture 段落區分。

日誌：%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/C4Context_*.log
紀錄上限 4 MiB / 10000 筆；資料採樣最多 20 Hz，F7 可強制取樣。
若版本不符，探針停用；讀取中裝備變動、身份不符或資料失效時捨棄該次結果。
資料值尚待實機對照，不是完成品或已驗證的 Action API。

恢復：退出遊戲，在 Mod Manager 移除本版或還原 EXP01，重新部署。
