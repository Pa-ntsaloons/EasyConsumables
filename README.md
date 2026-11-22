# EasyConsumables

A World of Warcraft addon for **WoW Forever** (Classic rules on the modern client) that keeps a set of macros pointed at the best food, drink, potions, Healthstones and bandages in your bags. The macros update automatically whenever your bags change; if you're in combat, the update waits until combat ends.

## What it does

| Macro | What it does |
|---|---|
| `EC Food` | Best food (health) |
| `EC Drink` | Best drink (mana) |
| `EC Health` | Best health potion / Healthstone |
| `EC Mana` | Best mana potion / mana gem |
| `EC Bandage` | Best bandage you have the First Aid skill for (mouseover → friendly target → self) |
| `EC Combo` | **One-macro style:** in combat a health potion (hold the modifier for a mana potion). Out of combat it either eats and drinks at once, or eats with drink on the modifier (your choice). **Two-macro style:** health side only (food / health potion). |
| `EC Combo MP` | Two-macro style only: drink out of combat, mana potion in combat. |
| `EC Mage` | Mages only. Click = Conjure Water, Shift = Conjure Food, at the highest rank your **targeted friendly player** can use for their level (your level with no target). Alt = open trade and put conjured water + food they can use into it. You still click Trade. |
| `EC Mage Food` | Mage, two-macro style only: `EC Mage` becomes water-only and this conjures food at your target's rank. Alt-click either one to trade. |

Each consumable's tooltip is read ("Restores 61.2 health over 18 sec", "140 to 180 health", "Heals 66 damage", "restores 500 life"...), so there's no item list to keep up to date. Items you can't use yet (level or First Aid requirement) are skipped, and battleground-only items (Warsong Gulch, Arathi Basin, Alterac Valley) are only picked inside that battleground.

Tooltips are read in English, German, French, Spanish, Portuguese (BR), Russian, Chinese (simplified and traditional) and Korean. The non-English wording is in `Locales.lua`.

## Install

1. Download the latest zip from CurseForge or from [`releases/`](releases/).
2. Extract it so you have `World of Warcraft\_forever_\Interface\AddOns\EasyConsumables\EasyConsumables.toc`.
3. Restart the game (or `/reload` if you're updating and no files were added).

## Usage

- Open the options with `/ec` (or the minimap button), turn on the macros you want, and click or drag a macro's row onto your action bar.
- **Buff food** (Well Fed / XP, stat buffs) is saved by default. Turn on *Use buff food* to allow it, and *Eat it before other food* to keep the buff up.
- **Consumables page** (`/ec list`, or right-click the minimap button): every consumable you've had, sorted into Food, Drink, Buff Food, Health, Mana and Bandages. Turn one off and it's never used.
- **Cooldowns:** action buttons holding `EC Bandage` show your Recently Bandaged wait (bandages have no item cooldown, so the game never shows one). `EC Health`, `EC Mana` and the combo macros show the potion / Healthstone cooldown. Works on Blizzard's action bars and can be turned off.
- **Minimap button:** left-click for options, right-click for the Consumables page, Shift-click to rescan, drag to move. It can be hidden or set to fade out until you hover over the minimap.

## Slash commands

| Command | What it does |
|---|---|
| `/ec` | Open the options |
| `/ec status` | Show the current best item for each macro (and mage ranks for your target) |
| `/ec update` | Rescan your bags and rewrite the macros now |
| `/ec list` | Open the Consumables page |
| `/ec minimap` | Show or hide the minimap button |
| `/ec debug` | List the consumables in your bags and how each was read |
| `/ec ignore <item>` | Never pick this item (shift-click it into chat) |
| `/ec unignore <item>` | Allow an ignored item again |
| `/ec ignorelist` | List ignored items |

## Building a release

1. Set `## Version:` in `EasyConsumables.toc` and add a `## <version>` section at the top of `CHANGELOG.md`.
2. Run:

   ```
   powershell -ExecutionPolicy Bypass -File .\build.ps1
   ```

   This builds `releases\EasyConsumables-<version>.zip` with only the files the game needs (the .toc, every file it loads, and LICENSE), lists the zip's contents, and copies that version's changelog section to the clipboard for CurseForge.
3. Add `-Install` to also copy the addon into `World of Warcraft\_forever_\Interface\AddOns`.

The CurseForge description and logo are in [`media/`](media/).

If a client patch changes the interface version, update `## Interface:` in the .toc (`/dump select(4, GetBuildInfo())` in game).

## Bug reports

Please open an issue at [github.com/Pa-ntsaloons/EasyConsumables/issues](https://github.com/Pa-ntsaloons/EasyConsumables/issues). Include what the macro did and what you expected. If an item isn't recognised, include the output of `/ec debug`.

## License

MIT, see [LICENSE](LICENSE).
