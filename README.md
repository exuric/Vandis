# Vandis

Arsenal script. Seere-style ESP rebuilt for performance, plus a silent aim that
lets you actually pick the hitbox.

## Load

```lua
loadstring(game:HttpGet("https://cdn.jsdelivr.net/gh/exuric/Vandis@main/Vandis.lua"))()
```

> **Use the jsDelivr link, not `raw.githubusercontent.com`.** GitHub's raw CDN
> serves stale copies for a long time after a push - it was still handing out a
> 251 KB build hours after the 264 KB one was committed. jsDelivr invalidates
> correctly. If the menu is missing a feature you know is in the readme, you are
> almost certainly on a cached file.

Single file, no fetching, no `require`, no `ModuleScript`, no cache.

- **RightShift** toggles the menu (Abyss default).
- **Delete** and `` ` `` also toggle it, and these deliberately ignore
  `gameProcessedEvent` so they still work when the game has a gui focused.

If anything fails during startup a red panel appears with the error and a
traceback, and the same text is printed to the executor console. The first line
printed is always an environment probe:

```
[Vandis] v5 probe: drawing=true player=<name> gui=true gameProcessedEvent=n/a
```

so you can tell instantly whether the failure is a missing `Drawing` API, no
`PlayerGui`, or something inside the library.

## UI

Built on [Abyss](https://github.com/Eazvy/UILibs/tree/main/Librarys/Abyss). The
library source is vendored inline (upstream lines 1-4257 of
`Librarys/Abyss/Example`, which is the library plus a demo; the demo half is
dropped). Because the library exposes its table as a local in the same chunk,
loading the script runs the library and then wires the modules up in one go.

API used: `Library.Window`, `Window:Tab`, `Tab:Section`, and the
`Toggle` / `Slider` / `Dropdown` / `Keybind` / `Label` elements, with values
read back from `Library.Flags`.

## Silent aim — hitting the head

Shots that should land on the head resolving on the torso is a target-selection
problem, so it is exposed as options instead of hardcoded.

| Option | Values |
| ------ | ------ |
| `hitbox` | `Head`, `Upper Torso`, `Torso`, `Root`, `Closest`, `Auto` |
| `head priority` | while the head is inside `head snap`, nothing else can steal the shot |
| `head snap` | 5-200 px, how far off the head still counts as a head hit |
| `fov` | 20-600 px selection radius |
| `max distance` | |
| `method` | `Raycast` answers the game's own raycast with one aimed at the target part; `Camera` swings the camera for the shot frame |
| `smoothness` | `Camera` method only |
| `hit chance` | 0-100 % |
| `show fov` | |
| `team check` / `neutral is enemy` / `require alive` | |

`Ctrl+P` marks the current target as a priority target (own colour set).

## ESP

Per-group toggles for enemy and teammates, sliders for max distance, fade, text
size and box aspect, and toggles for outlines, short names and distance-in-name.

### Why this one does not lag

The Seere ESP this is modelled on does a lot of avoidable work every frame, for
every player:

- 3-4 `FindFirstChild` calls per player per frame just to test if they are alive
- a `players:FindFirstChild` by name per player per frame
- a new `RaycastParams` allocated for every visibility raycast
- a fresh table of 8 `CFrame`s and several `Vector2`s per box
- a distance string rebuilt with `tostring()` every frame
- roughly 30 `Drawing` objects per player created whether the feature is on or not

All unconditional, all at render rate. This version:

- resolves body parts once and invalidates them via signal, never per frame
- creates a `Drawing` the first time its feature is actually enabled
- writes a property only when the value has genuinely changed
- rebuilds distance/health strings only when the displayed value changes
- updates near targets every frame, 120-300 / 300-600 / 600+ studs on every
  2nd / 3rd / 4th frame, and only resets a target's drawings on frames it is
  actually redrawn so banded targets do not flicker
- caps visibility raycasts at 6 per frame on one reused `RaycastParams`, caching
  each answer for 4 frames
- computes the box from 2 viewport projections instead of ~10

## Credits

- UI library: [Abyss](https://github.com/Eazvy/UILibs/tree/main/Librarys/Abyss),
  vendored inline
- ESP design and feature set: [Seere](https://github.com/0f76/seere_v3)
- UI/ESP reference collection: [Eazvy/UILibs](https://github.com/Eazvy/UILibs)
- Loader/structure inspiration: [QuotasHub](https://github.com/Insertl/QuotasHub)
  (open source), rewritten for this project

Vape V4's UI library (`NewGuiLibrary.lua`) is only distributed from
`vxperblx.xyz`, which no longer resolves, and the public Vape V4 copies only
reference that URL without shipping the file. Abyss is used instead.