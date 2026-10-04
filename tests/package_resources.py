"""Inspect all delivered game resources, including Lua require semantics."""
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def check(root, z, version, helper, folder=None):
    sys.path.insert(0, str(helper/'scripts'))
    from archive import ARCHIVE, TYPE, resource_hash
    from build_addon import entry_source
    expected = {
        ARCHIVE: ('mods/etxp/c4_quick_actions', entry_source('mods/etxp/c4_quick_actions',
                  (root/'private/build/c4_quick_actions.lua').read_bytes())),
        ARCHIVE[:-1]+'1': ('mods/etxp/c4_quick_actions_catalog',
                  (root/'private/build/c4_catalog.lua').read_bytes()),
        ARCHIVE[:-1]+'2': ('mods/etxp/c4_quick_actions_config',
                  (root/'private/build'/('c4_config.'+(folder.lower() if folder else 'off')+'.lua')).read_bytes())}
    for name, (resource, body) in expected.items():
        directory=folder if name.endswith('2') else 'Core'
        raw = z.read(directory+'/'+name if folder else name)
        assert struct.unpack_from('<III',raw)==(0xf0000011,1,1)
        fields=struct.unpack_from('<7Q6I',raw,104)
        key,kind,offset=fields[:3]
        assert key==resource_hash(resource) and kind==TYPE
        assert fields[7]==len(body)+8 and offset%16==0
        assert raw[offset:offset+8]==struct.pack('<II',len(body),2)
        assert raw[offset+8:offset+fields[7]]==body
        assert body.decode('utf-8') and b'\0' not in body
        assert bool(body.startswith(b'-- HD2-Addon:')) == (name==ARCHIVE)
        for suffix in ('.stream','.gpu_resources'):
            assert z.read(directory+'/'+name+suffix if folder else name+suffix)==b''
    main=expected[ARCHIVE][1].decode('utf-8')
    prefix=main[:main.index('local NativeCatalog=Catalog.native')]
    catalog=expected[ARCHIVE[:-1]+'1'][1].decode('utf-8')
    assert "require('mods/etxp/c4_quick_actions_catalog')" in prefix
    with tempfile.TemporaryDirectory(dir=root/'private/tests',prefix='catalog-load-') as d:
        script=Path(d)/'check.lua'
        script.write_text("package.preload['mods/etxp/c4_quick_actions_catalog']=function()\n"+catalog+
          "\nend\n"+prefix+"\nassert(Catalog.version=='"+version+"')\n"+
          "assert(#Catalog.contact.nodes==17 and #Catalog.native.nodes==85)\n"+
          "package.loaded['mods/etxp/c4_quick_actions_catalog'].version='mismatched-mod'\n"+
          "local ok,why=pcall(function()\n"+prefix+"\nend)\n"+
          "assert(not ok and tostring(why):find('c4_catalog_version_mismatch',1,true))\n")
        subprocess.run(['luajit',str(script)],check=True,timeout=10)
    main_config=main[main.index("local Config=require("):main.index('local M = {version=')]
    config=expected[ARCHIVE[:-1]+'2'][1].decode('utf-8')
    with tempfile.TemporaryDirectory(dir=root/'private/tests',prefix='config-load-') as d:
        script=Path(d)/'check.lua'
        script.write_text("local ContextReader={diagnostics=true}\n"+
            "package.preload['mods/etxp/c4_quick_actions_config']=function()\n"+config+
            "end\n"+main_config+"\nassert(diagnostics=='"+(folder.lower() if folder else 'off')+"')\n"+
            "assert(ContextReader.diagnostics==(diagnostics~='off'))\n"+
            "package.loaded['mods/etxp/c4_quick_actions_config'].version='wrong'\n"+
            "assert(not pcall(function()\n"+main_config+"\nend))\n")
        subprocess.run(['luajit',str(script)],check=True,timeout=10)
    return dict(resources=len(expected),sidecars=6,version=version,explicit_require=True,
                mod_version_mismatch_rejected=True,quiet_context_configured=True,plaintext_utf8=True)
