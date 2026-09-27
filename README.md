# Timebox Planner for Omarchy

A daily timebox planner for the [Omarchy](https://omarchy.org) shell, modeled on the paper
"Daily Timebox Planner": top priorities, a brain dump, and a half-hour schedule from 5 AM to 11 PM.
It follows your current Omarchy theme.

![Timebox Planner](preview.png)

- **Top Priorities**: three items; click the circle to mark one done.
- **Brain Dump**: free-form notes on a dotted pad.
- **Schedule**: `:00` / `:30` slots. Consecutive slots with the same text are drawn as one boxed timebox.
- A red line marks the current time on today's page.

## Install

```bash
omarchy plugin add https://github.com/HawzhinOmer/omarchy-timebox.git --enable
```

Bind it to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "Timebox planner", "omarchy-shell shell toggle hawzhin.timebox")
```

## Remove

```bash
omarchy plugin remove hawzhin.timebox
```

Then delete the keybinding line from `~/.config/hypr/bindings.lua`. Your saved days stay in
`~/.local/share/omarchy-timebox/`; delete that folder too if you don't want them.

## Requirements

Omarchy with the Quickshell-based shell (Omarchy 4 / Quattro). No other dependencies.

## Keys

| Key | Action |
| --- | --- |
| Click / drag, Shift+click | Select slots |
| Type or Enter | Fill the selected slots (Enter saves, Esc cancels) |
| Del / Backspace | Clear the selected slots |
| Arrows, Shift+arrows | Move / extend the selection |
| PgUp / PgDn | Previous / next day |
| Home | Jump to today |
| Tab | Jump to priorities, then brain dump |
| Esc | Close |

## Data

Each day is saved automatically as JSON in `~/.local/share/omarchy-timebox/YYYY-MM-DD.json`.

## License

MIT
