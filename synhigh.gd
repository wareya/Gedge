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
    kword_regex.compile("\\b(inline|const|static|volatile|if|else|elif|elseif|while|for|do|switch|case|match|goto|break|continue|public|private|protected|friend|extends|inherits|in|of|to|from|return|def|func|fn|lambda)\\b")
    kword_regex2.compile("\\b(typedef|void|nullptr_t|size_t|usize_t|char|short|int|long|unsigned|signed|float|double|struct|class|(ui|i)nt(8|16|24|32|48|64)_t|[ui](8|16|32|64)|f(32|64)|auto|bool|_Bool|var|let)\\b")
    kword_regex3.compile("(#include|#define|#ifdef|#if|#elif|#else|#endif|#undef)\\b")

var lines_info = {}
func _get_line_syntax_highlighting(line : int):
    ensure_editor()
    #process_lines(0, editor.get_line_count())
    waitfor()
    process_lines(line, line+1)
    return lines_info[line]

var waiting = false
func waitfor():
    if !waiting:
        waiting = true
        var start = Time.get_ticks_msec()
        await Engine.get_main_loop().process_frame
        var end = Time.get_ticks_msec()
        prints("time to highlight (ms):", str(end-start))
        #in_block_comment_until = ""
        waiting = false

func str_to_set(str : String):
    var ret = {}
    for c in str:
        ret[c] = null
    return ret

const varlike_str := "qwertyuiopasdfghjklzxcvbnm_QWERTYUIOPASDFGHJKLZXCVBNM"
var varlike = str_to_set(varlike_str)
const digits_str := "1234567890."
var digits = str_to_set(digits_str)
const digits_internal_str := "1234567890.xb_'abcdefABCDEFiu"
var digits_internal = str_to_set(digits_internal_str)
const brackets_str := "{}[]()<>\"\"''``"
var brackets = str_to_set(brackets_str)
const symbols_str := "~!@#$%^&*_+-=|\\:;,.?/"
var symbols = str_to_set(symbols_str)

var cache := {}
var ends_in_block_comment := {}
func process_lines(start : int, end : int):
    var in_block_comment_until := ""
    if start-1 in ends_in_block_comment:
        in_block_comment_until = ends_in_block_comment[start-1]
    if cache.size() > editor.get_line_count() * 8:
        cache = {}
    for j in range(start, end):
        if j > start:
            ends_in_block_comment[j-1] = in_block_comment_until
        
        var key := editor.get_line(j).md5_text() + in_block_comment_until
        if key in cache:
            lines_info[j] = cache[key][0]
            in_block_comment_until = cache[key][1]
            continue
        
        var text := editor.get_line(j)
        var ret := {}
        
        var instr := ""
        var instresc := false
        var innum := false
        var suppress_num := false
        
        var rm1 := kword_regex.search_all(text)
        var rm1set := {}
        for rm in rm1: rm1set[rm.get_start()] = rm.get_end()
        
        var rm2 := kword_regex2.search_all(text)
        var rm2set := {}
        for rm in rm2: rm2set[rm.get_start()] = rm.get_end()
        
        var rm3 := kword_regex3.search_all(text)
        var rm3set := {}
        for rm in rm3: rm3set[rm.get_start()] = rm.get_end()
        
        ret[0] = {"color" : Color.WHITE}
        
        if in_block_comment_until != "":
            ret[0] = {"color" : Color.DARK_OLIVE_GREEN}
        
        var i := 0
        while i < text.length():
            var skip_inc := false
            
            if in_block_comment_until != "":
                if text.find(in_block_comment_until, i) == i:
                    i += in_block_comment_until.length()
                    in_block_comment_until = ""
                    ret[i] = {"color" : Color.WHITE}
                    continue
                else:
                    i += 1
                    continue
            
            if instr == "":
                var next := false
                for k in line_comments:
                    if text.find(k, i) == i:
                        ret[i] = {"color" : Color.DARK_OLIVE_GREEN}
                        lines_info[j] = ret
                        cache[key] = [ret, in_block_comment_until]
                        i = text.length()
                        next = true
                        break
                for k in block_comments:
                    if text.find(k, i) == i:
                        ret[i] = {"color" : Color.DARK_OLIVE_GREEN}
                        in_block_comment_until = block_comments[k]
                        i += k.length()
                        next = true
                        break
                if next:
                    continue
            
            if instr != "":
                if text[i] == "\\":
                    instresc = true
                    i += 1
                    continue
            
            if instresc:
                instresc = false
                i += 1
                continue
            
            if text[i] == '"' or text[i] == "'":
                suppress_num = false
                innum = false
                if instr: instr = ""
                else: instr = text[i]
                if instr:
                    ret[i] = {"color" : Color.KHAKI}
                else:
                    ret[i+1] = {"color" : Color.WHITE}
                    instresc = false
            elif instr == "":
                if !innum and !suppress_num and text[i] in digits:
                    innum = true
                    ret[i] = {"color" : Color(0.65,0.5,1.0)}
                elif innum and !suppress_num and text[i] in digits_internal:
                    pass
                else:
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
        
        lines_info[j] = ret
        cache[key] = [ret, in_block_comment_until]
    
    ends_in_block_comment[end-1] = in_block_comment_until
