import ctypes, os, sys
lib = ctypes.CDLL(os.environ.get('OXCART_TEST_LUA_DLL', r'C:\Program Files\Cheat Engine\lua53-64.dll'))
lib.luaL_newstate.restype = ctypes.c_void_p
lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
lib.luaL_loadbufferx.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p, ctypes.c_char_p]
lib.lua_pcallk.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_longlong, ctypes.c_void_p]
lib.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.POINTER(ctypes.c_size_t)]
lib.lua_tolstring.restype = ctypes.c_char_p
lib.lua_close.argtypes = [ctypes.c_void_p]
source = sys.stdin.read().encode('utf-8')
vm = lib.luaL_newstate()
lib.luaL_openlibs(vm)
status = lib.luaL_loadbufferx(vm, source, len(source), b'validation', None)
if status == 0 and '--execute' in sys.argv:
    status = lib.lua_pcallk(vm, 0, 0, 0, 0, None)
if status:
    print(lib.lua_tolstring(vm, -1, None).decode('utf-8', errors='replace'))
else:
    print('Lua 5.3 validation passed')
lib.lua_close(vm)
sys.exit(1 if status else 0)
