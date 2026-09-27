# Third-party references

The project's MIT license covers project-authored code and documentation. It does not relicense Helldivers 2 or external projects. The repository does not bundle the game executable, extracted game assets, the loader runtime or third-party repositories.

## Runtime and packaging dependency

- [Bingus Shared Loader](https://github.com/CowboyBingus/BingusSharedLoader), by CowboyBingus. Runtime contract: v15+ / API 1. The packaging helper is pinned to commit `836427cef78b8a67cf771c1f16291d93be921744`; its two Python files are checked against [locked hashes](dependencies.lock.json). The helper is invoked from a separately obtained checkout and is not copied into this repository. See its [authoring contract](https://github.com/CowboyBingus/BingusSharedLoader/blob/836427cef78b8a67cf771c1f16291d93be921744/docs/AUTHORING.md).

## Research references

- [ConsistentVaulting](https://github.com/CowboyBingus/ConsistentVaulting/tree/57b6b277373d6192d612396815c283ab17e6f2cc): local-player ownership and native context research.
- [Helldivers2_RawData](https://github.com/Darctor/Helldivers2_RawData/tree/23f3258faa63a8cc3037c3d7198de7ea75f2abde): historical C4 component and enumeration leads.
- [HD2SDK Community Edition](https://github.com/Boxofbiscuits97/HD2SDK-CommunityEdition/tree/974b80a7e048b13221637eb9136006bb10ab5068): archive and resource-format research.
- [Filediver](https://github.com/xypwn/filediver/tree/cc6d9409a9b7700b0e4b0e1ee3a924d1d8e9d83f): resource names and state-machine schema cross-checks.
- Autodesk engine API documentation: [Window](https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/obj_stingray_Window.html), [Pad](https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/ns_stingray_Pad1.html), [PS4Pad](https://help.autodesk.com/cloudhelp/2019/ENU/Max-Interactive-Help/lua_ref/ns_stingray_PS4Pad1.html). These describe engine APIs, not a blanket compatibility guarantee for this game.

Native code signatures and structural constants in the runtime are build-verification data derived from the tested game build; they are not a separately licensed replacement for game code. External names and trademarks remain with their respective owners.

The project license uses the standard [MIT license text](https://opensource.org/license/mit).

## Cover artwork

The cover uses a gameplay frame supplied by the repository owner, with HUD cleanup and typography created using the built-in image generation tool. The original frame, exact editing prompt and provenance are included in [assets/ARTWORK.md](assets/ARTWORK.md). The project's code license does not relicense the game's artwork.
