class_name SkillData
extends Resource
## One thing a level can buy you.
##
## A Custom Resource for the same reason `EnemyData` and `ItemData` are: adding
## a skill should be a `.tres` in the inspector, not a class.
##
## **Skills write stats under their own source id**, exactly as buildings and
## worn gear do (`StatsComponent`). That is what keeps GDD §15 A7's rule alive
## through this change — every number on the character sheet can still name the
## thing that granted it, so a skill being refunded removes precisely what it
## added and nothing else.

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## Shown in the tree. The tree is read by shape before it is read by hovering,
## so this is not decoration — it is what makes a branch legible without
## pointing at every node in it.
@export var icon: Texture2D

## Points this costs. Kept at 1 for now: a tree where everything costs one point
## is a tree about *choosing*, and a tree with prices is a tree about saving up.
@export_range(1, 5) var cost: int = 1

## Another skill's id, or empty. One prerequisite rather than a list — a graph
## with multiple prerequisites is a graph the player cannot read off the screen.
@export var requires: StringName = &""

## Which column it sits in. Three branches, so the choice is legible: what you
## swing, what you can take, and how long you last.
@export_enum("Blade", "Body", "Wind") var branch: int = 0

## What taking it does, as {stat: delta} against `StatsComponent`'s named stats.
@export var modifiers: Dictionary = {}


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty() and not modifiers.is_empty()


static func branch_name(which: int) -> String:
	match which:
		1: return "Body"
		2: return "Wind"
		_: return "Blade"
