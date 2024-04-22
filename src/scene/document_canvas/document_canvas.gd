#============================================================
#    Document Canvas
#============================================================
# - author: zhangxuetu
# - datetime: 2024-04-22 10:52:13
# - version: 4.3.0.dev5
#============================================================
extends Control


signal selected(line_item: LineItem)


@export var margin : Rect2 = Rect2(8, 0, 8, 0)

@onready var text_edit : TextEdit = %TextEdit


var file_path : String = ""
var origin_lines : Array = []
var line_offset_point : float = 0
var line_items : Array[LineItem] = []
var p_to_item : Dictionary = {} # 点击的位置对应的行字符串

var _selected_pos : Vector2 = Vector2()
var _selected_line_item : LineItem = null


#============================================================
#  内置
#============================================================
func _ready():
	resized.connect(text_edit.hide)


func _draw():
	line_offset_point = 0
	var width = get_width()
	
	# 顶部文字
	var top_item_left = LineItem.new("2024/04/22  11:35:00", {
		font_color = Config.accent_color,
		font_size = Config.top_font_size,
		alignment = HORIZONTAL_ALIGNMENT_LEFT,
	})
	top_item_left.draw_to(self, margin, width)
	var top_item_right = LineItem.new("共 xxx 个文字", {
		font_color = Config.accent_color,
		font_size = Config.top_font_size,
		alignment = HORIZONTAL_ALIGNMENT_RIGHT,
	})
	top_item_right.draw_to(self, margin, width)
	line_offset_point += top_item_left.get_total_height( -1 ) + 2
	
	# 顶部分割线
	draw_line(Vector2(0, line_offset_point), Vector2(size.x, line_offset_point), Config.accent_color, 1)
	line_offset_point += 3
	draw_line(Vector2(0, line_offset_point), Vector2(size.x, line_offset_point), Config.accent_color, 1)
	
	# 更新内容
	_draw_lines()


func _gui_input(event):
	if InputUtil.is_click_left(event, false):
		text_edit.visible = false
		
		# 查找并处理这个位置上的 item
		_selected_pos = get_local_mouse_position()
		await Engine.get_main_loop().process_frame
		for idx in line_items.size() - 1:
			var item : LineItem = line_items[idx]
			var next_item : LineItem = line_items[idx + 1]
			if _selected_pos.y >= item.line_y_point and _selected_pos.y < next_item.line_y_point:
				_selected_line_item = item
				_select_line(_selected_line_item)
				queue_redraw()
				break


#============================================================
#  自定义
#============================================================
func get_width() -> float:
	return size.x - margin.position.x - margin.size.x


# 绘制位置向下偏移
func _line_point_offset(item: LineItem, width: float):
	line_offset_point += item.get_total_height(width)


## 打开绘制的文件
func open_file(path: String) -> void:
	LineItem.reset_line()
	file_path = path
	origin_lines = FileUtil.read_as_lines(path)
	line_items.clear()
	
	# 处理每行
	match file_path.get_extension().to_lower():
		"md":
			for line in origin_lines:
				var item = LineItem.new(line)
				item.handle_md()
				line_items.append( item )
		
		_:
			for line in origin_lines:
				line_items.append( LineItem.new(line) )
	
	queue_redraw()


# 绘制每行内容
func _draw_lines():
	p_to_item.clear()
	var width = get_width()
	for item in line_items:
		draw_line_item(item, width)


## 绘制这个行
func draw_line_item(item: LineItem, width : float):
	# 配置数据
	item.line_y_point = line_offset_point
	p_to_item[item.line_y_point] = item
	
	# 开始绘制
	item.draw_to(self, margin, width)
	# 向下偏移
	_line_point_offset(item, get_width())


# 选中行
func _select_line(item: LineItem):
	text_edit.visible = true
	text_edit.size = Vector2(get_width() + 18, 0)
	text_edit.text = item.origin_text.substr(0, item.origin_text.length())
	text_edit.size.y = item.get_total_height(get_width())
	text_edit.position = Vector2(0, item.line_y_point)
	
	text_edit.add_theme_font_size_override("font_size", item.font_size)
	text_edit.add_theme_font_override("font", item.font)
	
	text_edit.grab_focus()
	var v = text_edit.get_line_column_at_pos( text_edit.get_local_mouse_pos() , false)
	text_edit.set_caret_column(v.x)
	
	self.selected.emit(item)
	


# 插入行
func _insert_line(idx: int) -> LineItem:
	var new_line_item = LineItem.new("")
	var last_item = line_items[idx]
	new_line_item.line_y_point = last_item.line_y_point
	line_items.insert(idx, new_line_item)
	origin_lines.insert(idx, new_line_item.text)
	return new_line_item


# 更新这个行的内容
func _update_line_by_text_edit(line_item: LineItem):
	if line_item.origin_text != text_edit.text:
		var last_height = line_item.get_total_height(get_width())
		# 设置内容
		line_item.origin_text = text_edit.text
		if file_path.get_extension().to_lower() == "md":
			line_item.handle_md()
		var height = line_item.get_total_height(get_width())
		if last_height != height:
			_update_line_after_pos( line_items.find(line_item), height - last_height)
		queue_redraw()
	
	text_edit.visible = false


# 更新这个索引的行之后的位置偏移 
func _update_line_after_pos(item_idx: int, offset: float):
	for i in range(item_idx + 1, line_items.size()):
		line_items[i].line_y_point += offset
	queue_redraw()



#============================================================
#  连接信号
#============================================================
func _on_text_edit_visibility_changed():
	if text_edit and not text_edit.visible:
		if _selected_line_item:
			_update_line_by_text_edit(_selected_line_item)


func _on_text_edit_gui_input(event):
	if event is InputEventKey:
		if InputUtil.is_key(event, KEY_ENTER):
			_update_line_by_text_edit(_selected_line_item)
			get_tree().root.set_input_as_handled()
			text_edit.visible = false
			
			if not Input.is_key_pressed(KEY_CTRL) and _selected_line_item:
				# 插入新的行
				var new_idx : int = line_items.find(_selected_line_item) + 1
				var new_line_item : LineItem = _insert_line(new_idx)
				
				# 更新后面行的偏移
				var offset : float = new_line_item.get_font_height()
				_update_line_after_pos(new_idx, offset)
				
				# 选中这个行
				await Engine.get_main_loop().process_frame
				_selected_line_item = new_line_item
				_select_line(new_line_item)


func _on_text_edit_resized():
	pass # Replace with function body.
