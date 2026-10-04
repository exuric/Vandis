# Vandis

Arsenal-focused script with a Seere-style ESP and a silent aim that lets you
actually choose the hitbox.

## Load

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/exuric/Vandis/main/Vandis.lua"))()
```

Everything else (UI library and modules) is pulled from this repo on first run
and cached locally, so only the line above is needed each time.

Press **Delete** to toggle the menu. `Insert` and `` ` `` also work, because
executors and the Roblox client each swallow some of these keys.

If the menu does not appear at all after loading, delete the `Vandis` folder in
your executor's filesystem and run the load line again.

## Layout

| Path                  | What it is                                        |
| --------------------- | ------------------------------------------------- |
| `Vandis.lua`          | Entry point: fetch, cache, build the menu, bind UI |
| `lib/universe.lua`    | UI library (vendored)                              |
| `modules/core.lua`    | Services, per-player cache, team/weapon helpers    |
| `modules/esp.lua`     | ESP                                                |
| `modules/silentaim.lua` | Silent aim                                       |

## Silent aim — hitting the head

The old complaint was that shots which should land on the head were resolving
on the torso. That is a target-selection problem, so it is exposed as options
instead of being hardcoded.

| Option | Values | Notes |
| ------ | ------ | ----- |
| `hitbox` | `Head`, `Upper Torso`, `Torso`, `Root`, `Closest`, `Auto` | `Head` hard-locks the head and falls back down the body only if the head is gone |
| `head priority` | on/off | While the head is inside `head snap radius`, nothing else can steal the shot |
| `head snap radius` | 5-200 px | How far off the head still counts as a head hit |
| `fov` | 20-600 px | Selection radius around the crosshair |
| `method` | `Raycast`, `Camera` | `Raycast` answers the game's own raycast with one aimed at the target part; `Camera` swings the camera for the shot frame |
| `hit chance` | 0-100 % | |
| `smoothness` | 0-100 | `Camera` method only |

`team check`, `neutral is enemy` and `require alive` gate target selection.

## ESP

Toggles per group (enemy / teammates), plus a shared column for max distance,
fade, text size, box aspect, outlines, short names and distance-in-name.
`Ctrl+P` marks the current target as a priority target.

### Why this one does not lag

The Seere ESP this is based on does a lot of avoidable work every frame, for
every player:

- 3-4 `FindFirstChild` calls per player per frame just to test if they are alive
- a `players:FindFirstChild` by name per player per frame
- a brand new `RaycastParams` allocated for every visibility raycast
- a fresh table of 8 `CFrame`s and several `Vector2`s allocated per box
- a distance string rebuilt with `tostring()` every frame
- roughly 30 `Drawing` objects per player created up front whether the feature
  is on or not

All of it runs unconditionally at render rate. This version:

- resolves body parts once and invalidates them via signals, never per frame
- creates a `Drawing` the first time its feature is actually enabled
- only writes a property when the value has genuinely changed
- rebuilds the distance/health strings only when the displayed value changes
- updates near targets every frame, and 120-300 / 300-600 / 600+ studs every
  2nd / 3rd / 4th frame
- caps visibility raycasts at 6 per frame and reuses one `RaycastParams`,
  caching each player's answer for 4 frames
- computes the box from 2 viewport projections instead of ~10
- hides a player's drawings on the frames they are actually redrawn, so banded
  targets do not flicker

## Credits

- ESP design and feature set: [Seere](https://github.com/0f76/seere_v3)
- UI library: [Universe](https://github.com/Eazvy/UILibs/tree/main/Librarys/Universe)
  (upstream source `hemvi/cripware-archive`, vendored as `lib/universe.lua`)
- ESP/UI reference collection: [Eazvy/UILibs](https://github.com/Eazvy/UILibs)
- Loader/structure inspiration: [QuotasHub](https://github.com/Insertl/QuotasHub)
  (open source), rewritten for this project

Both upstream projects are open source; their work is credited above. The UI
library is vendored in `lib/universe.lua` with one local change: the menu toggle
key was moved from `Insert` to `Delete`.