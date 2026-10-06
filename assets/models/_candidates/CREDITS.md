# Evaluation candidates — free rigged soldiers

Downloaded for comparison only. Nothing here is wired into the game.
Source: https://poly.pizza (direct glTF from static.poly.pizza).

| File | Author | Licence | Tris | Surfaces | Materials | Joints | Reads as |
|---|---|---|---|---|---|---|---|
| SWAT_Quaternius | Quaternius | **CC0** | 7,752 | 9 | 4 | 62 | police/SWAT, not army |
| Soldier_Quaternius | Quaternius | **CC0** | 7,900 | 11 | 6 | 62 | tactical operative, no helmet |
| Character-Soldier_Quaternius | Quaternius | **CC0** | 20,712 | 60 | 14 | 43 | cartoon/chibi soldier |
| Military-man_madtrollstudio | madtrollstudio | CC-BY 3.0 | 12,202 | 6 | 1 (+tex) | 64 | closest to a uniformed soldier |
| Soldier_KolosStudios | KolosStudios | CC-BY 3.0 | 3,095 | 7 | 5 | 49 | armoured trooper |
| Soldier_J-Toastie | J-Toastie | CC-BY 3.0 | 4,757 | 15 | 15 | 40 | Mixamo rig; bind AABB unusable |

Poly Pizza labels some Quaternius models CC-BY 3.0. That is a Poly Pizza
mislabel: quaternius.com's FAQ states "All models are under the CC0
License" and "Attribution is not necessary", for commercial use included.
Everything by Quaternius above is therefore CC0.

Ours, for scale: rifle_soldier, 1,488 tris, 3 surfaces, **2 draw calls**.

## The problem with all of them

Every one carries 4-15 materials where ours has 2. With the shadow pass
that is 8-30 draw calls per soldier against our 2, which would undo the
Phase 6 and 7 draw-call work outright. They are flat-colour with no
textures (except madtroll), so the fix is baking materials down to vertex
colours - the thing om_kit already does - but it is real work per model.

Attribution: anything CC-BY that ships must be credited, as
assets/models/nature/CREDITS.md already does. CC0 carries no obligation.
