class_name QuestStep
extends Resource
## One thing a quest asks you to do.
##
## Four kinds and no scripting language. A quest system general enough to
## express anything is one nobody can read six months later, and the honest
## observation is that this game's loop is *go out, gather, come back* — so the
## kinds are the four verbs that loop already has, and a fifth is a deliberate
## decision rather than a config value.

enum Kind {
	## Have `count` of `target` on you. A material or an item; `Quests` checks
	## both collections, because a player asked to bring back timber does not
	## care which bag the game keeps it in.
	##
	## **Checked against what you are holding, not what you have ever picked
	## up.** Selling the timber you were asked to fetch un-completes the step,
	## which is correct: she wants the timber, not your word that you had some.
	GATHER,
	## Kill `count` of the enemy whose `EnemyData.id` is `target`. Cumulative —
	## a kill counts once and cannot be un-killed.
	SLAY,
	## Reach `node` in `target`'s conversation. This is "go and speak to the
	## smith", and it is how a quest sends you somewhere without inventing a
	## trigger volume.
	TALK,
	## `target` is a rebuild project and it is finished. See `Village`.
	BUILD,
}

@export var kind: Kind = Kind.GATHER

## What the step is about: a material id, an item id, an enemy id, a dialogue
## id, or a project id, depending on `kind`.
@export var target: StringName = &""

## Only for TALK: which node of that conversation counts as having spoken.
@export var node: String = ""

@export_range(1, 999) var count: int = 1

## Overrides the generated line in the journal. Left empty for anything whose
## generated text is already the truth — "Bring 8 timber" needs no author, and
## an authored copy of it is one more thing to fall out of step with `count`.
@export var text: String = ""
