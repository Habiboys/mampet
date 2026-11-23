# MamPet 2D Monster Animation Pipeline & Refactoring Guide

This document describes the architecture, asset pipeline, validation workflow, and honest per-character status for MamPet's **local-first, offline 2D interactive monster animation system** in Flutter.

---

## 1. Architecture Overview

MamPet renders interactive 2D monsters natively in Flutter without any external game engine, backend, or paid runtime SDK:

- **Data-driven rigs (`rig.json`)** define transparent 1024×1024 PNG layers, z-order, normalized pivot coordinates (`[0.0 .. 1.0]`), parent-child transform hierarchy, mutually-exclusive expression slots (`eyes`, `mouth`), and normalized body-part touch hitboxes.
- **Data-driven animations (`animations.json`)** define smooth keyframe tracks (`dx`, `dy`, `rot_deg`, `scale_x`, `scale_y`, `opacity`) across 7 gameplay states (`idle`, `happy`, `pet`, `eat`, `sleep`, `play`, `evolve`), randomized eye blink timing, and chewing mouth alternation.
- **Single-Ticker State Machine (`MonsterAnimationController`)** interpolates keyframes using smooth cosine easing and blends smoothly over `180 ms` between state transitions so characters never pop or snap.
- **Hierarchical Parent-Child Renderer (`MonsterRigRenderer`)** composes `Matrix4` transforms from root (`body`) down to children (`head -> eyes_open / mouth_happy`, `body -> wing_left / wing_right / tail`), ensuring joints and facial expressions stay pixel-locked during breathing, bouncing, and head tilts.
- **Zero-Latency Interaction (`MonsterInteractionHandler`)** maps single taps to the most specific matching body-part hitbox (`head`, `wing_left`, `tail`, `cap`, `body`, etc.) with 0 ms gesture-arena delay, and detects rapid double-taps (`≤ 320 ms`) for excited `play` bursts.
- **Battery & Memory Safety**:
  - `InteractiveMonster` automatically pauses its `Ticker` when the app enters background (`WidgetsBindingObserver`) or when `reduceMotion` is enabled.
  - `MonsterDex` grid cards continue to render lightweight static previews (`MonsterPreview` using `assets/monsters/<slug>/<stage>.png`) so 20 layered rigs are never animated simultaneously.
  - Dev-only QA files (`original.png`, `comparison.png`, `preview.gif`) are preserved on disk under each character folder but excluded from `pubspec.yaml` so Android release APKs remain compact.

---

## 2. Flutter Code Layout

| File | Responsibility |
|---|---|
| `lib/features/monsters/models/monster_rig.dart` | `MonsterRig`, `RigLayer`, `RigHitbox`, `RigTier`, and species ID (`01`–`20`) ↔ slug resolver |
| `lib/features/monsters/animation/monster_animation_state.dart` | `MonsterAnimation` enum (`idle`, `happy`, `pet`, `eat`, `sleep`, `play`, `evolve`) |
| `lib/features/monsters/animation/monster_animation_config.dart` | `MonsterAnimationConfig`, `AnimationStateConfig`, `KeyframeTrack`, `LayerTransform` |
| `lib/features/monsters/animation/monster_rig_repository.dart` | In-memory cached JSON loader with graceful whole-body fallback |
| `lib/features/monsters/animation/monster_animation_controller.dart` | State machine, cross-pose blending, auto-blinking, chewing alternation, sleep/wake, speed |
| `lib/features/monsters/animation/monster_rig_renderer.dart` | Hierarchical `Matrix4` layer renderer, floating sleep `Zzz`, live pivot & hitbox debug painter |
| `lib/features/monsters/animation/monster_interaction_handler.dart` | Zero-latency body-part hitbox hit-testing & rapid double-tap detection |
| `lib/features/monsters/widgets/interactive_monster.dart` | Reusable public `InteractiveMonster` widget used on Home, Detail, Evolution, and Preview Lab |
| `lib/features/monsters/widgets/monster_preview.dart` | Lightweight static preview widget for MonsterDex lists/grids |
| `lib/features/monsters/screens/animation_preview_screen.dart` | Developer **Animation Preview Lab** (`/dev/animation-preview`) |

---

## 3. Asset Directory Layout

```text
assets/monsters/
  rig_manifest.json                     # Authoritative index of all 60 characters & rig tiers
  <slug>/
    baby.png / young.png / adult.png    # Lightweight 400x400 static previews (MonsterDex & Android Widget)
    <stage>/
      original.png                      # Preserved untouched 1024x1024 source master (disk backup only)
      rig.json                          # Layer hierarchy, pivots, z-order, hitboxes (bundled in APK)
      animations.json                   # 7-state keyframe curves & blink config (bundled in APK)
      layers/                           # Quantized transparent 1024x1024 RGBA PNG layers (bundled in APK)
        body.png
        head.png                        # (optional per anatomy)
        wing_left.png / tail.png / ...  # (species-specific appendages/accessories)
        eyes_open.png / eyes_closed.png / eyes_sleep.png
        mouth_happy.png / mouth_neutral.png / mouth_eating.png
      comparison.png                    # Visual QA comparison sheet (disk QA only)
      preview.gif                       # Animated showcase preview GIF (disk QA only)
```

---

## 4. How to Add or Upgrade a Monster Rig

1. **Inspect on a 1024×1024 Coordinate Grid**
   - Generate a coordinate grid using `tools/make_hero_grids.py` to measure exact polygon cut lines, eye/mouth bounds, and anatomical pivot joints.
2. **Follow the 3 Golden Rules of Seamless 2D Rigging**
   - **Behind-parent appendages (`z < parent_z`)** (e.g. `tail`, `wing_left`, `wing_right`, `gills`, `ears`, `fins`): cut cleanly outside the parent's dark outline and extend the hidden root `+35–50 px` behind the parent so rotating never exposes a seam gap.
   - **In-front accessories (`z > parent_z`)** (e.g. `cap`, `chef_hat`, `crown`, `cherry`, `sprout`, `leaf`): never draw boxy root extensions on top; instead reconstruct the occluded parent fur/skin/head surface underneath.
   - **Clean facial sockets**: harmonic-inpaint occluded eye/mouth sockets excluding dark cartoon outline pixels (`lum < 115`) so alternative closed/sleeping/eating expressions never leave dark fringes.
3. **Register & Generate**
   - Add or update the character entry in `FULL_RIG_SPECS` inside `tools/refactor_all_monsters.py` (or place hand-painted artist PNGs in `assets/monsters/<slug>/<stage>/layers/` with matching `rig.json` & `animations.json`).
   - Run the pipeline, validator, and `pubspec.yaml` synchronizer:
     ```powershell
     python tools/refactor_all_monsters.py
     python tools/validate_monster_rigs.py
     python tools/sync_pubspec_assets.py
     ```
4. **Verify Visually & Interactively**
   - Inspect `assets/monsters/<slug>/<stage>/comparison.png` and `preview.gif`.
   - Launch MamPet → **Settings → Animation Preview Lab** (`/dev/animation-preview`) to test all 7 states, slow-motion (`0.25×`), transparent checkerboard edges, live pivot crosshairs, hitboxes, and FPS on device.

---

## 5. Honest Progress & Asset Quality Report (All 60 Characters)

Per project quality standards, every character is classified honestly by its actual `rig_tier` in `assets/monsters/rig_manifest.json`:

| Rig Tier | Count | Description |
|---|---:|---|
| **`full_layered`** | **26** | Multi-part anatomical layers + hidden joint root overlap + 6 facial expression layers (`eyes_open`, `eyes_closed`, `eyes_sleep`, `mouth_happy`, `mouth_neutral`, `mouth_eating`) + species hitboxes + `comparison.png` + `preview.gif` |
| **`whole_body`** | **32** | Clean 1024×1024 transparent `body.png` with exact ground pivot, head/body hitboxes, and species-archetype 7-state elastic animations; dense overlapping Young/Adult artwork (flames, vines, armor, props) preserved unchopped until manual artist layer separation |
| **`needs_manual_art`** | **2** | Source master image in `monster_collection_60_complete_flutter.zip` is corrupted/blank or duplicated from another species — requires original artist illustration |

### 5.1 Full Layered Interactive Rigs (26 / 60 — Covers 100% of All 20 Species!)

Every single one of MamPet's **20 species** has a full multi-part interactive layered rig for its **Baby** form (the form unlocked first on hatch/onboarding), plus **6 key Young & Adult stages**:

- **All 3 Starters**: `fox/baby`, `fox/young`, `leaf_spirit/baby`, `pink_axolotl/baby`, `pink_axolotl/young`
- **All 3 Fire Dragon Stages**: `fire_dragon/baby` (reference benchmark), `fire_dragon/young` *(trapped PNG checkerboard inside wing-neck loop cleaned)*, `fire_dragon/adult`
- **Additional Young Stages**: `water_slime/young`, `mushroom/young`
- **All Remaining Baby Species (15)**: `leaf_gorilla/baby`, `sky_bird/baby`, `water_slime/baby`, `dessert_panda/baby`, `lamb/baby`, `bread_turtle/baby`, `sea_dragon/baby`, `moss_golem/baby`, `dessert_ghost/baby`, `bee_moth/baby`, `ice_fox/baby`, `forest_deer/baby`, `chef_penguin/baby`, `mage_cat/baby`, `mushroom/baby`, `bamboo_panda/baby`

### 5.2 Whole-Body Archetype Rigs Awaiting Artist Layer Separation (32 / 60)

All remaining Young & Adult stages (`leaf_gorilla/{young,adult}`, `sky_bird/{young,adult}`, `fox/adult`, `water_slime/adult`, `pink_axolotl/adult`, `dessert_panda/{young,adult}`, `lamb/{young,adult}`, `bread_turtle/{young,adult}`, `sea_dragon/{young,adult}`, `moss_golem/{young,adult}`, `dessert_ghost/{young,adult}`, `bee_moth/{young,adult}`, `ice_fox/{young,adult}`, `forest_deer/{young,adult}`, `chef_penguin/{young,adult}`, `mage_cat/{young,adult}`, `mushroom/adult`, `bamboo_panda/{young,adult}`) feature intricate overlapping flames, floral wreaths, ribbons, utensils, or multi-tail wraps. Rather than faking rectangular crops that would expose broken joints, they use honest `whole_body` archetype-tuned animations with explicit upgrade notes in `rig.json`.

### 5.3 Source Master Defects Requiring Manual Artist Illustration (2 / 60)

1. **`assets/monsters/leaf_spirit/young.png`**: Master file inside `monster_collection_60_complete_flutter.zip` is effectively blank (only `0.8%` faint pixels). Marked `needs_manual_art`; needs original Leaf Spirit Young artwork.
2. **`assets/monsters/leaf_spirit/adult.png`**: Master file inside `monster_collection_60_complete_flutter.zip` is an exact visual duplicate of `forest_deer/adult.png`. Marked `needs_manual_art`; needs original Leaf Spirit Adult artwork.
3. *(Cleaned automatically during refactoring)*: `fire_dragon/young.png` had trapped gray-white PNG checkerboard squares inside the wing-neck loop, and `fox/young.png` had a stray blue left-edge artifact plus trapped tail-neck checkerboard — both were cleanly repaired in their refactored layers while keeping untouched `original.png` backups.
