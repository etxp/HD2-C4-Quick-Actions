# Helldivers 2 C4 雙鍵操作可行性研究 PRD v0.1

## 1. 專案名稱

**C4 Dual-Input Research Prototype**

研究目標：

> 調查是否能將 B/MD C4 Pack 改造成：
>
> **右鍵 = 投擲 / Deploy C4**  
> **左鍵 = 引爆 / Detonate C4**
>
> 並且不需要玩家手動切換 Deploy / Detonate firing mode。

本階段只做**技術研究與原型驗證**，不要求製作可公開發布的正式 Mod。

---

## 2. 背景

B/MD C4 Pack 原生具有兩個 firing modes：

- Deploy
- Detonate

Deploy 負責投擲 C4。

Detonate 負責觸發目前已部署的 C4。

目前遊戲要求玩家：

```text
切換 firing mode
↓
按 Fire
↓
Deploy / Detonate
```

本研究希望改造成：

```text
RMB
↓
Deploy

LMB
↓
Detonate
```

也就是：

```text
          C4 Equipped
              │
       ┌──────┴──────┐
       │             │
      RMB           LMB
       │             │
    Deploy        Detonate
       │             │
    Throw C4       BOOM
```

核心目標不是修改 C4 爆炸、傷害、彈藥或同步機制，而是研究**能否直接控制原版的兩個 C4 行為**。

---

## 3. 為什麼需要先研究

最簡單的模擬方式可能是：

```text
RMB
↓
切到 Deploy
↓
Fire
```

以及：

```text
LMB
↓
切到 Detonate
↓
Fire
```

但這種方案可能存在 Race Condition。

例如玩家高速輸入：

```text
Frame 100
RMB → Request Deploy

Frame 101
LMB → Request Detonate

Frame 102
Fire Event
```

如果 firing mode 已經在 Frame 101 被改成 Detonate：

```text
原本：
RMB → Throw C4

實際：
RMB → Detonate
```

因此不能假設：

```text
set_mode()
fire()
```

是原子操作。

此外，C4 的 Detonate 若被重複觸發，可能造成引爆流程重置或其他時序問題，因此長按、連點或錯誤的每幀觸發都必須列入壓力測試。

---

## 4. 研究最終問題

### Q1 — Deploy 與 Detonate 是否存在獨立 Action？

需要確認：

```text
C4
 ├─ Deploy action
 └─ Detonate action
```

是否真的能在不改變 firing mode 的情況下被分別呼叫。

這是最高優先級研究項目。

理想結果：

```text
execute_action(C4_DEPLOY)
```

以及：

```text
execute_action(C4_DETONATE)
```

可以獨立執行。

### Q2 — Fire Mode 是「Action 選擇器」還是「Action 本體」？

需要確認遊戲架構究竟是：

方案 A：

```text
Fire input
↓
Current Fire Mode
↓
Mode 對應 Action
```

還是：

方案 B：

```text
Deploy Mode
↓
修改 weapon state
↓
Fire

Detonate Mode
↓
修改另一組 weapon state
↓
Fire
```

如果是 A，直接呼叫 Action 的可能性較高。

如果是 B，可能需要控制 weapon state。

### Q3 — 能否取得 RMB / LMB 的獨立輸入事件？

調查現有 runtime Lua / loader 是否能取得：

```text
Mouse Left Pressed
Mouse Right Pressed
Mouse Left Released
Mouse Right Released
```

或者更高階的遊戲 action：

```text
Fire
Aim
Weapon Function
```

優先順序：

```text
遊戲 Action Event
>
Lua Input API
>
既有 Aim / Fire 狀態
>
外部 Input Hook
```

不要一開始就使用 OS 層滑鼠攔截。

---

## 5. 首選技術方案

### Route A — Direct Action

最高優先級。

目標架構：

```text
C4 Equipped
│
├─ RMB Press
│    ↓
│  Deploy()
│
└─ LMB Press
     ↓
   Detonate()
```

要求：

```text
不修改 current firing mode
不模擬 mode switch
不模擬額外 Fire input
```

應盡量讓原版遊戲自己處理：

```text
動畫
C4 數量
投擲
Projectile
Sticky behavior
Detonation
Damage
Networking
Cooldown
```

Mod 僅負責：

```text
Input → Action
```

#### Route A 成功條件

以下操作連續執行：

```text
RMB
LMB
RMB
LMB
RMB
LMB
```

不能出現：

```text
錯誤投擲
錯誤引爆
卡 firing mode
動畫卡死
無法再次使用
C4 數量錯亂
```

---

## 6. 第二方案

### Route B — Existing Fire + Secondary Action

若不能直接呼叫 Deploy / Detonate，研究是否可以利用原版：

```text
Fire
Aim
Weapon Function
```

例如：

```text
RMB 原本 = Aim
```

將 Aim action 改成：

```text
RMB
↓
Deploy
```

而：

```text
LMB
↓
Fire
↓
Detonate
```

此方案仍比自動切 firing mode 更好。

研究：

```text
Aim 是否是獨立 action
Aim 是否能被替換
替換後是否影響投擲方向
是否與動畫系統耦合
是否影響其他武器
```

修改必須只在：

```text
Current Weapon == B/MD C4
```

時生效。

---

## 7. 最後備用方案

### Route C — Automatic Fire Mode Switching

只有 Route A / B 均不可行才使用。

架構：

```text
RMB
↓
Request Deploy Mode
↓
等待 Mode Confirmed
↓
Fire
```

以及：

```text
LMB
↓
Request Detonate Mode
↓
等待 Mode Confirmed
↓
Fire
```

禁止：

```text
set_mode()
fire()
```

直接連續執行。

---

## 8. Route C 必須使用狀態機

建議：

```text
IDLE
 │
 ├── RMB
 │    ↓
 │ SWITCH_TO_DEPLOY
 │    ↓
 │ WAIT_CONFIRM
 │    ↓
 │ DEPLOY
 │    ↓
 │ ACTION_LOCK
 │    ↓
 │ IDLE
 │
 └── LMB
      ↓
   SWITCH_TO_DETONATE
      ↓
   WAIT_CONFIRM
      ↓
   DETONATE
      ↓
   ACTION_LOCK
      ↓
     IDLE
```

禁止兩個 action 同時修改 weapon state。

---

## 9. Input Buffer

如果：

```text
正在 Deploy
```

玩家此時按：

```text
LMB
```

不要直接執行。

記錄：

```text
pending_action = DETONATE
```

Deploy 完成後再處理。

最多保存：

```text
1 個 pending action
```

例如：

```text
LMB
LMB
LMB
LMB
LMB
```

不能產生：

```text
Detonate ×5
```

應該只產生：

```text
pending_action = DETONATE
```

---

## 10. Edge Detection

必須區分：

```text
Pressed
Held
Released
```

正常操作只應在：

```text
Pressed
```

觸發。

禁止：

```text
if LMB_down then
    detonate()
end
```

應該是類似：

```text
if LMB_pressed_this_frame then
    request_detonate()
end
```

---

## 11. 第一階段：資源研究

首先定位 C4 的：

```text
Weapon Resource
Firing Mode Resource
Action Resource
Projectile Resource
Detonator Resource
Animation Resource
Input Mapping
State Machine
```

需要建立資源關係：

```text
B/MD C4
│
├─ Weapon
│
├─ Deploy Mode
│   ├─ Action
│   ├─ Animation
│   └─ Projectile
│
└─ Detonate Mode
    ├─ Action
    ├─ Animation
    └─ Trigger
```

特別找：

```text
Deploy Action ID
Detonate Action ID
```

以及兩者是否共用：

```text
Fire Action
```

---

## 12. 第二階段：Runtime Research

調查 Lua runtime 能否讀取：

```text
Current Player
Current Weapon
Current Weapon Type
Current Fire Mode
Fire Input
Aim Input
Weapon Function Input
Animation State
Ammo / Charge Count
```

然後調查是否能寫入或呼叫：

```text
Weapon Action
Fire Action
Fire Mode
Input State
```

但：

```text
runtime data access
```

不等於：

```text
input/action API
```

必須分開驗證。

---

## 13. 第三階段：最小原型

先不要做雙鍵。

Prototype A：

```text
按某個測試鍵
↓
Deploy()
```

如果成功：

Prototype B：

```text
另一個測試鍵
↓
Detonate()
```

如果兩個均成功：

Prototype C：

```text
RMB → Deploy
LMB → Detonate
```

這樣可以快速分離：

```text
Action 問題
```

與：

```text
Input 問題
```

不要同時研究兩者。

---

## 14. Logging

研究版必須加入 log。

至少記錄：

```text
Timestamp
Frame / Tick
Current Weapon
Current Fire Mode
Input
Requested Action
Executed Action
Pending Action
Action Lock
Action Result
```

例如：

```text
[15230] RMB PRESSED
[15230] Weapon=C4
[15230] Request=DEPLOY
[15231] Execute=DEPLOY
[15231] Result=SUCCESS

[15232] LMB PRESSED
[15232] Request=DETONATE
[15232] Pending=DETONATE

[15245] Deploy Finished
[15246] Execute=DETONATE
```

這對高速操作 Bug 非常重要。

---

## 15. 高速輸入測試

必須專門建立 Stress Test。

### Test 1

```text
RMB
RMB
RMB
RMB
```

確認正常連續 Deploy。

### Test 2

```text
LMB
LMB
LMB
```

確認不會因 Mod 額外觸發造成 detonation timer 或 action state 異常。

### Test 3

高速：

```text
RMB → LMB
```

### Test 4

高速：

```text
LMB → RMB
```

### Test 5

極高速：

```text
RMB
LMB
RMB
LMB
RMB
LMB
```

### Test 6

同 Frame / 接近同時：

```text
RMB + LMB
```

必須定義優先級。

建議研究：

```text
已部署 C4 存在：
Detonate 優先

沒有已部署 C4：
Deploy 優先
```

但研究階段先觀察原版行為，不要過早固定規則。

---

## 16. Hold 測試

測試：

```text
Hold RMB
```

與：

```text
Hold LMB
```

確認：

```text
一個 press
=
一個 action
```

除非原版 C4 本身具有 hold/repeat 行為。

---

## 17. Weapon Switching 測試

測試：

```text
RMB
↓
立刻換武器
```

以及：

```text
LMB
↓
立刻換武器
```

不能造成：

```text
其他武器被強制切 firing mode
其他武器 firing action 被覆蓋
回到 C4 後狀態錯亂
```

所有 Hook 都必須有：

```text
if current_weapon ~= C4 then
    return
end
```

或等價限制。

---

## 18. Reload / Ammo / Empty 狀態

測試：

```text
C4 = 0
RMB
```

應沿用原版 Empty 行為。

不要：

```text
生成免費 C4
```

也不要繞過：

```text
ammo
backpack
reload
weapon state
```

---

## 19. Animation State

觀察：

```text
Deploy animation
Detonator animation
Weapon switch animation
Sprint
Dive
Prone
Vault
Stagger
Ragdoll
```

尤其測試：

```text
Throw animation 未完成
↓
Detonate
```

看原版是否允許。

Mod 不應強制取消 animation，除非研究證明必要。

---

## 20. Multiplayer Research

如果直接呼叫的是原版：

```text
Deploy Action
Detonate Action
```

應盡量讓遊戲原生 network path 處理。

但仍必須實測：

```text
Solo
Host
Client
High Ping Client
```

觀察：

```text
C4 是否正常同步
其他玩家是否看到投擲
爆炸是否同步
C4 是否重複生成
Host / Client 是否產生不同結果
```

目標是：

```text
Mod 只改本地 Input Routing
```

而不是：

```text
Mod 自己生成 Explosion / Projectile
```

---

## 21. 禁止範圍

本研究階段不要修改：

```text
C4 Damage
Explosion Radius
Armor Penetration
Projectile Physics
Sticky Physics
Ammo Capacity
Backpack Capacity
Explosion Network Logic
Detonation Range
```

也不要：

```text
自己 Spawn Explosion
自己 Spawn C4
自己同步 C4
```

除非研究證明原版 Action 無法重用。

---

## 22. 技術優先級

按照以下順序研究：

```text
1.
Direct Deploy / Detonate Action

↓

2.
Existing Fire / Aim Action Remapping

↓

3.
Lua Input Routing

↓

4.
Fire Mode State Machine

↓

5.
Native / External Input Hook
```

不要反過來。

---

## 23. Go / No-Go Decision

### GO-A

如果確認：

```text
Deploy()
Detonate()
```

可以獨立呼叫：

→ 直接進入正式 Mod 設計。

這是最佳結果。

### GO-B

如果無法獨立呼叫，但：

```text
RMB → Deploy
LMB → Detonate
```

可以透過既有 Aim / Fire Action mapping 完成：

→ 可以繼續。

### GO-C

如果只能：

```text
Switch Mode
→ Fire
```

→ 可以製作，但必須加入完整狀態機、Action Lock、Input Buffer。

正式製作前必須先完成高速輸入壓力測試。

### NO-GO

如果唯一可行方式是：

```text
OS Mouse Injection
+
模擬 Weapon Function Key
+
模擬 Fire
```

則暫停正式開發。

原因：

```text
輸入時序不穩定
幀率相關
延遲相關
Keybind 相依
Race Condition 高
玩家自訂按鍵容易破壞
```

---

## 24. 研究完成條件

研究階段完成時必須交付：

### A. C4 架構圖

```text
Input
↓
Fire Mode
↓
Action
↓
Projectile / Detonator
```

實際資源關係。

### B. Action 調查結果

明確回答：

```text
Deploy 能否獨立呼叫？
YES / NO

Detonate 能否獨立呼叫？
YES / NO
```

### C. Input 調查結果

明確回答：

```text
Lua 是否可取得 LMB？
Lua 是否可取得 RMB？
是否可取得 Fire？
是否可取得 Aim？
```

### D. Prototype

至少完成：

```text
Test Key → Deploy
```

以及：

```text
Test Key → Detonate
```

### E. Stress Test

完成：

```text
RMB/LMB 高速交替
```

測試。

### F. 建議架構

最後只能選：

```text
Route A
Route B
Route C
NO-GO
```

之一。

---

## 25. 最重要的研究原則

不要先研究：

> 「怎麼快速幫玩家切 Deploy / Detonate？」

應該先研究：

> **「Deploy 與 Detonate 到底能不能直接被獨立執行？」**

因為如果答案是 YES：

```text
RMB → Deploy()
LMB → Detonate()
```

整個高速輸入 Race Condition 問題會大幅降低。

而如果一開始就採用：

```text
切 Mode
→ Fire
```

後面會花大量時間處理：

```text
Timing
Race Condition
Input Buffer
Mode Desync
Animation Conflict
```

因此本專案第一階段的真正目標不是製作 C4 Mod，而是**找出 C4 的 Action 邊界與 Input 邊界**。
