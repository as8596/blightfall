extends SceneTree
## Paints a blob of one terrain into a field of the other, so the autotiler's
## output can be looked at.
##
##     godot --headless --path . --script res://tools/paint_terrain_proof.gd
##     xvfb-run -a godot --path . tests/screenshot.tscn -- \
##         --scene=res://tests/proof_grass_dirt.tscn --frames=20 --shot=/tmp/t.png
##
## A tileset with wrong peering bits does not error — it just picks the wrong
## corner piece somewhere, and you find out much later. This is how you see it:
## a round blob and a straight column exercise every bit between them, and a
## misread one shows up immediately as a notch in an edge that should be smooth.
func _init() -> void:
	for pair in [["res://resources/tilesets/grass_dirt.tres", "grass_dirt"],
			["res://resources/tilesets/grass_water.tres", "grass_water"]]:
		var ts := load(pair[0]) as TileSet
		var root := Node2D.new()
		root.name = "TerrainProof"
		var layer := TileMapLayer.new()
		layer.name = "Ground"
		layer.tile_set = ts
		root.add_child(layer)
		layer.owner = root
		# Fill 20x11 with terrain 1, then carve a blob of terrain 0 through it.
		var base: Array[Vector2i] = []
		for y in 11:
			for x in 20:
				base.append(Vector2i(x, y))
		layer.set_cells_terrain_connect(base, 0, 1, false)
		var blob: Array[Vector2i] = []
		for y in range(2, 9):
			for x in range(3, 12):
				if Vector2(x - 7, (y - 5) * 1.6).length() < 4.2:
					blob.append(Vector2i(x, y))
		for y in range(1, 10):
			blob.append(Vector2i(14, y))
			blob.append(Vector2i(15, y))
		layer.set_cells_terrain_connect(blob, 0, 0, false)
		var packed := PackedScene.new()
		@warning_ignore("return_value_discarded")
		packed.pack(root)
		@warning_ignore("return_value_discarded")
		ResourceSaver.save(packed, "res://tests/proof_%s.tscn" % pair[1])
		print("painted proof_%s" % pair[1])
	quit()
