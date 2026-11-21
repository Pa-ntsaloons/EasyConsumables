# EasyConsumables (WoW Forever)

Keeps macros pointed at the best consumable in your bags. They update automatically whenever your bags change; if you're in combat, the update waits until combat ends.

| Macro | What it does |
|---|---|
| `EC Food` | Best food (health) |
| `EC Drink` | Best drink (mana) |
| `EC Health` | Best health potion / healthstone |
| `EC Mana` | Best mana potion / mana gem |
| `EC Bandage` | Best bandage you have the First Aid skill for (mouseover → friendly target → self) |
| `EC Combo` | **One-macro style:** in combat a health potion (hold the modifier for a mana potion). Out of combat it either eats and drinks at once, or eats with drink on the modifier (your choice). **Two-macro style:** health side only (food / health potion). |
| `EC Combo MP` | Two-macro style only: drink out of combat, mana potion in combat. |
| `EC Mage` | Mages only. Click = Conjure Water, Shift = Conjure Food, at the highest rank your **targeted friendly player** can use for their level (your level with no target). Alt = open trade and put conjured water + food they can use into it. You still click Trade. |
| `EC Mage Food` | Mage, two-macro style only: `EC Mage` becomes water-only and this conjures food at your target's rank. Alt-click either one to trade. |

## How "best" is decided
Each consumable's tooltip is read ("Restores 61.2 health over 18 sec", "140 to 180 health", "Heals 66 damage", "restores 500 life"...), so no item list needs maintaining. Items you can't use (red level / First Aid requirement) are skipped. Battleground-only items (Warsong Gulch, Arathi Basin, Alterac Valley) are only picked while you're in that battleground.

Tooltips are read in English, German, French, Spanish, Portuguese (BR), Russian, Chinese (simplified and traditional) and Korean. The non-English wording is in `Locales.lua`; if an item isn't recognised on your client, `/ec debug` shows the text that was read.

## Cooldowns
Action buttons holding `EC Bandage` show your Recently Bandaged wait (bandages have no item cooldown, so the game never shows one). `EC Health`, `EC Mana` and the combo macros show the potion / Healthstone cooldown. Works on Blizzard's action bars; can be turned off in the options.

## Commands
- `/ec`: options
- `/ec status`: current picks (and mage ranks for your target)
- `/ec update`: rescan now
- `/ec debug`: list bag consumables and how each was read
- `/ec ignore <shift-click item>` / `/ec unignore` / `/ec ignorelist`

## Install / update
Copy this folder to `World of Warcraft\_forever_\Interface\AddOns\EasyConsumables`.
If a client patch changes the interface version, update `## Interface:` in the .toc (`/dump select(4, GetBuildInfo())` in game).
