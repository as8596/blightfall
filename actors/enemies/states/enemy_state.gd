class_name EnemyState
extends State
## Shared behaviour for enemy states.

var enemy: BaseEnemy:
	get:
		return actor as BaseEnemy

var data: EnemyData:
	get:
		return (actor as BaseEnemy).data


## Whether a hit interrupts this state.
##
## Everything staggers except the lunge. An enemy that can be stunlocked out of
## its own telegraph never gets to attack under pressure, and an enemy that
## can't be staggered at all makes hitting it feel like hitting a wall. The
## committed attack is the one place the player has to dodge instead of
## out-damaging (GDD §5, enemy rule 1: every enemy telegraphs).
func can_be_staggered() -> bool:
	return true
