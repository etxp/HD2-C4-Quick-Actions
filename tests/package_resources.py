"""Inspect the two delivered game resources, including Lua require semantics."""
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


def check(root, z, version, helper):
    sys.path.insert(0, str(helper/'scripts'))
    from archive import ARCHIVE, TYPE, resource_hash
    from build_addon import entry_source
    expected = {
        ARCHIVE: ('mods/etxp/c4_boundary_probe', entry_source('mods/etxp/c4_boundary_probe',
                  (root/'private/build/c4_quick_actions.lua').read_bytes())),
        ARCHIVE[:-1]+'1': ('mods/etxp/c4_quick_actions_catalog',
                  (root/'private/build/c4_catalog.lua').read_bytes())}
    for name, (resource, body) in expected.items():
        raw = z.read('Core/'+name)
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
            assert z.read('Core/'+name+suffix)==b''
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
    return dict(resources=len(expected),sidecars=4,version=version,explicit_require=True,
                mod_version_mismatch_rejected=True,plaintext_utf8=True)
