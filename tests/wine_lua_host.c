/* Private offline host: loads a local Lua DLL in this process only. */
#include <windows.h>
#include <stdio.h>
typedef struct lua_State lua_State;
typedef lua_State *(__cdecl *new_fn)(void);
typedef void (__cdecl *void_fn)(lua_State *);
typedef int (__cdecl *file_fn)(lua_State *, const char *);
typedef int (__cdecl *call_fn)(lua_State *, int, int, int);
typedef const char *(__cdecl *string_fn)(lua_State *, int, size_t *);
typedef void (__cdecl *table_fn)(lua_State *, int, int);
typedef void (__cdecl *push_fn)(lua_State *, const char *);
typedef void (__cdecl *seti_fn)(lua_State *, int, int);
typedef void (__cdecl *field_fn)(lua_State *, int, const char *);
#define FN(type,name) type name = (type)GetProcAddress(lib,#name); if (!name) return 3
int main(int argc, char **argv) {
    if (argc < 3) return 2;
    HMODULE lib = LoadLibraryA(argv[1]);
    if (!lib) { fprintf(stderr,"LoadLibrary error %u\n",(unsigned)GetLastError()); return 3; }
    FN(new_fn,luaL_newstate); FN(void_fn,luaL_openlibs); FN(file_fn,luaL_loadfile);
    FN(call_fn,lua_pcall); FN(string_fn,lua_tolstring); FN(void_fn,lua_close);
    FN(table_fn,lua_createtable); FN(push_fn,lua_pushstring);
    FN(seti_fn,lua_rawseti); FN(field_fn,lua_setfield);
    lua_State *L = luaL_newstate(); if (!L) return 4;
    luaL_openlibs(L); lua_createtable(L,argc-2,0);
    for (int i=2; i<argc; ++i) { lua_pushstring(L,argv[i]); lua_rawseti(L,-2,i-2); }
    lua_setfield(L,-10002,"arg");
    int status=luaL_loadfile(L,argv[2]);
    if (!status) status=lua_pcall(L,0,0,0);
    if (status) fprintf(stderr,"%s\n",lua_tolstring(L,-1,NULL));
    lua_close(L); FreeLibrary(lib); return status ? 1 : 0;
}
