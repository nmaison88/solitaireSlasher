extends VBoxContainer
class_name SimpleCarousel

signal item_changed(index: int, item_text: String)

@export var items: Array[String] = []
@export var item_icons: Array[String] = []  # Paths to icon images
@export var orientation: String = "horizontal"  # "horizontal" or "vertical"
@export var current_index: int = 0
@export var use_icons: bool = false  # Whether to display icons instead of text

var label: Label
var icon_display: TextureRect
var prev_button: Button
var next_button: Button

func _ready():
	if orientation == "horizontal":
		_setup_horizontal()
	else:
		_setup_vertical()
	
	_update_display()

func _setup_horizontal():
	# Create HBoxContainer for horizontal layout
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(hbox)
	
	# Previous button (left arrow)
	prev_button = Button.new()
	prev_button.text = "<"
	prev_button.custom_minimum_size = Vector2(80, 80)
	prev_button.add_theme_font_size_override("font_size", 48)
	prev_button.pressed.connect(_on_prev_pressed)
	hbox.add_child(prev_button)
	
	if use_icons:
		# Icon display for images
		icon_display = TextureRect.new()
		icon_display.custom_minimum_size = Vector2(200, 200)
		icon_display.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon_display.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbox.add_child(icon_display)
	else:
		# Label to display current item text
		label = Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.custom_minimum_size = Vector2(400, 80)
		label.add_theme_font_size_override("font_size", 48)
		hbox.add_child(label)
	
	# Next button (right arrow)
	next_button = Button.new()
	next_button.text = ">"
	next_button.custom_minimum_size = Vector2(80, 80)
	next_button.add_theme_font_size_override("font_size", 48)
	next_button.pressed.connect(_on_next_pressed)
	hbox.add_child(next_button)

func _setup_vertical():
	# Previous button (up arrow)
	prev_button = Button.new()
	prev_button.text = "▲"
	prev_button.custom_minimum_size = Vector2(400, 60)
	prev_button.add_theme_font_size_override("font_size", 36)
	prev_button.pressed.connect(_on_prev_pressed)
	add_child(prev_button)
	
	# Label to display current item
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(400, 80)
	label.add_theme_font_size_override("font_size", 48)
	add_child(label)
	
	# Next button (down arrow)
	next_button = Button.new()
	next_button.text = "▼"
	next_button.custom_minimum_size = Vector2(400, 60)
	next_button.add_theme_font_size_override("font_size", 36)
	next_button.pressed.connect(_on_next_pressed)
	add_child(next_button)

func _on_prev_pressed():
	current_index = (current_index - 1 + items.size()) % items.size()
	_update_display()
	item_changed.emit(current_index, items[current_index])

func _on_next_pressed():
	current_index = (current_index + 1) % items.size()
	_update_display()
	item_changed.emit(current_index, items[current_index])

func _update_display():
	if items.size() > 0:
		if use_icons and icon_display and item_icons.size() > current_index:
			# Load and display icon
			var texture = load(item_icons[current_index])
			if texture:
				icon_display.texture = texture
		elif label:
			# Display text
			label.text = items[current_index]

func set_items(new_items: Array[String]):
	items = new_items
	current_index = 0
	_update_display()

func set_item_icons(new_icons: Array[String]):
	item_icons = new_icons
	_update_display()

func get_current_item() -> String:
	if items.size() > 0:
		return items[current_index]
	return ""

func get_current_index() -> int:
	return current_index
