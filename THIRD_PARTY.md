# Third-party material

The MIT license covers project-authored code and documentation. It does not relicense Helldivers 2, external mods, native game material or existing game-derived artwork.

## Dependencies

- Bingus Shared Loader, by CowboyBingus: runtime v17+ / API 1. Runtime checks require the loader's internal version value to be at least 16, as documented in `docs/INSTALL.txt`.
- Official Mod Bindings Menu: runtime v2+ / API 1. Install separately; its source/runtime is not bundled here.
- The external [BingusSharedLoader packaging helper](https://github.com/CowboyBingus/BingusSharedLoader/tree/836427cef78b8a67cf771c1f16291d93be921744) is pinned by commit and file hashes in `dependencies.lock.json`. The pin concerns packaging tools only and does not restrict game versions. Obtain it separately as described in `docs/BUILDING.md`.
- LuaJIT 2.1 runs the tests; Python 3.10+ and libdeflate-gzip are build tools. Their implementations are not included.

Native signature catalogs and structural constants are compatibility data used by the mod and fixtures, not replacement game code. Full game binaries, extracted asset collections and private native-memory captures are not included. The fixture's iterator signature is the same small contract already checked by the runtime.

The existing `assets/` artwork and `dist/` binary predate this source-only update. Their provenance remains in `assets/ARTWORK.md`. Earlier research references and attribution are preserved in `legacy/0.6.0/THIRD_PARTY.md`. No new recordings, audio models, voice samples, external mod code or raw runtime logs are added by this update.
