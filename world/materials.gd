class_name Materials
extends RefCounted
## What the three haul materials are called, look like, and are worth.
##
## Materials are not `ItemData` and should not become it — `InventoryComponent`
## says why at length, and the short version is that the satchel is a counted
## currency with one axis and giving it a type system makes both collections
## illegible. But they are still *things with names and prices*, and until this
## existed those facts were scattered: the icons lived in `world/pickup.gd`, the
## display names were `String(id).capitalize()` in two different files, and the
## prices did not exist at all.
##
## One table, so adding a fourth material is one edit rather than four and a bug
## in whichever one got missed.

## Order matters — it is the order they are listed in every UI that shows them,
## and it runs cheap to dear, which is also roughly the order you find them.
const ORDER: Array[StringName] = [&"timber", &"stone", &"ironwork"]

const NAMES: Dictionary = {
	&"timber": "Timber",
	&"stone": "Stone",
	&"ironwork": "Ironwork",
}

const ICONS: Dictionary = {
	&"timber": preload("res://art/sprites/props/material_timber.png"),
	&"stone": preload("res://art/sprites/props/material_stone.png"),
	&"ironwork": preload("res://art/sprites/props/material_ironwork.png"),
}

## Gold per unit, before anybody's margin.
##
## Set against `Village.TIERS`, which is what materials are actually *for*: a
## trivial project is 4 timber and a high one is 16 timber, 14 stone and 6
## ironwork. At these prices that high project is worth about 350 gold, which is
## an order of magnitude more than a meal — and that ratio is the whole point.
## Selling your haul should feel like spending the house you were going to
## build, not like finding loose change.
##
## Ironwork is dear because it is the scarcest drop and the one two projects
## gate on.
const VALUES: Dictionary = {
	&"timber": 6,
	&"stone": 9,
	&"ironwork": 26,
}


static func name_of(id: StringName) -> String:
	return NAMES.get(id, String(id).capitalize())


static func icon_of(id: StringName) -> Texture2D:
	return ICONS.get(id)


static func value_of(id: StringName) -> int:
	return int(VALUES.get(id, 0))


static func known(id: StringName) -> bool:
	return VALUES.has(id)


## The ids in `contents`, in `ORDER`, skipping anything held at zero. Anything
## the table has never heard of is listed after the known ones rather than
## dropped — a material that exists in a save and not in this file is a bug, and
## hiding it from the one screen that would reveal it is not a fix.
static func sorted(contents: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in ORDER:
		if int(contents.get(id, 0)) > 0:
			out.append(id)
	for id in contents:
		var key := StringName(id)
		if int(contents[id]) > 0 and not ORDER.has(key):
			out.append(key)
	return out
