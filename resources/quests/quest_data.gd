class_name QuestData
extends Resource
## One job somebody has asked you to do.
##
## A Resource for the same reason `ItemData` and `SkillData` are: a second quest
## should be a `.tres` in the inspector rather than a class.
##
## ## You come back to a person
##
## Meeting every objective does not finish a quest — it makes it *ready*, and
## finishing it means going back to whoever asked. That is one extra walk, and
## it buys the thing this game is actually about: the payoff for a job is a
## conversation with the person who wanted it done, rather than a toast sliding
## in over the top of the screen while you stand in a field.
##
## It also means the dialogue system is the quest UI. `Quests` needs no "hand
## in" button anywhere, because handing in is a reply.

@export var id: StringName = &""
@export var title: String = ""

## Who gives it and who it is returned to — a dialogue id. One person for both:
## a quest you take from one character and return to another is a good trick and
## a bad default, and when it is wanted it is a `TALK` step.
@export var giver: StringName = &""

## Shown in the journal under the title. Her words, not a description of the
## mechanics — the steps below already say what to do.
@export_multiline var summary: String = ""

## What has to happen. Checked in order for display, but not gated in order:
## anything you can do early, you may.
@export var steps: Array[QuestStep] = []

@export_group("Reward")
@export_range(0, 9999) var gold: int = 0
@export_range(0, 9999) var experience: int = 0
## Handed over on turn-in. Refused rather than dropped if the pack is full, so
## a reward cannot evaporate — see `Quests.turn_in`.
@export var items: Array[ItemData] = []

@export_group("Repeat")
## Whether it can be taken again after being finished.
##
## **The one Maren offers is repeatable**, and that is what makes her arrangement
## an arrangement rather than an errand: the carters are not coming back, so the
## job does not end. A quest that can be finished forever is a quest that stops
## being a reason to visit.
@export var repeatable: bool = false


func is_valid() -> bool:
	return id != &"" and not title.is_empty() and not steps.is_empty()
