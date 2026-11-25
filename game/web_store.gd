## Web build only: keeps the settings files in the browser dependably.
##
## In a browser Godot's user:// lives in memory and is copied to the browser's
## IndexedDB storage shortly after a file is written; a tab closed or reloaded
## right after a save can miss that copy, and some private modes have no
## IndexedDB. So after every save the file's text is also put in the page's
## localStorage (synchronous: it is there the moment the save returns), and
## before a load that copy is written back to user:// when there is one. Both
## fail quietly when the browser offers neither. Nothing happens on desktop.
class_name WebStore
extends RefCounted

const KEY_PREFIX: String = "ascii-racer:"


static func _key(path: String) -> String:
	return KEY_PREFIX + path.get_file()


## Call after writing `path` (a user:// file).
static func saved(path: String) -> void:
	if not OS.has_feature("web"):
		return
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		return
	JavaScriptBridge.eval("try { localStorage.setItem(%s, %s); } catch (e) {}" % [JSON.stringify(_key(path)), JSON.stringify(text)], true)


## Call before reading `path`: restores it from the browser's copy, if any.
static func restore(path: String) -> void:
	if not OS.has_feature("web"):
		return
	var v: Variant = JavaScriptBridge.eval("(function () { try { return localStorage.getItem(%s); } catch (e) { return null; } })()" % JSON.stringify(_key(path)), true)
	if v == null or not v is String or (v as String) == "":
		return
	if FileAccess.file_exists(path) and FileAccess.get_file_as_string(path) == v:
		return
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(v)
		f.close()
