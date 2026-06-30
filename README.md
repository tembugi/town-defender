# Town Defender

A small low-poly **3D** town-defender built in **Godot 4.7**, modelled on the
Whiteout-Survival ad-minigame loop: **gather resources → build → defend against
waves**. Art is from the free [KayKit](https://kaylousberg.itch.io/) packs
(Adventurers, Character Animations, Medieval Hexagon, Skeletons) under `Models/`.

Built to run on mobile browsers — uses the `gl_compatibility` renderer (WebGL2),
a single-threaded web export, and 75% 3D render scaling on web. Deployed to
GitHub Pages via CI on every push to `main`.

## How to play

You control the **Knight** with the on-screen joystick (or `WASD`/arrows on
desktop). The camera follows you over a hex field with your **Keep** at the
centre.

1. **Gather**: walk up to a tree or rock to fell it — felling drops a resource
   pile on the ground. Walk over a pile as the hero and it's banked instantly.
2. **Hire workers** (`HIRE WORKER`, 25g / `H`): Rogues that fell nodes on their
   own, fetch loose piles (including ones you chopped), and haul them back to the
   Keep to bank gold.
3. **Build**: stand on a glowing build pad with enough gold to construct it.
   - **House** (20g) — raises the worker cap.
   - **Market** (45g) — passive gold income over time.
   - **Barracks** (80g) — adds a reusable *Train* pad; train Barbarian soldiers
     (30g each) that guard the Keep and charge nearby raiders.
4. **Defend**: press `START WAVE` (or `Space`) to send in a wave of skeletons.
   Waves are **stackable** — the button has a short cooldown (shown by a sweeping
   overlay) and displays the live count of enemies left. Skeletons use
   separation steering to fan out and besiege the Keep from all sides.
5. **Attack**: a telegraphed cone is drawn in front of the hero. A swing starts
   only when an enemy is at least partly inside it, and the hit is re-checked
   after a short wind-up — so an enemy that dodges out in time is missed.

Survive all **8 waves** to win. If the Keep's health hits zero, it's game over.

## Running locally

```
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

## Project layout

| File | Purpose |
|------|---------|
| `Main3D.tscn` | Entry scene (project main scene). |
| `scripts/Game3D.gd` | Game controller: world/hex field, camera, HUD, economy, build & wave systems, hero combat. |
| `scripts/Hero3D.gd` | Player-controlled Knight: movement, facing, attack cone. |
| `scripts/Worker3D.gd` | Rogue villager: fell → fetch drop → haul → deposit loop. |
| `scripts/Soldier3D.gd` | Barbarian Keep defender. |
| `scripts/Enemy3D.gd` | Skeleton raider: separation steering, attacks the Keep. |
| `scripts/ResourceNode3D.gd` | Harvestable tree/rock (depletes + regrows). |
| `scripts/ResourceDrop3D.gd` | Loose resource pile dropped on felling. |
| `scripts/BuildPad3D.gd` | Build-slot marker with cost label and affordability dimming. |
| `scripts/TouchJoystick.gd` | Floating virtual joystick. |
| `scripts/Rig.gd` | Shared helpers: KayKit animation retargeting, HP bars, blob shadows, colliders. |
| `Models/` | KayKit art (characters, animation rigs, hexagon buildings/tiles, skeletons). |

## Notes on the art

KayKit characters are a mesh plus a `Rig_Medium` skeleton with **no** embedded
clips; animations live in separate `Rig_Medium_*.glb` files and are merged into a
shared `AnimationLibrary` at runtime (`Rig.gd`). The Adventurers and Skeletons
rigs share the name `Rig_Medium` but are **not** cross-compatible, so each has its
own animation set.
