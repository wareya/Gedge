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

func do_close(editor : CodeEdit, fname : String):
    open_files.erase(fname)
    open_file_hashes.erase(fname)
    editors.remove_child(editor)

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
                do_close(editors.get_child(idx), fname)

@onready var ctrl_mask = KEY_MASK_META if OS.get_name() in ["macOS", "iOS"] else KEY_MASK_CTRL

func _ready() -> void:
    var dir := DirAccess.open("txt")
    var data := get_dir_contents(dir)
    var root : TreeItem = tree.create_item(null)
    add_items_to_tree(tree, root, data)
    
    tree.item_activated.connect(open_selected)
    
    var m_file := menu.get_node("File") as PopupMenu
    m_file.set_item_accelerator(0, KEY_O | ctrl_mask)
    m_file.set_item_accelerator(1, KEY_S | ctrl_mask)
    m_file.index_pressed.connect(m_file_pressed)

var open_files = {}
var open_file_hashes = {}
var open_file_modtimes = {}
var open_file_modtimes_temp = {}

func do_open(fname : String):
    var justfile := fname.get_file()
    if fname in open_files:
        open_files[fname].show()
    elif fname and FileAccess.file_exists(fname):
        var start = Time.get_ticks_msec()
        var f := FileAccess.open(fname, FileAccess.READ)
        var s = f.get_as_text()
        var ftime = FileAccess.get_modified_time(fname)
        f.close()
        var end = Time.get_ticks_msec()
        prints("file read time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        var editor := preload("res://CodeEditor.tscn").instantiate()
        editor.use_parent_material = true
        editor.text_changed.connect(buffer_updated.bind(editor))
        prints("child init time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        editor.syntax_highlighter = editor.syntax_highlighter.duplicate()
        end = Time.get_ticks_msec()
        prints("highlighter setup time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        editors.add_child(editor)
        var idx = editor.get_index()
        end = Time.get_ticks_msec()
        prints("add child time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        editors.set_tab_title(idx, justfile)
        editors.set_tab_metadata(idx, fname)
        editors.set_tab_icon(idx, preload("res://text.png"))
        open_files[fname] = editor
        open_file_modtimes[fname] = ftime
        open_file_modtimes_temp[fname] = ftime
        end = Time.get_ticks_msec()
        prints("other stuff time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        editor.text = s
        editor.clear_undo_history()
        end = Time.get_ticks_msec()
        prints("text assign time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        editor.show()
        end = Time.get_ticks_msec()
        prints("show time (ms):", str(end-start))
        
        start = Time.get_ticks_msec()
        open_file_hashes[fname] = s.md5_text()
        end = Time.get_ticks_msec()
        prints("md5 time (ms):", str(end-start))
        s = ""

func trigger_open():
    var diag := FileDialog.new()
    diag.use_native_dialog = true
    diag.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    diag.file_selected.connect(do_open)
    diag.show()
func trigger_save():
    pass

func m_file_pressed(index : int):
    if index == 0:
        trigger_open()
    elif index == 1:
        trigger_save()

var last_ts_check = Time.get_ticks_msec()
func buffer_updated(editor : CodeEdit):
    var idx := editor.get_index()
    var ts_differ = false
    var fname = editors.get_tab_metadata(idx)
    if fname == "":
        editors.set_tab_button_icon(idx, preload("res://unsaved.png"))
    else:
        if abs(last_ts_check - Time.get_ticks_usec()) > 5000:
            open_file_modtimes_temp[fname] = FileAccess.get_modified_time(fname)
            last_ts_check = Time.get_ticks_usec()
            
        var start = Time.get_ticks_msec()
        if open_file_modtimes[fname] != open_file_modtimes_temp[fname]:
            editors.set_tab_button_icon(idx, preload("res://unsaved.png"))
            warn_outdated(fname)
        elif open_file_hashes[fname] != editor.text.md5_text():
            editors.set_tab_button_icon(idx, preload("res://unsaved.png"))
        else:
            editors.set_tab_button_icon(idx, null)
        var end = Time.get_ticks_msec()
        prints("dirty check time (ms):", str(end-start))

func open_selected():
    var n : TreeItem = tree.get_selected()
    if !n:
        return
    var _fname = n.get_metadata(0)
    if not _fname is String:
        return
    var fname : String = _fname as String
    do_open(fname)

func any_window_has_focus():
    for window in DisplayServer.get_window_list():
        if DisplayServer.window_is_focused(window):
            return true
    return false

var dt := 0.1
var last_ts_check_process = Time.get_ticks_msec()
func _process(delta: float) -> void:
    if !Engine.is_editor_hint():
        if any_window_has_focus():
            since_input += delta
            if since_input > 2.0:
                OS.low_processor_usage_mode_sleep_usec = 40000 # check for state updates at a rate of at most 25hz
            else:
                OS.low_processor_usage_mode_sleep_usec = 4000 # 250hz
        else:
            since_input += delta
            if since_input > 2.0:
                OS.low_processor_usage_mode_sleep_usec = 200000 # 5hz
            else:
                OS.low_processor_usage_mode_sleep_usec = 20000 # 50hz
    
    if editors.current_tab >= 0:
        var fname = editors.get_tab_metadata(editors.current_tab)
        if abs(last_ts_check_process - Time.get_ticks_usec()) > 5000:
            open_file_modtimes_temp[fname] = FileAccess.get_modified_time(fname)
            last_ts_check_process = Time.get_ticks_usec()
            
            if open_file_modtimes[fname] != open_file_modtimes_temp[fname]:
                warn_outdated(fname)
                editors.set_tab_button_icon(editors.current_tab, preload("res://unsaved.png"))

func warn_outdated(fname : String):
    pass
