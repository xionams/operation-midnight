# Third-party nature assets

Everything in this directory is from **Kenney's Nature Kit (2.1)**.

- Source: https://kenney.nl/assets/nature-kit
- Licence: **CC0 1.0 Universal** (public domain dedication)
  https://creativecommons.org/publicdomain/zero/1.0/
- Author: Kenney (www.kenney.nl)

CC0 requires no attribution. This file exists anyway, because knowing
which art in a repository is ours and which is not is worth more than the
licence strictly demands.

## Why these and not our own

The generated greyboxes in `assets/models/` are built from
`tools/asset_specs.py`, which can express boxes and cylinders. That is
adequate for a war factory, whose real-world shape is close to a box. It
is not adequate for a tree: ours was three stacked cylinders, and no
amount of lighting or texturing makes a cone on a stick read as a tree.

The split is deliberate and it is not "ours vs theirs", it is
**gameplay-bearing vs scenery**:

- **Units and structures stay generated.** They carry the `Faction`
  material slot the runtime recolours, and their dimensions have to match
  the `body_size` that selection rings, health bars and placement
  footprints are derived from. See docs/ART_DIRECTION.md sections 5 and 8.
- **Nature is scenery.** It carries no faction, blocks nothing the player
  reasons about, and has no dimension contract with gameplay.

## Modifications

Unmodified geometry. Each model's import is scaled to game metres via
`nodes/root_scale` in its `.import` file, because the kit is authored at
roughly 1 unit per tile rather than 1 unit per metre. Materials are
replaced at runtime by `scripts/core/scenery.gd`, which re-shades every
scenery surface with the fog shader so props cannot show through the
shroud.
