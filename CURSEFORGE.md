# EasyConsumables

**Always press the right button.** EasyConsumables keeps a set of macros pointed at the best food, drink, potions, healthstones and bandages in your bags, and updates them automatically whenever your bags change. Mages get macros that conjure the right rank of water and food for whoever they're targeting.

No item lists to go out of date: every consumable's tooltip is read, so it works with any food, potion or bandage the game has.

---

## Macros

| Macro | What it does |
|---|---|
| **EC Food** | Your best food |
| **EC Drink** | Your best drink |
| **EC Health** | Your best health potion or Healthstone |
| **EC Mana** | Your best mana potion or mana gem |
| **EC Bandage** | Your best bandage you have the First Aid skill for. Uses it on your mouseover, then your friendly target, then yourself. |
| **EC Combo** + **EC Combo MP** | One button per side: food or drink out of combat, health or mana potion in combat. |
| **EC Mage** + **EC Mage Food** | *Mages only.* Conjures water / food at the highest rank your targeted friendly player can use for their level. |

Turn macros on or off in `/ec`, then click or drag them from the options page straight onto your action bar.

## Smart picking

- **Best item wins.** The item that restores the most is used.
- **Conjured first on a tie.** Mage food is used before bought food that's just as good, but a bought item that's *better* is still used.
- **Skips what you can't use.** Items above your level or First Aid skill are ignored.
- **Well Fed (XP buff) food, your call.** By default it's never used, so it's saved. Turn on *Use Well Fed (XP buff) food first* to eat it before anything else and keep the buff up while leveling.
- **Healthstones before potions**, since they're free and have their own cooldown (optional).
- **Ignore list:** `/ec ignore <item>` (shift-click the item) keeps it out of every macro.

## Combo macros

Turn them on in `/ec`. By default you get two:
- **EC Combo:** food out of combat, health potion in combat.
- **EC Combo MP:** drink out of combat, mana potion in combat.

Prefer a single button? Switch to **one macro**:
- In combat it uses a health potion, or a mana potion while you hold a modifier (Shift, Ctrl or Alt).
- Out of combat it either **eats and drinks at the same time**, or **eats, with the modifier for drink**. Your choice.

## Mages: conjure for your target

Target a friendly player and press **EC Mage** for water or **EC Mage Food** for food. The highest rank *they* can use at their level is picked automatically, so no more Crystal Water for a level 30. With no target, it uses your level.

**Alt-click** either macro to open a trade with your target and fill it with conjured water and food they can use. You just click Trade.

Prefer one button? Switch to a single **EC Mage** macro: click for water, Shift-click for food.

## Commands

- `/ec`: open options
- `/ec status`: show what each macro is currently using
- `/ec update`: rescan your bags now
- `/ec ignore <item>` / `/ec unignore <item>`: shift-click an item to add or remove it from the ignore list
- `/ec ignorelist`: show ignored items
- `/ec help`: list all commands

## Good to know

- **Combat:** the game doesn't allow macros to be edited during combat, so changes made in combat apply the moment it ends.
- **Macro slots:** macros are created as character-specific by default. Each uses one of your macro slots.
- **Language:** requires an **English** game client (it reads tooltip text).

Bugs or ideas? Leave a comment. Please include what the macro did and what you expected.
