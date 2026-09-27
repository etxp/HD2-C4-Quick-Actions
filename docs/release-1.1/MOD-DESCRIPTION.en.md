# HD2 C4 Quick Actions 1.1

## Short description

Throw and detonate C4 with separate, customizable controls for keyboard, mouse and controllers. Version 1.1 adds Manual/Contact detonation modes, automatic reload, and support for prone, diving and vehicle passenger actions.

## Full description

With C4 equipped, use one action to throw and another to detonate, without repeatedly switching between deployment and detonation. Configure both bindings and their activation types through Mod Bindings Menu. Keyboard, mouse, Xbox and PlayStation controllers are supported. No F6 activation is needed.

### What's new in 1.1

- **Manual and Contact detonation modes:** Choose a mode in the game's existing C4 weapon-settings menu. Manual mode lets you decide when to detonate. Contact mode detonates C4 when it hits an object, while still allowing manual detonation during flight.
- **Mod Bindings Menu controls:** Configure throw and detonate separately, including release-to-throw. Separate Standard and Reversed packages are no longer needed.
- **Prone and diving support:** Throw and detonate while prone, diving or transitioning through the air.
- **Vehicle passenger support:** Use C4 from FRV and tank passenger seats. Activating throw automatically leans out and keeps the passenger out until the full throwing animation finishes.
- **Automatic reload:** Reloads after throwing when spare ammunition is available, and after resupplying from empty. Includes passenger reloads and recovery after leaving a vehicle when a reload was interrupted. Weapon switches, interfaces and other player actions can interrupt reloading.
- **Smoother throwing:** Throw and detonate bindings no longer trigger the game's normal shoulder aim. Holding a release-to-throw binding retains aiming. Also fixes throwing interrupting sprint when the throw binding shares the fire input.
- **Accidental input fixes:** Interfaces, the tactical map and the weapon-settings menu block new throw and detonate inputs. Switching detonation modes no longer consumes the C4 in your hand.

### How to use

Set **Throw C4** and **Detonate C4** on the MODS bindings page, then equip C4. Choose the detonation mode in the game's existing C4 weapon-settings menu:

- **MANUAL:** Throw a charge, then use your detonate binding.
- **CONTACT:** Detonates on collision. You can also detonate manually before impact.

Each charge keeps the mode selected when its throw began. Changing modes does not change charges already thrown. Manual detonation retains the game's normal behavior of detonating your own charges. Contact charges already in the world continue reacting to collisions after a weapon switch or while the map is open.

### Requirements

- Bingus Shared Loader **v17+ / API 1**.
- Official Mod Bindings Menu **v2+ / API 1**.
- **HD2 Mod Manager 1.3** or **HD2 Arsenal**. Both use the same ZIP.

### Installation

1. Exit the game and install/enable both dependencies.
2. Disable or remove older C4 Quick Actions packages, including Standard and Reversed editions.
3. Import `HD2-C4-Quick-Actions-1.1.zip`.
4. Select **Installation → C4 Quick Actions — MBM controls**, then deploy.
5. Start the game and configure throw and detonate on the MODS bindings page.

Enable only one C4 Quick Actions version at a time. To uninstall, disable or remove it in your manager and redeploy.

### Compatibility notes

Vehicle features apply to passenger seats, not the driver seat. New throw and detonate inputs are blocked while ragdolled.

The mod is not locked to a specific game version number. Game updates that change the internal functions or data structures it uses may still require a mod update.

If the bindings are missing from the MODS page, check that both dependencies and this mod are enabled and deployed, then restart the game.
