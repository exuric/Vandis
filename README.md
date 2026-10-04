# Vandis

Arsenal script. Seere-style ESP rebuilt for performance, plus a silent aim that
lets you actually pick the hitbox.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/exuric/Vandis/main/Vandis.lua"))()
```

Single file. No fetching, no `require`, no `ModuleScript`, no cache, no remote
dependency. Press **Delete** to toggle the menu (`Insert` and `` ` `` also work).

If anything goes wrong at startup the menu is replaced by a red panel showing
the actual error, and the same text is printed to the executor console.

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

## ESP

`Delete` opens the menu; per-group toggles for enemy and teammates, plus shared
sliders for max distance, fade, text size and box aspect, and toggles for
outlines, short names and distance-in-name.

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

- ESP design and feature set: [Seere](https://github.com/0f76/seere_v3)
- UI/ESP reference collection: [Eazvy/UILibs](https://github.com/Eazvy/UILibs)
- Loader/structure inspiration: [QuotasHub](https://github.com/Insertl/QuotasHub)
  (open source), rewritten for this project

Vape V4's UI library (`NewGuiLibrary.lua`) is only distributed from
`vxperblx.xyz`, which no longer resolves, and the public Vape V4 copies just
reference that URL without shipping the file. The UI here is therefore written
from scratch in the same style rather than depending on a dead host.