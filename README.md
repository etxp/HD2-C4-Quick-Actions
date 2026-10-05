# HD2 C4 Quick Actions 1.13.1

[繁體中文](README.zh-TW.md)

Throw and detonate C4 with separate, customizable controls in Helldivers 2. Set both actions through Mod Bindings Menu for keyboard, mouse, Xbox or PlayStation controllers. No F6 activation is needed.

## Version 1.13.1

Compatibility update for [Bingus Shared Loader v19](https://github.com/CowboyBingus/BingusSharedLoader/releases/tag/v19) and [Mod Bindings Menu v2.2](https://github.com/CowboyBingus/ModBindingsMenu/releases/tag/v2.2), both released 2026-10-04. Gameplay, controls and per-frame cost are those of 1.13; older loader and menu versions keep working.

- With Mod Bindings Menu v2.2, both bindings are read with one `poll` call; a refused registration is retried only when the menu changes.
- The menu's new assignments file format is read, including while the menu replaces the file.
- Windows functions are declared under this addon's own names, so another mod's declarations of the same functions can no longer break it.

Accepted in the game on 2026-10-05 with Loader v19 and the menu v2.2. [Details](docs/VALIDATION.md).

## Version 1.13

A performance release: features and controls are unchanged, and every check of the previous versions is kept. The addon now needs far less work per frame to perform them.

| Measured in the game, 2026-10-04 | before | 1.13 |
| --- | --- | --- |
| Memory reads per update, C4 in hand | about 1,265 (1.11, reported in [issue #1](https://github.com/etxp/HD2-C4-Quick-Actions/issues/1)) | 119 (development build of 1.13) |
| Memory reads per update, primary weapon | 322 (1.11, same report) | 36 |
| Addon time, C4 in hand | 21.8–27.1 ms per second (previous candidate) | 9.9 ms per second |
| Addon time, other weapon or aboard the ship | 6.8–8.1 ms per second | 3.6–4.4 ms per second |

These come from different sessions and machines; they are not a same-mission comparison and not an FPS claim. [How it works](docs/OPTIMIZATION.md) · [what was verified](docs/VALIDATION.md).

## Features

- **Manual / Contact modes:** choose in the existing C4 weapon-settings menu. Contact charges detonate on collision; manual detonation remains available during flight.
- **Custom bindings:** configure Throw C4 and Detonate C4, including release-to-throw.
- **Prone and diving:** throw and detonate through prone, diving and airborne transitions.
- **Vehicle passengers:** FRV and tank passenger support, with automatic lean-out held through the complete throw.
- **Automatic reload:** reload after throwing and after resupplying from empty. Other player actions can interrupt reload; includes recovery after an interrupted passenger reload when leaving the vehicle.
- **Smoother controls:** throw and detonate bindings suppress overlapping vanilla aim/fire inputs. Holding a release-to-throw binding retains aiming.
- **Interface protection:** map, interface, weapon-settings and ragdoll states block new actions. Changing modes does not consume the held C4.

Vehicle features apply to passenger seats, not drivers. Already thrown Contact charges retain their mode and continue reacting to collisions after a weapon switch or while the map is open.

## Requirements and installation

- Bingus Shared Loader **v17+ / API 1** (current: v19).
- Official Mod Bindings Menu **v2+ / API 1** (current: v2.2, which needs the loader v18 or newer).
- **HD2 Mod Manager 1.3** or **HD2 Arsenal**. Both use the same V1-manifest ZIP.

Disable older C4 Quick Actions editions, import `HD2-C4-Quick-Actions-1.13.1.zip` and deploy; there are no installation options. Configure **Throw C4** and **Detonate C4** on the MODS bindings page. See [installation instructions](docs/INSTALL.txt).

This repository holds the 1.13.1 source and documentation. The installable ZIP is not stored in the repository; developers can [build it from source](docs/BUILDING.md). The existing `dist/HD2-C4-Quick-Actions-v0.6.0.zip` is historical.

## Source and validation

- [Build and run offline tests](docs/BUILDING.md)
- [Architecture](docs/ARCHITECTURE.md), [performance design](docs/OPTIMIZATION.md) and [validation scope](docs/VALIDATION.md)
- [Full English mod description](docs/release-1.1/MOD-DESCRIPTION.en.md) / [繁體中文介紹](docs/release-1.1/MOD-DESCRIPTION.zh-TW.md)
- [Changelog](CHANGELOG.md) and [contribution guide](CONTRIBUTING.md)
- [Diagnostic test build](profile/INSTALL-PROFILE.txt) for measuring the addon's own cost
- [Earlier public source and research](legacy/0.6.0/README-HISTORY.md)

Runtime code is not gated on a game build number or whole-file hash. It resolves and checks the native functions and structures it uses; incompatible changes may still require a mod update. Offline tests do not establish live-game compatibility.

## Contributors

- **etxp** — project direction, feature requirements, in-game testing, feedback and release approval.
- **OpenAI Codex (AI assistant)** — assisted with implementation, debugging, offline tests, packaging, documentation and media preparation under etxp's direction (through 1.12).
- **Claude (AI assistant, Anthropic)** — the 1.13 read-path redesign, the 1.13.1 dependency update, their tests, diagnostic build and documentation, under etxp's direction.

Project-authored code and documentation use the [MIT license](LICENSE). External dependencies and game material retain their own rights; see [third-party notes](THIRD_PARTY.md).
