extends Control

@onready var hot_exit := $"../HotDB"

@export var stale_check_ms := 5000.0
@export var stale_check_round_robin := 1000.0

@export var version_check_ms := 1000.0

@onready var tree : Tree = $EditorArea/Tree
@onready var editors : TabContainer = $EditorArea/Center/Editors
@onready var menu : MenuBar = $MenuList/MenuBar

@onready var dummy_ := func(): randomize(); return null
# this shoooouuuuld be awful enough to be invalid on every OS?
var dummy_name_prefix := "UNTITLED%\n://:////:\r"
func get_new_dummy_name():
    return dummy_name_prefix + String.num_uint64(randi(), 64)

func file_open_pretty_please(fname, mode) -> FileAccess:
    # on some OSs, like windows, file access can fail spuriously
    # for no reason and simply require an immediate retry
    var f = FileAccess.open(fname, mode)
    for _i in 5:
        if f:
            break
        OS.delay_usec(250)
        f = FileAccess.open(fname, mode)
    return f

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

func ask_close(editor : CodeEdit, fname : String):
    current_ts_update(fname)
    force_dirty_update(editor, fname)
    var idx := editor.get_index()
    if editors.get_tab_button_icon(idx) != null:
        if !await confirm_dialog("File has not been saved or has been changed externally. Close anyway?\n\nAny unsaved data will be lost.", "Unsaved Data Warning"):
            return
    do_close(editor, fname)
    
func do_close(editor : CodeEdit, fname : String):
    hot_exit.unregister_editor(editor)
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
                ask_close(editors.get_child(idx), fname)

@onready var ctrl_mask = KEY_MASK_META if OS.get_name() in ["macOS", "iOS"] else KEY_MASK_CTRL

func _notification(what):
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        dirty_update_all()
        # TODO: implement hot exit
        if false and any_is_dirty():
            if !await confirm_dialog("At least one file has not been saved, or has been changed externally. Close anyway?\n\nAny unsaved data will be lost.", "Unsaved Data Warning"):
                return
        get_tree().quit()
        
func _ready() -> void:
    get_tree().set_auto_accept_quit(false)
    
    var dir := DirAccess.open("txt")
    var data := get_dir_contents(dir)
    var root : TreeItem = tree.create_item(null)
    add_items_to_tree(tree, root, data)
    
    tree.item_activated.connect(open_selected_tree_item)
    
    var m_file := menu.get_node("File") as PopupMenu
    m_file.set_item_accelerator(0, KEY_O | ctrl_mask)
    m_file.set_item_accelerator(1, KEY_S | ctrl_mask)
    m_file.set_item_accelerator(2, KEY_S | KEY_MASK_SHIFT | ctrl_mask)
    m_file.index_pressed.connect(m_file_pressed)
    
    var m_edit := menu.get_node("Edit") as PopupMenu
    m_edit.set_item_accelerator(0, KEY_Z | ctrl_mask)
    m_edit.set_item_accelerator(1, KEY_Z | KEY_MASK_SHIFT | ctrl_mask)
    m_edit.index_pressed.connect(m_edit_pressed)
    
    get_tree().root.files_dropped.connect(drop_files)

func drop_files(a):
    for _f in a:
        var f := _f as String
        print(f)
        f = f.replace("\\", "\\.\\")
        f = f.replace("/", "/./")
        do_open(f)

var open_files = {}
var open_files_is_crlf = {}
var open_file_hashes = {}
var open_file_modtimes = {}
var open_file_modtimes_temp = {}
var open_file_version_num = {}

func init_buffer(s : String, fname : String, ftime, no_db_insert : bool = false):
    print("starting to init buffer...")
    var justfile := fname.get_file()
    
    var start = Time.get_ticks_msec()
    var editor := preload("res://CodeEditor.tscn").instantiate()
    editor.visible = false
    editor.use_parent_material = true
    editor.text_changed.connect(buffer_updated.bind(editor))
    var end = Time.get_ticks_msec()
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
    
    var old = editors.get_tab_control(editors.current_tab)
    if old:
        old.hide()
    
    start = Time.get_ticks_msec()
    editors.set_tab_title(idx, justfile)
    end = Time.get_ticks_msec()
    prints("title set time (ms):", str(end-start))
    start = Time.get_ticks_msec()
    editors.set_tab_metadata(idx, fname)
    end = Time.get_ticks_msec()
    prints("metadata set time (ms):", str(end-start))
    start = Time.get_ticks_msec()
    editors.set_tab_icon(idx, preload("res://text.png"))
    end = Time.get_ticks_msec()
    prints("icon set time (ms):", str(end-start))
    
    start = Time.get_ticks_msec()
    open_files[fname] = editor
    open_file_modtimes[fname] = ftime
    open_file_modtimes_temp[fname] = ftime
    open_file_version_num[fname] = editor.get_version()
    end = Time.get_ticks_msec()
    prints("dict update time (ms):", str(end-start))
    
    start = Time.get_ticks_msec()
    open_files_is_crlf[fname] = s.get_slice_count("\n") == s.get_slice_count("\r\n")
    end = Time.get_ticks_msec()
    prints("dict update time (is_crlf) (ms):", str(end-start))
    
    start = Time.get_ticks_msec()
    open_file_hashes[fname] = s.md5_text()
    end = Time.get_ticks_msec()
    prints("md5 time (ms):", str(end-start))
    
    if s.length() > 10000:
        print("adding loading text?")
        editor.text = "<Loading....>"
        if s.length() > 1000000:
            editor.wrap_mode = TextEdit.LINE_WRAPPING_NONE
            editor.autowrap_mode = TextServer.AUTOWRAP_OFF
            editor.text = "<Loading.... NOTE: Very large file detected. Disabling word wrapping. Editing will still work!>"
        if !no_db_insert:
            editor.show()
        editor.clear_undo_history()
        await Engine.get_main_loop().process_frame
        await Engine.get_main_loop().process_frame
    
    start = Time.get_ticks_msec()
    editor.text = s
    s = ""
    editor.clear_undo_history()
    end = Time.get_ticks_msec()
    prints("text assign time (ms):", str(end-start))
    
    start = Time.get_ticks_msec()
    if !no_db_insert:
        editor.show()
    end = Time.get_ticks_msec()
    prints("show time (ms):", str(end-start))
    
    editor.lines_edited_from.connect(on_lines_edited_from)
    
    if !no_db_insert:
        hot_exit.register_editor(editor)

func do_open(fname : String, no_db_insert : bool = false):
    if fname.is_relative_path():
        fname = DirAccess.open(".").get_current_dir() + "/" + fname
    
    # forcibly canonicalize filename
    if fname and FileAccess.file_exists(fname):
        var f := file_open_pretty_please(fname, FileAccess.READ)
        if !f:
            OS.alert("File may not exist", "Failed to open file")
            return
        fname = f.get_path_absolute()
        f.close()
    
    if fname in open_files:
        if !no_db_insert:
            open_files[fname].show()
    elif fname and FileAccess.file_exists(fname):
        var start = Time.get_ticks_msec()
        var f := file_open_pretty_please(fname, FileAccess.READ)
        if !f:
            OS.alert("File may not exist", "Failed to open file")
            return
        var s = f.get_as_text()
        var ftime = FileAccess.get_modified_time(fname)
        f.close()
        var end = Time.get_ticks_msec()
        prints("file read time (ms):", str(end-start))
        
        init_buffer(s, fname, ftime, no_db_insert)

func trigger_open():
    var diag := FileDialog.new()
    diag.use_native_dialog = true
    diag.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    diag.file_selected.connect(do_open)
    diag.show()

func trigger_saveas():
    var diag := FileDialog.new()
    diag.use_native_dialog = true
    diag.file_mode = FileDialog.FILE_MODE_SAVE_FILE
    var editor = editors.get_tab_control(editors.current_tab)
    diag.file_selected.connect(func (f): do_save(f, editor))
    diag.show()

func trigger_save():
    var fname = editors.get_tab_metadata(editors.current_tab)
    var editor = editors.get_tab_control(editors.current_tab)
    
    do_save(fname, editor)

class MultiHandler extends RefCounted:
    signal fired
    var connections = []
    func _connect(sig : Signal):
        var f = fire.bind(sig)
        connections.push_back([sig, f])
        sig.connect(f)
    func fire(sig):
        for c in connections:
            (c[0] as Signal).disconnect(c[1])
        connections = []
        fired.emit(sig)
    static func first(array : Array):
        var ret = MultiHandler.new()
        for c in array:
            ret._connect(c)
        return ret

func confirm_dialog(text : String, title : String):
    var d := ConfirmationDialog.new()
    d.force_native = true
    d.title = title
    d.dialog_text = text
    d.dialog_autowrap = true
    Engine.get_main_loop().root.add_child(d)
    d.popup_centered()
    d.show()
    var which = await MultiHandler.first([d.confirmed, d.canceled]).fired
    return which == d.confirmed

func do_save(fname : String, editor : CodeEdit):
    var idx := editor.get_index()
    var text := recover_editor_text(editor)
    var text_md5 := text.md5_text()
    
    open_file_modtimes_temp[fname] = FileAccess.get_modified_time(fname)
    last_ts_check_process = Time.get_ticks_msec()
    
    if fname in open_file_modtimes and open_file_modtimes[fname] != open_file_modtimes_temp[fname] \
        and open_file_hashes[fname] != text_md5:
        editors.set_tab_button_icon(idx, preload("res://outdated.png"))
        if !await confirm_dialog("File has been modified externally. Save anyway?", "Save Warning"):
            return
    elif fname in open_file_modtimes and open_file_modtimes[fname] != open_file_modtimes_temp[fname]:
        editors.set_tab_button_icon(idx, preload("res://outdated_but_saved.png"))
        if !await confirm_dialog("File has been modified externally. Save anyway?", "Save Warning"):
            return
    elif fname in open_file_hashes and open_file_hashes[fname] == text_md5:
        return
    
    var temp_fname = fname + ".~temp~"
    var i := 0
    while FileAccess.file_exists(temp_fname) and i < 10:
        temp_fname += "~"
        i += 1
    if FileAccess.file_exists(temp_fname):
        OS.alert("Temporary file already exists", "Saving Failed")
        return
    
    var f := file_open_pretty_please(temp_fname, FileAccess.WRITE_READ)
    if !f:
        OS.alert("Failed to open file for writing", "Saving Failed")
        return
    f.store_string(text)
    f.flush()
    f.flush()
    f.flush()
    f.close()
    
    var hash1 := text.md5_text()
    text = ""
    
    f = file_open_pretty_please(temp_fname, FileAccess.READ)
    if !f:
        OS.alert("Failed to reopen file to verify correct saving", "Saving Failed")
        return
    var text2 = f.get_as_text()
    f.close()
    
    if text2.md5_text() != hash1:
        OS.alert("File corrupt on save", "Saving Failed")
        return
    
    var e : Error = DirAccess.rename_absolute(temp_fname, fname)
    if e:
        OS.alert("Failed to swap temp files (" + var_to_str(e) + ")", "Saving Failed")
        return
    
    var ftime = FileAccess.get_modified_time(fname)
    
    var old_fname_maybe = editors.get_tab_metadata(idx)
    open_file_modtimes.erase(old_fname_maybe)
    open_file_modtimes_temp.erase(old_fname_maybe)
    open_file_hashes.erase(old_fname_maybe)
    open_files_is_crlf.erase(old_fname_maybe)
    open_files.erase(old_fname_maybe)
    
    open_file_modtimes[fname] = ftime
    open_file_modtimes_temp[fname] = ftime
    open_file_hashes[fname] = text2.md5_text()
    open_files_is_crlf[fname] = text2.count("\n") == text2.count("\r\n")
    open_files[fname] = editor
    
    var justfile := fname.get_file()
    editors.set_tab_title(idx, justfile)
    editors.set_tab_button_icon(idx, null)
    editors.set_tab_metadata(idx, fname)

func m_file_pressed(index : int):
    if index == 0:
        trigger_open()
    elif index == 1:
        trigger_save()
    elif index == 2:
        trigger_saveas()

func m_edit_pressed(index : int):
    if editors.current_tab < 0:
        return
    if index == 0:
        (editors.get_tab_control(editors.current_tab) as CodeEdit).undo()
    elif index == 1:
        (editors.get_tab_control(editors.current_tab) as CodeEdit).redo()

func recover_editor_text(editor : CodeEdit) -> String:
    if open_files_is_crlf[editors.get_tab_metadata(editor.get_index())]:
        return editor.text.replace("\n", "\r\n")
    else:
        return editor.text
func get_editor_md5(editor : CodeEdit) -> String:
    if open_files_is_crlf[editors.get_tab_metadata(editor.get_index())]:
        return editor.text.replace("\n", "\r\n").md5_text()
    else:
        return editor.text.md5_text()

func current_ts_update(fname : String):
    if FileAccess.file_exists(fname):
        open_file_modtimes_temp[fname] = FileAccess.get_modified_time(fname)
        last_ts_check = Time.get_ticks_msec()

func force_dirty_update(editor : CodeEdit, fname : String):
    var idx := editor.get_index()
    if abs(last_ts_check - Time.get_ticks_msec()) > stale_check_ms:
        current_ts_update(fname)
    
    var start = Time.get_ticks_msec()
    var text_md5 := get_editor_md5(editor)
    
    if open_file_modtimes[fname] != open_file_modtimes_temp[fname] \
        and open_file_hashes[fname] != text_md5:
        editors.set_tab_button_icon(idx, preload("res://outdated.png"))
    elif open_file_modtimes[fname] != open_file_modtimes_temp[fname]:
        editors.set_tab_button_icon(idx, preload("res://outdated_but_saved.png"))
    elif open_file_hashes[fname] != text_md5:
        editors.set_tab_button_icon(idx, preload("res://unsaved.png"))
    else:
        editors.set_tab_button_icon(idx, null)
    var end = Time.get_ticks_msec()
    prints("dirty check time (ms):", str(end-start))

func dirty_update_all():
    for fname in open_files:
        current_ts_update(fname)
        force_dirty_update(open_files[fname], fname)

func any_is_dirty():
    for i in editors.get_tab_count():
        if editors.get_tab_button_icon(i) != null:
            return true
    return false

var last_ts_check = Time.get_ticks_msec()
func buffer_updated(editor : CodeEdit):
    var idx := editor.get_index()
    var ts_differ = false
    var fname = editors.get_tab_metadata(idx)
    if fname == "":
        editors.set_tab_button_icon(idx, preload("res://unsaved.png"))
    else:
        if abs(last_ts_check - Time.get_ticks_msec()) > stale_check_ms:
            current_ts_update(fname)
        
        force_dirty_update(editor, fname)

func open_selected_tree_item():
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

var last_ts_check_process = Time.get_ticks_msec()
var f := 0
var t := 0.0

var potentially_dirty_lines = {}
func on_lines_edited_from(from : int, to : int):
    for i in range(from, to+1):
        potentially_dirty_lines[i] = null
    #var editor = editors.get_tab_control(editors.current_tab)
    #print(var_to_str(editor))
    #print(Engine.get_frames_drawn())

func force_check_updated(editor : CodeEdit, fname : String):
    open_file_modtimes_temp[fname] = FileAccess.get_modified_time(fname)
    
    var text_md5 := get_editor_md5(editor)
    
    #prints("checking", fname)
    
    if open_file_modtimes[fname] != open_file_modtimes_temp[fname] \
        and open_file_hashes[fname] != text_md5:
        editors.set_tab_button_icon(editor.get_index(), preload("res://outdated.png"))
    elif open_file_modtimes[fname] != open_file_modtimes_temp[fname]:
        editors.set_tab_button_icon(editor.get_index(), preload("res://outdated_but_saved.png"))
    elif open_file_hashes[fname] != text_md5:
        #prints("think", fname, "is modified...")
        editors.set_tab_button_icon(editor.get_index(), preload("res://unsaved.png"))
    else:
        editors.set_tab_button_icon(editor.get_index(), null)

var last_version_check = Time.get_ticks_msec()

var last_rr_ts_check = Time.get_ticks_msec()
var rr_ts_index := 0
var prev_timestamp = Time.get_ticks_msec()
func _process(delta: float) -> void:
    if Engine.is_editor_hint():
        return
    
    f += 1
    t += delta
    if t > 5.0:
        $"../Label".text = str(round(f/t*100)/100)
        t = 0.0
        f = 0
    
    var timestamp = Time.get_ticks_msec()
    if timestamp - prev_timestamp > 100:
        prints("took", (timestamp - prev_timestamp)/1000.0, "seconds between frames")
    prev_timestamp = timestamp
    
    last_rr_ts_check += delta
    if last_rr_ts_check * 1000.0 > stale_check_round_robin and editors.get_tab_count() > 0:
        last_rr_ts_check = 0.0
        rr_ts_index = (rr_ts_index + 1) % editors.get_tab_count()
        var fname = editors.get_tab_metadata(rr_ts_index)
        if FileAccess.file_exists(fname):
            force_check_updated(editors.get_tab_control(rr_ts_index), fname)
    
    if any_window_has_focus():
        since_input += delta
        if since_input > 2.0:
            OS.low_processor_usage_mode_sleep_usec = 20000 # check for state updates at a rate of at most 50hz
        else:
            OS.low_processor_usage_mode_sleep_usec = 4000 # 250hz
    else:
        since_input += delta
        if since_input > 2.0:
            OS.low_processor_usage_mode_sleep_usec = 200000 # 5hz
        else:
            OS.low_processor_usage_mode_sleep_usec = 20000 # 50hz
    
    %CRLF.text = ""
    $EditorArea/Center/StatusBar.visible = false
    if editors.current_tab >= 0 and editors.current_tab < editors.get_tab_count():
        $EditorArea/Center/StatusBar.visible = true
        var fname = editors.get_tab_metadata(editors.current_tab)
        var editor : CodeEdit = editors.get_tab_control(editors.current_tab)
        
        if fname in open_files_is_crlf and open_files_is_crlf[fname]:
             %CRLF.text = "CRLF"
        else:
             %CRLF.text = "LF"
        
        %RowCol.text = str(str(editor.get_caret_line()) + ":" + str(editor.get_caret_column()))
        
        last_version_check += delta
        if last_version_check * 1000.0 > version_check_ms:
            last_version_check = 0.0
            if open_file_version_num[fname] != editor.get_version():
                open_file_version_num[fname] = editor.get_version()
                prints("new version", editor.get_version())
                hot_exit.update_editor(editor)
        
        if abs(last_ts_check_process - Time.get_ticks_msec()) > stale_check_ms:
            current_ts_update(fname)
            
            var text_md5 := get_editor_md5(editor)
            
            if open_file_modtimes[fname] != open_file_modtimes_temp[fname] \
                and open_file_hashes[fname] != text_md5:
                editors.set_tab_button_icon(editors.current_tab, preload("res://outdated.png"))
            elif open_file_modtimes[fname] != open_file_modtimes_temp[fname]:
                editors.set_tab_button_icon(editors.current_tab, preload("res://outdated_but_saved.png"))
