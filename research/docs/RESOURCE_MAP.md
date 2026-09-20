> Historical research note. Status statements describe that experiment; see [current validation](../../docs/VALIDATION.md). Local-only artifacts are not bundled.

# C4 資源關係與未確認邊界

實線：目前檔案中按格式解出的關係或 archive 成員。虛線：舊版配置或待追蹤的執行路徑。

```mermaid
flowchart TD
    Mouse[Lua Mouse pressed / released<br/>歷史實機 API 存在] -.本探針實機待測.-> Input[Fire / Aim 遊戲 Action<br/>未定位]
    Input -.未追蹤.-> Dispatch[Deploy / Detonate dispatcher<br/>未定位]
    Config[舊 WeaponData 配置<br/>Single + WeaponFunctionType_Detonate] -.消費者待追蹤.-> Dispatch
    Dispatch -.原生動作鏈未證實.-> Throwable[C4 Throwable 舊配置<br/>arm_grenade / throw_far / throw_short]
    Dispatch -.引爆與網路流程未證實.-> Trigger[Detonation trigger<br/>未定位]
    Bundle[本機 archive bba76437a1c00c1e] --> Unit[引爆器 unit<br/>51f50d6321f52f3d]
    Bundle --> Charge[C4 本體 unit<br/>9b75217d8312dd67]
    Bundle --> Backpack[背包 unit<br/>2a18f81c44a26771]
    Unit -->|StateMachineRef +0x20| SM[動畫 state_machine<br/>51f50d6321f52f3d]
    SM --> Idle[idle clip<br/>3666461975a443c3]
    SM --> Hellpod[idle_hellpod clip<br/>4d2c37b7a3eab047]
    Throwable -.同 entity hash，舊資料.-> Charge
```

| 類別 | resource ID（hex） | 名稱／用途 | 狀態 |
| --- | --- | --- | --- |
| 背包 | `2a18f81c44a26771` | `.../c4_charge_backpack` | 現版 unit／bones／physics 已找到 |
| 引爆器 | `51f50d6321f52f3d` | `.../c4_charge_detonator` | 現版 unit／bones／physics／state_machine 已找到 |
| C4 本體 | `9b75217d8312dd67` | `.../c4_charge` | 現版 unit／bones／physics 已找到；完整 spawn 路徑未證實 |
| Deploy UI | `38adabc6a32af014` | `content/ui/mission/hud/weapon_function/firemode_deploy_c4` | material／texture，**不是 Action** |
| Detonate UI | `55374383474193f8` | `content/ui/mission/hud/weapon_function/firemode_detonate_c4` | material／texture，**不是 Action** |
| Deploy Action ID | 未知 | 無可驗證的呼叫入口 | 待研究 |
| Detonate Action ID | 未知 | `11 / WeaponFunctionType_Detonate` 不能替代它 | 待研究 |
| Gameplay state machine | 未知 | 不等於已找到的動畫 state machine | 待研究 |

完整路徑、來源 archive、byte offset 與 SHA256 見 local-resources.json (`../evidence/local-resources.json`; local research artifact) 和 state-machine.json (`../evidence/state-machine.json`; local research artifact)。所有 64-bit 資源 ID 用字串保存，避免 JSON／JavaScript 精度遺失。
