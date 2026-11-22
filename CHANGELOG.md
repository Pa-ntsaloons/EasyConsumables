# Changelog

## 2.0.0

_Released 2026-11-21_

### Fixes
- Macros no longer pick the wrong item, or nothing at all, right after logging in. Items whose data hadn't loaded yet were treated as non-consumables for the rest of the session; they're now rechecked once the data arrives, and the addon rescans a few times in the first seconds after login.
- Macros are no longer created before the game has loaded your macro list, which could make duplicates at login.
- Numbers with a comma decimal ("61,2") are read correctly.

### Consumables page
- New **Consumables** page (under EasyConsumables in the AddOns settings, or `/ec list`) lists every consumable you've had, sorted into Food, Drink, Buff Food, Health Potions & Healthstones, Mana Potions & Gems, and Bandages.
- Each item has an on/off switch. Off puts it on the ignore list, so it's never used. Off items are greyed out, and you can show only what's in your bags.

### Buff food
- Buff food now covers any food or drink that gives a buff (Well Fed / XP, stats and so on), not just Well Fed.
- **Use buff food** turns it on or off as a whole, and **Eat it before other food** puts it first. Single buff foods are switched on or off on the Consumables page.
- Your old Well Fed setting carries over.

### Cooldowns on your action bar
- EC Bandage shows your Recently Bandaged wait, which the game never shows because bandages have no cooldown of their own.
- EC Health, EC Mana and the combo macros show the potion / Healthstone cooldown. On the combo buttons it shows only in combat by default, or always if you prefer.
- While a cooldown runs, the macro name is hidden and the countdown is resized so it doesn't overlap the stack count or hotkey.
- Works on Blizzard's action bars, and can be turned off in the options.

### Languages
- Tooltips are now read in German, French, Spanish, Portuguese (BR), Russian, Chinese and Korean as well as English. Unsupported languages get a one-time notice.
- New `/ec debug` lists each consumable in your bags and how it was read. Please include it when reporting an item that isn't recognised.

### Minimap button
- New minimap button: left-click opens the options, right-click the Consumables page, Shift-click rescans your bags; hover it to see your current picks. Drag it to move it around the minimap (round or square).
- Options to show or hide it (also `/ec minimap`) and to fade it out until you hover over the minimap.

### Other
- Battleground-only food, bandages and potions are only picked inside their battleground.
- Each macro's on/off switch is now next to its row in the options.
- Code reorganised into smaller files, one per job, with no change in behaviour.

## 1.0.1

_Released 2026-11-13_

- New option **Use Well Fed (XP buff) food first**, replacing "Ignore buff food". Off (default): Well Fed food is never used, so it's saved. On: it's eaten before any other food to keep the XP buff up.

## 1.0.0

_Released 2026-11-13_

First release.

- Macros for your best food, drink, health potion / Healthstone, mana potion / mana gem and bandage, updated automatically when your bags change (deferred until after combat).
- Combo macros: food/drink out of combat, potions in combat. Either two macros (EC Combo + EC Combo MP, the default) or one macro with a modifier key. One-macro style can eat and drink together, or use the modifier for drink.
- Mage macros: conjure water and food at the highest rank your targeted friendly player can use; Alt-click to open trade and fill it with conjured items they can use. Either two macros (default) or one with Shift for food.
- Items are rated from their tooltips; conjured items win ties, but a better bought item is still used.
- Skips items you can't use yet, Well Fed buff food (optional), and anything on your ignore list.
- Options page (`/ec`) with click-or-drag macros onto your action bar.
