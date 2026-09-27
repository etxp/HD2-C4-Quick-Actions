# HD2 C4 Quick Actions 1.1

[繁體中文](README.zh-TW.md)

Throw and detonate C4 with separate, customizable controls in Helldivers 2. Set both actions through Mod Bindings Menu for keyboard, mouse, Xbox or PlayStation controllers. No F6 activation is needed.

## Version 1.1

- **Manual / Contact modes:** choose in the existing C4 weapon-settings menu. Contact charges detonate on collision; manual detonation remains available during flight.
- **Custom bindings:** configure Throw C4 and Detonate C4, including release-to-throw. No separate Standard / Reversed packages.
- **Prone and diving:** throw and detonate through prone, diving and airborne transitions.
- **Vehicle passengers:** FRV and tank passenger support, with automatic lean-out held through the complete throw.
- **Automatic reload:** reload after throwing and after resupplying from empty. Other player actions can interrupt reload; includes recovery after an interrupted passenger reload when leaving the vehicle.
- **Smoother controls:** throw and detonate bindings suppress overlapping vanilla aim/fire inputs. Holding a release-to-throw binding retains aiming.
- **Interface protection:** map, interface, weapon-settings and ragdoll states block new actions. Changing modes does not consume the held C4.

Vehicle features apply to passenger seats, not drivers. Already thrown Contact charges retain their mode and continue reacting to collisions after a weapon switch or while the map is open.

## Requirements and installation

- Bingus Shared Loader **v17+ / API 1**.
- Official Mod Bindings Menu **v2+ / API 1**.
- **HD2 Mod Manager 1.3** or **HD2 Arsenal**. Both use the same V1-manifest ZIP.

Disable older C4 Quick Actions editions, import `HD2-C4-Quick-Actions-1.1.zip`, select **Installation → C4 Quick Actions — MBM controls**, and deploy. Configure **Throw C4** and **Detonate C4** on the MODS bindings page. See [installation instructions](docs/INSTALL.txt).

This repository update publishes the 1.1 source and documentation only. It does not create a GitHub Release or add the 1.1 binary ZIP. The existing `dist/HD2-C4-Quick-Actions-v0.6.0.zip` is historical, not the current version. Developers can [build 1.1 from source](docs/BUILDING.md).

## Source and validation

- [Build and run offline tests](docs/BUILDING.md)
- [Architecture](docs/ARCHITECTURE.md) and [validation scope](docs/VALIDATION.md)
- [Full English mod description](docs/release-1.1/MOD-DESCRIPTION.en.md) / [繁體中文介紹](docs/release-1.1/MOD-DESCRIPTION.zh-TW.md)
- [Changelog](CHANGELOG.md) and [contribution guide](CONTRIBUTING.md)
- [Earlier public source and research](legacy/0.6.0/README-HISTORY.md)

Runtime code is not gated on a game build number or whole-file hash. It resolves and checks the native functions and structures it uses; incompatible changes may still require a mod update. Offline tests do not establish live-game compatibility.

## Contributors

- **etxp** — project direction, feature requirements, in-game testing, feedback and release approval.
- **OpenAI Codex (AI assistant)** — assisted with implementation, debugging, offline tests, packaging, documentation and media preparation under etxp's direction.

Project-authored code and documentation use the [MIT license](LICENSE). External dependencies and game material retain their own rights; see [third-party notes](THIRD_PARTY.md).
