extends RefCounted
## Shared by the flicker counters: Next text with only its trailing air clock removed.
## "… · BUILD AIR IN 1:09" -> "… · BUILD AIR IN"; "… · BUILD AIR NOW · 0:59 LEFT" -> "… · BUILD AIR NOW · LEFT".
## Stage words stay, so a stage change still counts as a Next change; a clock-only tick does not.

static var _clock := RegEx.create_from_string(" \\d+:\\d\\d( LEFT)?$")


static func strip_clock(text: String) -> String:
	var m := _clock.search(text)
	if m == null:
		return text
	return text.substr(0, m.get_start()) + (" LEFT" if m.get_string(1) != "" else "")


## Count Next changes in a sequence of texts, ignoring clock-only ticks.
static func count_changes(texts: Array) -> int:
	var changes := 0
	var last = null
	for t in texts:
		var s := strip_clock(str(t))
		if s != last:
			changes += 1
			last = s
	return changes
