class_name SkillBranch
extends Control
## The lines between the skills in one branch.
##
## A separate node purely so something owns a `_draw()`. The skill nodes
## themselves are real `Panel`s laid out on top of this and take their own
## clicks; all this does is join them up.
##
## **The line carries state too.** A join into a skill you have taken is lit; a
## join into one you could take now is half-lit; a join into something still out
## of reach is barely there. That is what makes a branch readable at a glance
## rather than node by node — you can see how far down you have got without
## reading a single word.

## [[from, to, skill_id], ...] in this control's local space. Set once by the
## menu after it has laid the nodes out; the geometry never changes after that,
## only the colours.
var links: Array = []

const TAKEN := Color(0.78, 0.66, 0.40, 0.95)
const OPEN := Color(0.52, 0.45, 0.31, 0.85)
const LOCKED := Color(0.26, 0.24, 0.21, 0.75)
const WIDTH := 3.0


func _draw() -> void:
	for link in links:
		var from: Vector2 = link[0]
		var to: Vector2 = link[1]
		var id: StringName = link[2]
		var colour := LOCKED
		if Skills.is_unlocked(id):
			colour = TAKEN
		elif Skills.can_unlock(id):
			colour = OPEN

		# Drawn as two segments through a shared elbow rather than as one
		# diagonal: a fork drawn diagonally is two lines crossing the gap at
		# different angles, and the eye reads that as a mess. Square joins read
		# as a diagram.
		var mid_y := (from.y + to.y) * 0.5
		draw_line(Vector2(from.x, from.y), Vector2(from.x, mid_y), colour, WIDTH)
		draw_line(Vector2(from.x, mid_y), Vector2(to.x, mid_y), colour, WIDTH)
		draw_line(Vector2(to.x, mid_y), Vector2(to.x, to.y), colour, WIDTH)
