Historical instructions for the named experiment; see ../../README.md for the current release.

C4 Boundary Probe EXP01 / 0.1.0

這是唯讀研究探針，不是 C4 雙鍵操作 Mod。
它不投擲、不引爆、不改 firing mode、不注入滑鼠或 Fire 輸入。

需要獨立安裝 Bingus Shared Loader v15 或更新版（API 1）。
此包只含一個自行命名的 Lua resource，不含 Loader、Wwise 或 boot 替換。
離線封裝與假引擎測試已做；本探針尚未通過遊戲內驗收。

準備做實機研究時，關閉遊戲後用既有 Mod 管理器匯入探針及 Loader。
使用單一 Loader；依 Loader 的官方說明設定優先序。
進入可自行操作的測試場景後，F6 開始／停止滑鼠紀錄，F7 加入人工時間標記。
F6／F7 只控制日誌，不控制 C4。若其他 Mod 共用這兩鍵，先避開衝突。
滑鼠的所有原版效果仍照常運作。探針不知道當前武器或選單模式，日誌會寫 UNKNOWN。

日誌：%LOCALAPPDATA%/CowboyBingus/Helldivers2/Logs/C4Boundary_<UTC>_<序號>.log
每個 session 使用新檔；每 60 個 update callback flush。
上限 10,000 筆或約 4 MiB；達上限會停止探針，原遊戲 callback 繼續執行。
時間為 UTC 秒級時間戳與 update dt 累計；tick 是 Lua callback 計數，不保證等於渲染幀號。

先做原版基準：記錄目前 Deploy／Detonate 模式，測單鍵、長按、交替、同時按下。
把觀察到的投擲／引爆與彈量另記下來。日誌的 input 不是已執行 Action 的證明。
之後若需要停用，透過同一管理器停用並重新部署。
