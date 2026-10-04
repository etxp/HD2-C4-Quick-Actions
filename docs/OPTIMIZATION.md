# 1.13 — the same checks with fewer reads

1.12 spent its time rebuilding the same picture of the game every update. A
read through `ReadProcessMemory` plus the Lua work around it costs close to a
microsecond in the game (1.289 ms for about 1,265 reads in 1.11, GitHub issue
#1; about 0.7 us per read measured in development build 1.12-lean.1), so the
cost of the addon follows its number of reads and the bookkeeping around them.

1.13 keeps every check of 1.12 and changes how much work it takes to perform
them. It was developed in two steps, 1.12-lean.1 and 1.12-lean.2, which this
document still names; 1.13 is 1.12-lean.2 with version metadata only.

No gameplay rule, input sampling rate, native call, data write or code
verification was removed or moved. One read-only observation is taken less
often under stated conditions (see "Added in 1.12-lean.2"). Both steps were run
in the live game on 2026-10-04 and the owner accepted gameplay on the second.
See [VALIDATION.md](VALIDATION.md) for what the evidence covers.

## The idea

A snapshot is built by walking pointers from the game's globals to the local
avatar, the selected weapon and its components. Every byte the walk reads is
recorded as a guard, and the snapshot is trusted only after all guards have
been read a second time and found unchanged.

That makes a snapshot a pure function of its guarded bytes: the same bytes
always produce the same walk and the same result. So when all guards of an
earlier snapshot still hold the same bytes, a new walk would return exactly
that snapshot, and it can be used again. Comparing the guards is the check
1.12 already performs at the end of every walk; this build performs it at the
start of the next phase instead of walking again.

## What changed

**Guards on one page are compared with one read** (`GuardSpans`). A 4 KiB page
is mapped as a whole, so a span between two guards on the same page is readable
exactly when the guards are. A manager's map header, registry pointer and state
pointer become one read instead of four; in the captured game layout 15 of the
17 resolved globals share one page. Every guarded byte is still compared, and
bytes between guards are ignored. A guard that crosses a page boundary is split.

**Snapshots are kept until a guard changes** (`SnapshotCache`). At its first use
in each before/after phase a retained snapshot rereads all its guards. Equal:
it is used. Different or unreadable: it is discarded and the walk runs as in
1.12. Within a phase, read-only consumers share the snapshot, as the routing
observation of 1.12-opt.2 already did. Native calls, data writes and phase boundaries force the next use to
reread. A walk that met an unreadable address, or made an unguarded read, is
never kept beyond its own phase, because its result depended on something no
guard records.

**A changed snapshot is rebuilt from the spans just read** (`ReadMemo`). The
comparison that found the change has already read the current bytes of every
page involved. The new walk takes them from there and then rereads all of its
own guards from memory, which is the original consistency check. If that check
fails, or the walk is rejected, it is repeated from memory alone. These spans
live for one uninterrupted Lua phase and are dropped at every native mutation.

**Capability checks are unchanged in strength.** `cap.same()` before a throw,
detonation, reload, passenger write, Fire-flag write or input inhibition
always rereads memory, and the complete code verification runs before each
native gameplay call as before. Nothing retained can authorize an action.

The same principle is applied to the other per-phase readers:

- Native input state (Aim/Fire gates): the observation is kept and its guards
  reread each phase; the engine's selected-mapping query still runs every phase,
  after the code check and before a second guard comparison, in the original
  order. Both gates read neighbouring records of one input owner, so their
  guards are reread together once per phase.
- UI stack: a confirmed pointer/stack image is kept. While a new read of both is
  identical and the pointer is unchanged around the stack read, the second stack
  read is skipped.
- Mode labels: a maintenance pass that only read is skipped while every byte it
  read is unchanged. Without a label lease, the template walk is skipped when
  the phase's shared observation positively shows that no local C4 is selected.
  In 1.12 that walk ran every update for players not holding C4.
- Native code verification compares every guarded code byte with one read per
  page; any difference is then reported by the original per-guard comparison.
- `WindowsRead` reuses one bounded buffer instead of allocating two per read.

In the after-update phase the complete action snapshot (used by automatic
reload) is compared first when the previous update used it; the routing
observation guards a subset of the same bytes and is then compared against
those spans without reading the pages again.

## Added in 1.12-lean.2

The live profile of 1.12-lean.1 (below) showed two things worth removing.

**Bookkeeping nobody reads.** With diagnostics off, the gameplay guard built a
descriptive row and a twelve-part change key on every phase only to hand them
to a logger that discards them. It now makes the same engine calls and UI reads
in the same order and takes the same decision without building them. Mode-label
sync returns before setting up its protected pass when it holds no lease and no
local C4 is selected.

**The complete reload observation on every update.** Automatic reload needs
the whole action snapshot only while something is pending. When there is no
intent, no dismount ticket, no active weapon or avatar ability, no
interruption and spare ammunition is present, a complete observation can only
learn that an ammunition count changed or that the context became unusable. So
in the Off build it rereads the chamber, reserve and supply records on every
update (three small reads) and takes the complete observation every 100 ms
while those are unchanged. A changed record, a throw, an intent, a ticket or an
empty spare count restores per-update observation in the same update. The one
difference from 1.12: if the context becomes unusable for a reason other than
ammunition (for example the C4 descriptor stops matching), input inhibition is
released up to 100 ms later. Actions are unaffected: every throw, detonation
and reload still takes and rechecks its own snapshot.

## What it costs

Synthetic fixture, page-granular memory, reads per update:

| State | 1.12 | 1.12-opt.2 | 1.12-lean.1 | 1.12-lean.2 = 1.13 |
| --- | --- | --- | --- | --- |
| Not in a mission | 24 | not measured | 10 | 10 |
| Ordinary weapon | 196 | 128 | 40 | 40 |
| C4 selected, idle | 1064.8 | 588 | 122 | 92 |
| C4 selected, guards changing every update | 1064.8 | 588 | 226 | 129 |
| Interface open | 8 | 8 | 6 | 6 |
| Tank passenger, idle | 1155.8 | 654 | 130 | 100 |

Timings are in [VALIDATION.md](VALIDATION.md).

## What the live profile of 1.12-lean.1 showed

A diagnostic build of 1.12-lean.1 was run in the game on 2026-10-04 (twenty
30-second reports; Proton 11, about 67 updates per second in a mission):

| State | Reads per update | Time per update | Per second |
| --- | --- | --- | --- |
| Aboard the ship | 10 | 70 us | 5.4 ms |
| Mission, ordinary weapon | 36 | 86-98 us | 5.9-6.5 ms |
| C4 held, standing and moving | 119 | 176-180 us | 11.5-12.1 ms |
| Throw, detonate and reload cycles | 129-186 | 239-283 us | 15.6-19.1 ms |

- The fixture predicted 122 reads with C4 idle; the game needed 119.
- Retained snapshots hold in the game: with C4 held, 0-4 of about 2,000
  rereads per 30 seconds found a change, all in the avatar flag bytes.
- During throws and reloads the action snapshot is rebuilt on most updates.
  The changing bytes are the clocks of the active weapon and avatar abilities.
- One read costs about 0.7 us in the game. Reads were about half of the C4
  cost; the rest is Lua work. The game's Lua is LuaJIT 2.1.0-alpha, and with
  that DLL the harness runs almost as slowly with the JIT on as off.
- 60-70 us per update is present in every state: the window/UI guard about 24,
  mode-label sync including the routing reread it triggers about 16, Mod
  Bindings Menu sampling 6, the focus query 5.5.

## 1.12-lean.2 in the game

Run without instrumentation on 2026-10-04 and measured by the Watchdog
(1 ms clock, 60-second sums; states inferred from the steps in cost):

| State | 1.12-opt.2 (2026-10-03) | 1.12-lean.1 | 1.12-lean.2 = 1.13 |
| --- | --- | --- | --- |
| Aboard the ship | 6.8 ms/s | 6.5-7.2 ms/s | 3.6-4.4 ms/s |
| Mission, ordinary weapon | 8.1 ms/s | 6.2-7.1 ms/s | 4.3 ms/s |
| C4 held | 21.8-27.1 ms/s | 12.1-14.5 ms/s | 9.9 ms/s |

These are different sessions, not a same-mission comparison. At about 68
updates per second, 9.9 ms/s is about 0.14 ms per update.

## What is still not known

- A read-count profile of 1.12-lean.2 itself was not taken; the 119 reads per
  update above are from 1.12-lean.1.
- Contact tracking while Contact charges are in flight is unchanged from 1.12
  and was not profiled.
- A span whose bytes changed since the last comparison becomes a new Lua string
  of up to 4 KiB. The synthetic heap check shows no retained growth; live
  garbage volume is unmeasured.

## Replacing suppression with configuration: examined, not done

The owner asked whether Fire/Aim suppression could become a one-time data
change. Static analysis of the captured code plus a read-only live capture:

- The Fire route bit (0x2000) is chosen by whether the weapon entity has a
  particular component. The detonator does not. There is no data field.
- Entering shoulder aim asks a per-resource WeaponData byte (+0x182). The
  detonator has no per-entity override; its shared template byte is 1 and lies
  in a committed, private, **read-only** page. Writing it would need a
  protection change, which this project does not do.
- The avatar's reaction to Fire uses a threshold from a manager the detonator
  does belong to. Where that configuration lives and whether it is writable was
  not captured.

## Why not go further

Direct pointer reads instead of `ReadProcessMemory` would make validation almost
free, but a stale pointer then crashes the game instead of returning an error;
no exported Windows routine gives a guarded copy without that race. Validating
structure less often than every phase would let a compacted component array be
read through a stale address for several frames, which can leave Aim/Fire
inhibited on another weapon. Dropping the before-update or after-update pass
changes when suppression and restoration happen relative to the engine update.
None of these can be justified without live testing, so none is in this build.
The native-contact data experiment (`../native-contact-exp.2`) remains separate
and unverified.

## 繁體中文摘要

本版沒有刪減任何檢查，只改變完成同樣檢查所需的工作量：

1. 快照結果完全由它讀過並守衛的位元組決定；逐位元組重驗全部未變就沿用。
2. 同一個 4 KiB 頁面的守衛合併成一次讀取，每個守衛位元組仍逐一比對。
3. 投擲、引爆、裝填、乘客寫入、開火旗標寫入與輸入抑制前一律重新讀取並驗證。
4. lean.2 新增：關閉診斷時不再組沒人看的描述資料；沒有待處理事項且有備彈時，
   自動裝填的完整觀察改為每 100 ms 一次，但彈膛、備彈與補給紀錄仍每次更新重讀，
   一有變動立刻恢復逐次觀察。

實機量測（2026-10-04）：開發版 lean.1 持 C4 每次更新 119 次讀取、約 0.18 ms，快取幾乎都命中；
lean.2（即 1.13）以 Watchdog 量得持 C4 約 9.9 ms/s、其他狀態 3.6–4.4 ms/s。
