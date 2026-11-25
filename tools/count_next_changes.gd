extends SceneTree
## Flicker counter for playtest clip logs: NEXT_LOG=path -> prints "NEXT=<n>".
const NextCountdown := preload("res://scripts/next_countdown.gd")


func _init() -> void:
	var path := OS.get_environment("NEXT_LOG")
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("cannot open %s" % path)
		quit(2)
		return
	var texts: Array = []
	while not f.eof_reached():
		var line := f.get_line()
		var i := line.find("NEXT = ")
		if i >= 0:
			texts.append(line.substr(i + 7))
	print("NEXT=%d" % NextCountdown.count_changes(texts))
	quit(0)
