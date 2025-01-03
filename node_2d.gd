@tool
extends Control

@onready var tree := $EditorArea/Tree
@onready var editors := $EditorArea/Editors
@onready var menu := $MenuList/MenuBar

func get_dir_contents(dir : DirAccess) -> Dictionary:
    var ret := {}
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if dir.current_is_dir():
                var dir2 = DirAccess.open(dir.get_current_dir() + "/" + file_name)
                ret[file_name] = get_dir_contents(dir2)
            else:
                ret[file_name] = dir.get_current_dir() + "/" + file_name
            file_name = dir.get_next()
    return ret

func add_items_to_tree(tree : Tree, parent : TreeItem, dict : Dictionary):
    for k in dict:
        var item = tree.create_item(parent)
        item.set_text(0, k)
        if dict[k] is String:
            item.set_metadata(0, dict[k])
        else:
            add_items_to_tree(tree, item, dict[k])

var delete_idx := -1
var since_input := 0.0
func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        pass
    elif event is InputEventJoypadButton:
        pass
    else:
        since_input = 0.0
    
    if event is InputEventMouseButton:
        var tb := editors.get_tab_bar() as TabBar
        if event.button_index == 3 and event.is_pressed():
            delete_idx = tb.get_tab_idx_at_point(tb.get_local_mouse_position())
        if event.button_index == 3 and event.is_released():
            var idx = tb.get_tab_idx_at_point(tb.get_local_mouse_position())
            if idx >= 0 and idx == delete_idx:
                var fname = editors.get_tab_metadata(idx)
                open_files.erase(fname)
                open_file_hashes.erase(fname)
                editors.remove_child(editors.get_child(idx))
        pass

func _ready() -> void:
    var dir := DirAccess.open("txt")
    var data := get_dir_contents(dir)
    var root : TreeItem = tree.create_item(null)
    add_items_to_tree(tree, root, data)
    
    tree.item_activated.connect(open_selected)
    editors.tab_button_pressed
    
    #var s := Shortcut.new()
    #var e := InputEventKey.new()
    #e.key_label = KEY_F
    #e.alt_pressed = true
    #s.events.append(e)
    #(menu.get_node("File") as PopupMenu).set_item_shortcut(0, s)
    
    #(menu.get_node("File") as PopupMenu).set_item_accelerator(0, KEY_F | KEY_MASK_ALT)

var open_files = {}
var open_file_hashes = {}

func buffer_updated(editor : CodeEdit):
    print(editor.get_version())
    var idx := editor.get_index()
    if open_file_hashes[editors.get_tab_metadata(idx)] != editor.text.md5_text():
        editors.set_tab_button_icon(idx, preload("res://unsaved.png"))
    else:
        editors.set_tab_button_icon(idx, null)

func open_selected():
    var n : TreeItem = tree.get_selected()
    if !n:
        return
    var _fname = n.get_metadata(0)
    if not _fname is String:
        return
    var fname : String = _fname as String
    if fname in open_files:
        open_files[fname].show()
    elif fname and FileAccess.file_exists(fname):
        var f := FileAccess.open(fname, FileAccess.READ)
        var s = f.get_as_text()
        f.close()
        var editor := preload("res://CodeEditor.tscn").instantiate()
        editor.text = s
        editor.clear_undo_history()
        editors.add_child(editor)
        editors.set_tab_title(editor.get_index(), fname.get_file())
        editors.set_tab_metadata(editor.get_index(), fname)
        editors.set_tab_icon(editor.get_index(), preload("res://text.png"))
        #editors.set_tab_button_icon(editor.get_index(), preload("res://close.png"))
        editor.syntax_highlighter = editor.syntax_highlighter.duplicate()
        
        editor.show()
        
        editor.use_parent_material = true
        editor.text_changed.connect(buffer_updated.bind(editor))
        
        open_files[fname] = editor
        open_file_hashes[fname] = s.md5_text()

var dt := 0.1
func _process(delta: float) -> void:
    if get_window().has_focus():
        since_input += delta
        if since_input > 0.5:
            OS.low_processor_usage_mode_sleep_usec = 40000 # check for state updates at a rate of at most 25hz
        else:
            OS.low_processor_usage_mode_sleep_usec = 4000 # 250hz
    else:
        OS.low_processor_usage_mode_sleep_usec = 200000 # 5hz
    
    pass

