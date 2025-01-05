extends Node

var hot_db : SQLite = null
const db_fname := "user://gedge_hot_exit_state.db"
const table_name := "hot_exit_data"

@onready var editors : TabContainer = $"../Main/EditorArea/Center/Editors"
@onready var main := $"../Main"

func _ready():
    hot_db = SQLite.new()
    hot_db.verbosity_level = SQLite.NORMAL
    hot_db.path = db_fname
    hot_db.open_db()
    hot_db.create_table(table_name, {
        # for non-file buffers: synthetic. if synthetic, orig_md5 and mod_time should be ignored
        "fname" : {"data_type": "text", "not_null": true, "primary_key": true},
        "tabname" : {"data_type": "text", "not_null": true},
        
        # buffer data is only stored if the buffer is dirty
        # if false, text_gz buffer is empty and current_md5 should be ignored
        "is_dirty" : {"data_type": "int", "not_null": true},
        
        "text_gz" : {"data_type": "blob"},
        
        "undo_json_gz" : {"data_type": "blob"},
        "redo_json_gz" : {"data_type": "blob"},
        
        "current_md5" : {"data_type": "text"},
        "orig_md5" : {"data_type": "text"},
        "mod_time" : {"data_type": "int", "not_null": true},
        "is_crlf" : {"data_type": "int", "not_null": true},
        
        "tab_index" : {"data_type": "int", "not_null": true},
        "is_selected" : {"data_type": "int", "not_null": true},
        
        "caret_row" : {"data_type": "int", "not_null": true},
        "caret_col" : {"data_type": "int", "not_null": true},
        "scroll_row" : {"data_type": "float", "not_null": true},
    })
    
    var loaded : Array = hot_db.select_rows(table_name, "", ["*"])
    for d in loaded:
        main.do_open(d["fname"], true)
        var editor : TextEdit = main.open_files[d["fname"]]
        if d["is_dirty"]:
            var new_text = (d["text_gz"] as PackedByteArray).\
                decompress_dynamic(-1, FileAccess.COMPRESSION_DEFLATE).\
                get_string_from_utf8()
            if new_text != editor.text:
                editor.text = new_text
            main.force_check_updated(editor, d["fname"])
        editor.set_caret_line(d["caret_row"])
        editor.set_caret_column(d["caret_col"])
        editor.scroll_vertical = d["scroll_row"]
        if d["is_selected"] == 1:
            editor.show()

func editor_get_data(editor : TextEdit):
    var idx := editor.get_index()
    var fname : String = editors.get_tab_metadata(idx)
    
    var data = {}
    data["tabname"]        = editors.get_tab_title(idx)
    data["is_dirty"]       = 1 if editors.get_tab_button_icon(idx) != null else 0
    data["text_gz"]        = editor.text.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)\
                             if data["is_dirty"] else PackedByteArray()
    data["undo_json_gz"]   = PackedByteArray() # TODO
    data["redo_json_gz"]   = PackedByteArray() # TODO
    data["current_md5"]    = main.get_editor_md5(editor)
    data["orig_md5"]       = main.open_file_hashes[fname]
    data["mod_time"]       = main.open_file_modtimes[fname]
    data["is_crlf"]        = main.open_files_is_crlf[fname]
    data["tab_index"]      = idx
    data["is_selected"]    = 1 if editor.visible else 0
    data["caret_row"]      = editor.get_caret_line()
    data["caret_col"]      = editor.get_caret_column()
    data["scroll_row"]     = editor.scroll_vertical
    #print(data)
    return data

func register_editor(editor : TextEdit):
    var idx := editor.get_index()
    var fname : String = editors.get_tab_metadata(idx)
    hot_db.query("BEGIN TRANSACTION;")
    
    var query_core_a = ["fname"]
    var query_core_b = ["?"]
    var bindings = [fname]
    
    var insert = func(key, val):
        query_core_a[0] += "," + key
        query_core_b[0] += ",?"
        bindings.append(val)
    
    var data = editor_get_data(editor)
    for k in data:
        insert.call(k, data[k])
    
    var query = "INSERT INTO " + table_name + " (" + query_core_a[0] + " ) VALUES ( " + query_core_b[0] + ");"
    
    #print(query)
    #print(bindings)
    
    hot_db.query_with_bindings(query, bindings)
    
    var temp = hot_db.error_message
    hot_db.query("END TRANSACTION;")
    hot_db.error_message = temp

func update_editor(editor : TextEdit):
    var idx := editor.get_index()
    var fname : String = editors.get_tab_metadata(idx)
    hot_db.query("BEGIN TRANSACTION;")
    
    var query_core = ["fname = ?"]
    var bindings = [fname]
    
    var insert = func(key, val):
        query_core[0] += ", " + key + "=?"
        bindings.append(val)
    
    var data = editor_get_data(editor)
    for k in data:
        insert.call(k, data[k])
    
    var query = "UPDATE " + table_name + " SET " + query_core[0] + " WHERE fname = ?"
    
    hot_db.query_with_bindings(query, bindings + [fname])
    
    var temp = hot_db.error_message
    hot_db.query("END TRANSACTION;")
    hot_db.error_message = temp

func unregister_editor(editor : TextEdit):
    var fname = editors.get_tab_metadata(editor.get_index())
    var query = "DELETE FROM " + table_name + " WHERE fname=?;"
    hot_db.query_with_bindings(query, [fname])

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
    pass
