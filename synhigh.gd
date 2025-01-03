@tool
extends CodeHighlighter

var editor : TextEdit = null

func ensure_editor():
    editor = get_text_edit()

@export var line_comments := {
    "//":null,
    #"#":null,
    #"--":null,
    #";":null,
}

@export var block_comments := {
    "/*":"*/",
}

var kword_regex := RegEx.new()
var kword_regex2 := RegEx.new()
var kword_regex3 := RegEx.new()

func _init() -> void:
    kword_regex.compile("\\b(inline|const|static|volatile|if|else|elif|elseif|while|for|do|switch|case|match|goto|break|continue|public|private|protected|friend|extends|inherits|in|of|to|from|return)\\b")
    kword_regex2.compile("\\b(typedef|void|nullptr_t|size_t|usize_t|char|short|int|long|unsigned|signed|float|double|struct|class|(ui|i)nt(8|16|24|32|48|64)_t|[ui](8|16|32|64)|f(32|64)|auto|bool|_Bool|var|let)\\b")
    kword_regex3.compile("(#include|#define|#ifdef|#if|#elif|#else|#endif|#undef)\\b")

func _get_line_syntax_highlighting(line : int):
    ensure_editor()
    var text : String = editor.get_line(line)
    var ret := {}
    
    #var name_regex := RegEx.create_from_string("[a-zA-Z_][a-zA-Z_0-9]*")
    const varlike := "qwertyuiopasdfghjklzxcvbnm_QWERTYUIOPASDFGHJKLZXCVBNM"
    const digits := "1234567890."
    const digits_internal := "1234567890.xb_'abcdefABCDEFiu"
    const brackets := "{}[]()<>\"'`"
    const symbols := "~!@#$%^&*_+-=|\\:;,.?/"
    
    
    var instr := ""
    var instresc := false
    var innum := false
    var suppress_num := false
    
    var rm1 := kword_regex.search_all(text)
    var rm1set = {}
    for rm in rm1: rm1set[rm.get_start()] = rm.get_end()
    
    var rm2 := kword_regex2.search_all(text)
    var rm2set = {}
    for rm in rm2: rm2set[rm.get_start()] = rm.get_end()
    
    var rm3 := kword_regex3.search_all(text)
    var rm3set = {}
    for rm in rm3: rm3set[rm.get_start()] = rm.get_end()
    
    ret[0] = {"color" : Color.WHITE}
    
    var i = 0
    while i < text.length():
        var skip_inc := false
        
        if instr == "":
            for k in line_comments:
                if text.find(k) == i:
                    ret[i] = {"color" : Color.DARK_OLIVE_GREEN}
                    return ret
        
        if instr != "":
            if text[i] == "\\":
                instresc = true
                i += 1
                continue
        
        if instresc:
            instresc = false
            i += 1
            continue
        
        if text[i] in ['"', "'"]:
            suppress_num = false
            innum = false
            if instr: instr = ""
            else: instr = text[i]
            if instr:
                ret[i] = {"color" : Color.KHAKI}
            else:
                ret[i+1] = {"color" : Color.WHITE}
                instresc = false
        elif instr == "" and !suppress_num and text[i] in digits and !innum:
            innum = true
            ret[i] = {"color" : Color(0.65,0.5,1.0)}
        elif instr == "" and !suppress_num and text[i] in digits_internal and innum:
            pass
        elif instr == "":
            if innum:
                innum = false
                ret[i] = {"color" : Color.WHITE}
            
            if text[i] in varlike:
                suppress_num = true
            elif not text[i] in digits:
                suppress_num = false
            
            if i in rm1set and rm1set[i] >= 0:
                ret[i] = {"color" : Color.LIGHT_SKY_BLUE.lerp(Color.CORNFLOWER_BLUE, 0.5)}
                i = rm1set[i]
                ret[i] = {"color" : Color.WHITE}
                skip_inc = true
            
            if i in rm2set and rm2set[i] >= 0:
                ret[i] = {"color" : Color.LIGHT_SKY_BLUE.lerp(Color.CORNFLOWER_BLUE, 0.5)}
                i = rm2set[i]
                ret[i] = {"color" : Color.WHITE}
                skip_inc = true
            
            if i in rm3set and rm3set[i] >= 0:
                ret[i] = {"color" : Color.LIGHT_CORAL}
                i = rm3set[i]
                ret[i] = {"color" : Color.WHITE}
                skip_inc = true
            
            if !skip_inc and (text[i] in symbols or text[i] in brackets):
                ret[i] = {"color" : Color(0.8,0.9,1.0)}
                ret[i+1] = {"color" : Color.WHITE}
            
        if !skip_inc:
            i += 1
    
    #print(ret)
    return ret
