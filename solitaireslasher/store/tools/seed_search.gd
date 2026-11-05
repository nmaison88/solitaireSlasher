extends Node
## Finds a Solitaire deal with lots of real moves early on, so the demo looks lively. Prints "SEED <n>".
func _ready() -> void:
	var best_seed := 1
	var best_score := -1
	for seed_value in range(1, 400):
		var game := Game.new()
		add_child(game)
		game.set_difficulty("Medium")
		game.new_game(seed_value)
		var score := 0
		var seen := {}
		for step in 16:
			var hint: Dictionary = game.get_hint()
			match hint.type:
				"tableau_to_foundation":
					game.move_to_foundation("tableau", hint.from, hint.to); score += 3
				"waste_to_foundation":
					game.move_to_foundation("waste", -1, hint.to); score += 3
				"waste_to_tableau":
					game.move_waste_to_tableau(hint.to); score += 2
				"tableau_to_tableau":
					var key := str(hint.from, ">", hint.to, "#", game.tableau[hint.from].size())
					var pointless: bool = hint.count == game.tableau[hint.from].size() and game.tableau[hint.to].is_empty()
					if seen.has(key) or pointless:
						game.draw_from_stock_3()
					else:
						seen[key] = true
						game.move_tableau_to_tableau(hint.from, hint.to, hint.count); score += 2
				_:
					game.draw_from_stock_3()
		if score > best_score:
			best_score = score
			best_seed = seed_value
		game.free()
	print("SEED ", best_seed, " score ", best_score)
	get_tree().quit()
