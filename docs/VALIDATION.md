# 1.13.1 validation

1.13.1 changes only how the addon talks to its two dependencies and to
Windows; gameplay code is that of release 1.13.

**Accepted in the game on 2026-10-05.** The owner reported all functions
working. The deployed files were checked byte for byte: this package, Mod
Bindings Menu v2.2 and Bingus Shared Loader v19 from their GitHub releases.
The loader log shows `loader-v19`, both mods loaded and "Startup finished: 2
loaded, 0 failed"; the menu log shows both bindings registered on their
previous native actions (10:0, 10:2) with no refused registration, and the
assignments file converted to format 2 with its backup. Released 1.13 ran in
the game with Loader v18 and the menu v2.1.

## What the new dependencies changed

Both releases were downloaded from their GitHub releases and checked against
their published SHA256SUMS; their sources were compared with the previous
releases.

- **Bingus Shared Loader v19.** `version` stays 17 and `api` 1, so the addon's
  check (`api == 1`, `version >= 16`, `open_log`) is unchanged. The loader now
  calls Windows under private names and keeps only six plain declarations for
  mods written for v18. New `revision`, `capabilities` and `after_startup`
  fields; this addon uses none of them. Its packaging helper changed two loader
  build constants and added a read function; for this addon's three payloads it
  produces archives byte-identical to the pinned helper's.
- **Mod Bindings Menu v2.2.** `api` 1, `version` 3, the same
  `register_binding`, `is_down` and `ready`. New: `poll` (several bindings in
  one call), `revision`, refusals that last the session, and a new format of the
  assignments file this addon reads, saved through a temporary file.

## Offline evidence

- **Gameplay suite** in Off and Verbose on byte-granular and page-granular
  memory, and again in Off and Verbose with a v2.2-style menu table (`poll`,
  `revision`): all cases pass. With `poll`, each update makes one `poll` call
  and no `is_down` call.
- **Differential sessions** (`scripts/differential.py`): 400 of 400 sessions identical to 1.12, 400 to 1.12-opt.2 and 400 to released 1.13 (240,000 updates, every native call, data write and gate state compared after each update). Half of the
  seeds give the addon a v2.2-style menu; builds that do not know `poll` read
  the same answers through `is_down`.
- **Menu contract** (`tests/test_mbm_contract.lua`): identical samples from
  `poll` and `is_down` menus over 20,000 random states; `poll` errors or
  refusals fall back to `is_down`; a refused registration is retried only when
  `revision` changes (once per second without it); a replaced menu table
  registers again. With the v2.2 source present, the release's **real
  `poll.lua`** runs against a simulated input owner: over 5,000 random states
  (sweeps, missing owner, input not ready) it accepts this addon's arguments
  and equals `is_down`, and the bindings layer runs on it.
- **Assignments file:** v2.1 and format 2 (with CRLF) give the same native
  actions; incomplete, duplicate, out-of-range and malformed records are
  rejected; a missing or unusable file keeps the actions last read, and a
  changed action is read within a second.
- **Windows declarations in the game's own LuaJIT** (`scripts/check_wine.py`,
  game `lua51.dll` under Wine, real kernel32/user32 on the test's own memory):
  reads, the Fire-flag, passenger and label exchanges and the focus query work
  with nothing declared first, after the loader's six plain declarations, and
  after another mod declared `ReadProcessMemory`, `WriteProcessMemory`,
  `GetCurrentProcess` and others with conflicting prototypes. Released 1.13
  passes the first two and fails the third (`cannot convert 'uint64_t [1]' to
  'unsigned int *'`).

## Cost

Read counts per update are those of 1.13 in every scenario (C4 idle 92.2, ordinary weapon 40, ship 10). Absolute
timings vary with machine load between runs, so 1.13.1 is compared as a share of 1.12 measured in the same run:

| Scenario | 1.13 share of 1.12, C / Wine | 1.13.1 share of 1.12, C / Wine |
| --- | --- | --- |
| Not in a mission | 24.5% / 27.8% | 24.6% / 28.6% |
| Ordinary weapon | 12.8% / 13.8% | 13.3% / 15.1% |
| C4 idle | 5.8% / 5.6% | 5.9% / 5.0% |
| C4, guards changing every update | 12.1% / 11.3% | 11.3% / 12.1% |
| Tank passenger | 5.4% / 5.8% | 5.5% / 6.1% |

The benchmark menu offers only `is_down`, so these runs measure the Windows
declaration change; `poll` is covered by the contract and gameplay tests.

Retained heap over six 5,000-update states: -12.56 to +14.90 KiB net, no accumulating trend.

## Live check

Run on 2026-10-05 with Bingus Shared Loader v19 and Mod Bindings Menu v2.2:
both bindings on the MODS tab with their keys, throw and detonate, shoulder-aim
suppression and the menu log were checked; the owner reported all functions
working. The cost was not re-measured; the offline read counts and timings
equal 1.13's.

---

# 1.13 validation (unchanged by 1.13.1)

1.13 is development build 1.12-lean.2 with version metadata and documentation
changes only. That build was run in the live game on 2026-10-04: the owner
accepted throw, detonate and automatic reload, and the Watchdog measured its
cost (see [OPTIMIZATION.md](OPTIMIZATION.md)). The live run was not a
systematic pass over every item in the list at the end of this document.
Everything else below is offline: synthetic memory, mocked native functions, no
game process.

## Behaviour offline

**Scripted differential sessions.** `scripts/differential.py` runs the same
random script (presses and holds of both MBM actions, weapon switches, UI, map,
weapon settings, poses, death, focus loss, MBM API loss, ammunition, resupply,
ability progress, avatar actions, remaps, passenger lean states, and changes
made in the middle of the engine update) through this build, 1.12 and
1.12-opt.2, and compares after every update each native call with its
arguments, each data write, the C4 Fire flags, Aim/Fire inhibition state and
call counts, reload calls and eligibility queries, mapping queries, lean calls,
vanilla Fire events and the addon status.

Result: **400 of 400 sessions identical to formal 1.12 and
400 of 400 identical to 1.12-opt.2**, 600 updates each
(240,000 updates), half on byte-granular and half on page-granular
memory, with the shipped 100 ms reload interval active. The sessions contain
8,552 native throw/detonation starts, 19,958 updates with data writes and
1,882 reload calls; one seed in three is a vehicle passenger. The script
does not make the context unusable for a non-ammunition reason, which is the
one case where this build differs from 1.12 (below).

**Gameplay suite.** `scripts/check.py`: 1,635 passing checks. The complete
gameplay suite (342 cases; 338 in Off, where four logging-only cases are
skipped) runs in Off and Verbose on byte-granular and on page-granular memory,
unchanged from 1.12 apart from tests of the new mechanism.

**Checks added in 1.12-lean.2.**

- Quiet gameplay guard: identical decision, status and readiness to the
  descriptive guard over 20,000 random steps covering every veto, window API
  errors and invalid values; the same engine and UI calls in the same order.
- Reload interval: about 20 complete observations in 2 s of idle C4 instead of
  120; a changed chamber, reserve or supply record is observed in the same
  update; an empty spare count keeps per-update observation and resupply
  reloads at once; a throw restores per-update observation; leaving and
  reselecting C4 starts with a complete observation; a throw is refused when
  the chambered charge disappears between complete observations; the Verbose
  build keeps per-update observation.
- **The one difference from 1.12:** when the C4 descriptor stops matching
  (context unusable for a non-ammunition reason), input inhibition is released
  after at most 7 updates (100 ms) instead of on the next update.

The checks added for 1.12-lean.1 (coalesced comparison versus per-guard
comparison, retained snapshot versus new walk over 12,000 random changes,
retention rules, native input state, UI stack image, mode labels) are retained.

## Read work and timing

Synthetic whole-update measurements. Three alternating-order trials per variant
and scenario, each in its own process: 300 warmup updates, 600 counted with a
read meter, 300 unmetered warmup, 600 timed without the meter. Off diagnostics,
identical scenario scripts and reload fixture for all variants. Medians:

| Scenario | Reads per update: 1.12 / lean.1 / 1.13 | Linux C memory, ms: 1.12 / lean.1 / 1.13 | Wine + game Lua, ms: 1.12 / lean.1 / 1.13 |
| --- | --- | --- | --- |
| Not in a mission | 24.0 / 10 / 10 | 0.027 / 0.008 / 0.007 | 0.030 / 0.008 / 0.008 |
| Ordinary weapon | 196.0 / 40 / 40 | 0.168 / 0.023 / 0.021 | 0.193 / 0.027 / 0.027 |
| C4 idle | 1064.8 / 122 / 92 | 0.931 / 0.068 / 0.054 | 1.073 / 0.080 / 0.060 |
| C4, guards changing every update | 1064.8 / 226 / 129 | 0.933 / 0.210 / 0.113 | 1.062 / 0.240 / 0.120 |
| C4 with many bindings | 1064.8 / 126 / 96 | 0.933 / 0.071 / 0.054 | 1.053 / 0.085 / 0.068 |
| Open interface | 8.0 / 6 / 6 | 0.010 / 0.006 / 0.004 | 0.012 / 0.007 / 0.005 |
| Held release-to-throw | 1064.8 / 122 / 92 | 0.929 / 0.069 / 0.051 | 1.053 / 0.082 / 0.063 |
| Tank passenger | 1155.8 / 130 / 100 | 1.016 / 0.072 / 0.055 | 1.183 / 0.082 / 0.068 |

"Wine + game Lua" is a standalone host with the local game Lua DLL (LuaJIT
2.1.0-alpha) and real `ReadProcessMemory` on its own invented pages; it never
attaches to a game. Times include fixture work and are not game FPS. Against
1.12-lean.1, C4 idle falls 24% in reads and 20% / 25% in time; the
states without C4 keep their read counts and lose only bookkeeping time. The
harness mocks the engine window API, Mod Bindings Menu and the focus query, so
it understates the fixed per-update cost that the live profile measured.

## Retained heap

Six synthetic states, 5,000 updates each, collecting every 500 updates and
clearing only fixture history. Post-warmup net change per state: -10.82 to
+13.19 KiB; no accumulating trend. The shared VM, JIT and fixture are included.

## Diagnostic test package

`scripts/build_profile.py` injects timers and counters into the assembled Off
entry without changing `src/`. That package passes the complete Off gameplay
suite on both memory models and writes its reports to
`C4QuickActionsProfile.log`. It is a separate ZIP, not the release package.

## Package and managers

The release ZIP keeps the GUID, V1 manifest, description, root payloads and
fixed Off configuration. It contains no diagnostic choices, performance
counters, private captures, upstream code or game DLLs. `scripts/check_package.py`
validates ZIP and resource hashes, Lua catalog/config loading and version
consistency. The local manager check validates the HD2MM 1.3 V1 schema and the
installed Arsenal converter with deployment, redeployment and removal inside
isolated folders. Hashes are recorded in the ignored `evidence/` folder. No
real game install or remote publication is performed.

## Live coverage

Accepted in the game by the owner on 2026-10-04 (1.12-lean.2 build): throw,
detonate and automatic reload behave normally. Not separately confirmed in that
run, and worth watching for in normal play: Contact and airborne detonation,
FRV and tank passenger throws, reload after dismount, map / weapon settings /
UI vetoes, death and respawn, alt-tab away and back, and firing or aiming
another weapon immediately after switching away from C4.

繁體中文：1.13 即開發版 1.12-lean.2（僅改版本資訊與文件）。該版已於 2026-10-04 在遊戲內
執行，投擲、引爆與自動裝填經使用者驗收，耗時以 Watchdog 量測。離線證據：完整功能測試在
兩種記憶體模型下通過；隨機腳本下每次更新的原生呼叫與資料寫入與 1.12 完全相同；與 1.12
唯一的差異是「非彈藥原因導致狀態不可用」時，輸入抑制最多晚 100 ms 解除。
