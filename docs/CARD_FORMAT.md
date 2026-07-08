# Koti Custom Card Format

A custom card is a small JSON file — no code. Koti interprets it with the
same lightweight widgets every built-in card uses, so custom cards are just
as fast on old tablets. Because a card is plain text, **sharing is
copy/paste**: export a card with *Copy* in the card editor, import one with
*Paste*. The importer picks their own device in the editor, which overrides
the card's `entity`.

Example cards live in [`cards/examples/`](../cards/examples/).

## Creating one

1. Long-press anywhere → edit mode → tap **+**.
2. Card type: **Custom**. Pick a device (optional but recommended).
3. Tap **Starter** for a working template, tweak, **Add**.

## Top level

```json
{
  "name": "{name}",
  "icon": "power_on",
  "entity": "switch.washer",
  "state": "{attributes.remaining} min left",
  "activeWhen": "state == 'on'",
  "progress": "attributes.progress",
  "tap": { "action": "popup" },
  "quick": { "icon": "power_on", "action": { "action": "toggle" } },
  "popup": [ ...blocks... ],
  "blocks": [ ...blocks... ]
}
```

| Field | Meaning |
|---|---|
| `name` | Card title (template). Overridden by the editor's Display name. |
| `icon` | Icon name from the bundled set (below). |
| `entity` | Default entity. Overridden by the device picked in the editor. |
| `state` | Second line of the card (template). Default `{state\|title}`. |
| `activeWhen` | Condition — when true the card gets the highlighted look. |
| `progress` | Value path drawn as a ring around the icon (0–100, or `{"value": "...", "max": 255}`). |
| `tap` | Action when the card is tapped. Defaults to opening the popup if one is defined. |
| `quick` | Small button in the card's top-right corner: `{ "icon", "action" }`. |
| `popup` | Blocks shown in the card's popup. |
| `blocks` | Optional: replace the whole card face with your own blocks (advanced — content that doesn't fit the tile is clipped). |

## Templates

`{...}` tokens are replaced with live values:

- `{state}` `{name}` `{entity_id}` `{attributes.brightness}` — the card's entity
- `{sensor.kitchen_temp.state}` `{sensor.kitchen_temp.attributes.unit_of_measurement}` — any other entity; a bare `{sensor.kitchen_temp}` means its state
- Filters after `|`: `round`, `round1`, `upper`, `lower`, `title` — e.g. `{sensor.temp.state|round}°`

Missing entities/attributes render as `—`.

## Conditions

Used by `activeWhen` and any block's `showWhen`:

```
state == 'on'          attributes.battery < 20
sensor.door.state != 'closed'      state contains 'play'
state                  (bare path: true for on/open/home/playing/…)
```

Operators: `==` `!=` `>` `<` `>=` `<=` `contains`.

## Actions

```json
{ "action": "toggle" }
{ "action": "service", "service": "vacuum.start" }
{ "action": "service", "service": "light.turn_on", "data": { "brightness": 180 } }
{ "action": "popup" }
{ "action": "none" }
```

Any action may add `"entity": "..."` to target something other than the
card's entity.

## Blocks

Every block accepts an optional `"showWhen"` condition.

| Block | Fields | Renders |
|---|---|---|
| `text` | `text` (template), `size`: `small`/`normal`/`large`/`title`, `align`, `color`: `active`/`secondary`/`#rrggbb` | A line of text |
| `icon` | `icon`, `size`, `circle` (default true), `activeWhen` | Icon in a circle |
| `entity` | `entity`, `icon` | Icon + name + live state row |
| `toggle` | `entity`, `label` | Labeled on/off switch |
| `slider` | `value` (path), `min`, `max`, `step`, `label`, `service`, `field`, `entity`, `data` | Slider; on release calls `service` with `{field: value}` |
| `progress` | `value` (path), `max` | Progress bar |
| `button` | `text` and/or `icon`, `action`, `style`: `outlined`/`filled` | One button |
| `buttons` | `buttons`: list of button fields | Row of buttons |
| `row` | `blocks` | Blocks side by side |
| `gap` | `height` | Vertical space |
| `divider` | — | Thin line |

Slider example — a brightness control:

```json
{ "type": "slider", "label": "Brightness",
  "value": "attributes.brightness", "min": 0, "max": 255,
  "service": "light.turn_on", "field": "brightness" }
```

## Freeform popup layout

By default `popup` blocks stack top-to-bottom (a `row` block groups its
children side-by-side). For pixel-precise designs — like ones exported by
the [web card builder](https://clutchthrower.github.io/koti/builder/) —
switch to canvas mode:

```json
{
  "popupLayout": "canvas",
  "canvasSize": [360, 480],
  "popup": [
    { "type": "text", "text": "{name}", "x": 0.06, "y": 0.04, "w": 0.6, "h": 0.1 },
    { "type": "icon", "icon": "light", "x": 0.75, "y": 0.02, "w": 0.2, "h": 0.15 }
  ]
}
```

`canvasSize` is the design-time reference size (any unit — only its aspect
ratio matters); every block then needs `x`, `y`, `w`, `h` as 0–1 fractions
of that canvas, placing it anywhere without affecting other blocks. Omit
`popupLayout` (or set it to `"stack"`) for the normal linear layout.

## Icons

All icons are bundled in the app (`assets/icons/`), so cards never load
anything over the network:

`access_point apple apple_tv aqi-high aqi-low aqi-medium arrow-down arrow-up
battery bedroom clock close console cooling curtain-closed curtain-open
decrease doorbell door door_open electric energy fan fridge gas heating home
homepod hot_water humidifier humidifier-on humidity increase kitchen lamp
light living-room lock lock-open lock-unlocking media menu motion music mute
pause pendant-light pendent person plant play play-next plex plug power_off
power_on purifier scenes skip_next skip_previous sony speaker temp-high
temp-low temp-medium thermostat tv tv-play unmute updates vacuum
vacuum-charge vacuum-clean wifi`

An unknown icon falls back to `home` (the editor warns you).

## Sharing your cards

PRs adding cards to `cards/examples/` are welcome — keep entity IDs generic
(`switch.washer`, not `switch.willys_washer_3`) since importers re-pick the
device anyway.
