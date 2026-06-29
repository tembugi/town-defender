# Town Defender

A small tower-defense game built in **Godot 4.7** on top of the *Tiny Swords* art pack
that ships in `Assets/`. Enemies march along the road toward your castle — build towers
on the marked slots to stop them before they break through.

## How to play

1. Open the project in Godot 4.7 (or run it from the command line):
   ```
   /Applications/Godot.app/Contents/MacOS/Godot --path .
   ```
2. **Build towers**: click a tower button in the bottom bar, then click a glowing slot
   on the map. Towers auto-attack any enemy in range.
   - **Archer Tower** (50g) — fast, cheap, single-target arrows.
   - **Bomb Tower** (110g) — slow, expensive, lobs explosives that deal splash damage.
3. **Start a wave**: press the *Start Wave* button (or `Space`). Between waves you can
   keep building.
4. **Economy**: every enemy killed drops gold; clearing a wave pays a bonus. Spend it on
   more towers.
5. **Survive**: each enemy that reaches the castle costs you castle health. Lose all 20
   and it's game over. Clear all **10 waves** to win.

### Enemies
- **Pawn** — fast, weak, cheap to kill.
- **Archer** — medium health and speed.
- **Warrior** — slow but very tanky, and costs 2 castle health if it leaks through.

Waves get bigger and add more warriors as you progress.

## Project layout

| File | Purpose |
|------|---------|
| `Main.tscn` | Entry scene (set as the project's main scene). |
| `scripts/Game.gd` | Game manager: map, waves, gold/lives, UI, build logic. |
| `scripts/Enemy.gd` | Path-following enemy with health bar. |
| `scripts/Tower.gd` | Tower targeting and firing. |
| `scripts/Projectile.gd` | Arrows (homing) and bomb shells (lobbed + splash). |
| `scripts/Anim.gd` | Builds `SpriteFrames` from the 192×192 sprite sheets at runtime. |
| `Assets/` | The Tiny Swords sprite/tileset/FX pack. |

All game objects are created in code, so the only scene file is the tiny `Main.tscn`.
