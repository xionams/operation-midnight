#!/usr/bin/env python3
"""Point each *Stats resource at its greybox model.

This is the whole integration surface. Gameplay reads `visual_scene` and
instantiates whatever it finds, so swapping a greybox for final art later
means replacing a .glb - no scene edits, no code changes.
"""

import os
import re

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

MAPPING = {
    "config/units/rifle_soldier.tres": "rifle_soldier",
    "config/units/at_squad.tres": "at_squad",
    "config/units/engineer.tres": "engineer",
    "config/units/spy.tres": "spy",
    "config/units/attack_dog.tres": "attack_dog",
    "config/units/scout_vehicle.tres": "scout_vehicle",
    "config/units/assault_vehicle.tres": "assault_vehicle",
    "config/units/main_battle_tank.tres": "main_battle_tank",
    "config/units/artillery_vehicle.tres": "artillery_vehicle",
    "config/units/harvester.tres": "harvester",
    "config/buildings/command_hq.tres": "command_hq",
    "config/buildings/power_plant.tres": "power_plant",
    "config/buildings/refinery.tres": "refinery",
    "config/buildings/barracks.tres": "barracks",
    "config/buildings/war_factory.tres": "war_factory",
    "config/buildings/radar_center.tres": "radar_center",
    "config/buildings/tech_center.tres": "tech_center",
    "config/buildings/forward_post.tres": "forward_post",
    "config/buildings/mg_tower.tres": "mg_tower",
    "config/buildings/at_turret.tres": "at_turret",
    "config/buildings/wall.tres": "wall",
    "config/buildings/gate.tres": "gate",
    "config/buildings/comms_outpost.tres": "comms_outpost",
    "config/buildings/comms_relay.tres": "comms_outpost",
    "config/buildings/repair_depot.tres": "repair_depot",
    "config/buildings/supply_depot.tres": "supply_depot",
    "config/buildings/civilian_structure.tres": "civilian_structure",
}


def wire(rel_path, model_id):
    path = os.path.join(ROOT, rel_path)
    with open(path) as handle:
        text = handle.read()

    model_path = "res://assets/models/%s.glb" % model_id
    if model_path in text:
        return "already wired"

    ids = [int(m) for m in re.findall(r'\[ext_resource [^\]]*id="(\d+)"', text)]
    new_id = (max(ids) + 1) if ids else 1

    ext_line = '[ext_resource type="PackedScene" path="%s" id="%d"]\n' % (model_path, new_id)
    last_ext = list(re.finditer(r'\[ext_resource [^\]]*\]\n', text))
    if last_ext:
        end = last_ext[-1].end()
        text = text[:end] + ext_line + text[end:]
    else:
        header_end = text.index("\n") + 1
        text = text[:header_end] + "\n" + ext_line + text[header_end:]

    if "visual_scene" in text:
        text = re.sub(r'visual_scene = .*\n', 'visual_scene = ExtResource("%d")\n' % new_id, text)
    else:
        text = text.rstrip("\n") + '\nvisual_scene = ExtResource("%d")\n' % new_id

    # load_steps must cover every ext_resource plus the resource itself.
    count = len(re.findall(r'\[ext_resource ', text)) + 1
    text = re.sub(r'load_steps=\d+', "load_steps=%d" % count, text, count=1)
    if "load_steps=" not in text.split("\n")[0]:
        text = text.replace("[gd_resource ", "[gd_resource load_steps=%d " % count, 1)

    with open(path, "w") as handle:
        handle.write(text)
    return "wired -> %s" % model_id


if __name__ == "__main__":
    for rel_path, model_id in sorted(MAPPING.items()):
        print("%-44s %s" % (rel_path, wire(rel_path, model_id)))
