"""Assemble the editable 1.1 modules, with no native compilation or process access."""
import hashlib
import copy
import json
from pathlib import Path
import re
from lua_packaging import strip_comments

ROOT = Path(__file__).resolve().parents[1]
VERSION = '1.1'

def delivery_catalog(original):
    """Canonicalize ignored pattern bytes; matching and runtime reads are unchanged.

    NativeResolver compares only bytes whose mask is FF. Relative addresses are
    decoded from the loaded module, never from these masked-out capture bytes.
    Zeroes improve ordinary ZIP compression without weakening any verification.
    """
    catalog = copy.deepcopy(original)
    for node in catalog['nodes']:
        raw, mask = bytes.fromhex(node['hex']), bytes.fromhex(node['mask'])
        assert len(raw) == len(mask) and set(mask) <= {0, 255}
        node['hex'] = bytes(a & b for a, b in zip(raw, mask)).hex()
    return catalog

def lua(value):
    if value is None: return 'nil'
    if isinstance(value, bool): return 'true' if value else 'false'
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, str): return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list): return '{' + ','.join(map(lua, value)) + '}'
    return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in sorted(value.items())) + '}'

def assemble():
    text = (ROOT / 'src/entry.lua.in').read_text()
    def module(match):
        name = match[1]
        return 'local ' + name + '=(function()\n' + (ROOT / 'src' / (name + '.lua')).read_text() + '\nend)()'
    text = re.sub(r'@@MODULE:(\w+)@@', module, text)
    catalog = delivery_catalog(json.loads((ROOT / 'src/native_catalog.json').read_text()))
    text = text.replace('@@CATALOG@@', "local Catalog=require('mods/etxp/c4_quick_actions_catalog')\n"
                        "assert(Catalog.version=='@@VERSION@@','c4_catalog_version_mismatch')\nlocal NativeCatalog=Catalog.native")
    contact_catalog = delivery_catalog(json.loads((ROOT / 'src/contact_catalog.json').read_text()))
    text = text.replace('@@CONTACT_CATALOG@@', 'local ContactCatalog=Catalog.contact')
    text = text.replace('@@VERSION@@', VERSION)
    assert '@@' not in text
    target = ROOT / 'private/build/c4_quick_actions.lua'
    target.parent.mkdir(parents=True, exist_ok=True)
    (target.parent / 'c4_catalog.lua').write_text('return '+lua(dict(
        version=VERSION, native=catalog, contact=contact_catalog))+'\n')
    target.with_suffix('.annotated.lua').write_text(text)
    target.write_text(strip_comments(text))
    (target.parent / 'native_catalog.lua').write_text('return ' + lua(catalog) + '\n')
    (target.parent / 'contact_catalog.lua').write_text('return ' + lua(contact_catalog) + '\n')
    # Export the very same module bodies for the native-memory test fixtures.
    support = ROOT / 'private/tests/modules'
    support.mkdir(parents=True, exist_ok=True)
    for name in ('ContextReader', 'ActionReader', 'AvatarScope'):
        prefix = 'return function(R,D)\nlocal AvatarFlags=dofile("src/AvatarFlags.lua")\n'
        if name == 'ActionReader':
            prefix += 'local AvatarScope=dofile("private/tests/modules/avatar_scope.lua")(R,D)\n'
            prefix += 'local ReloadReader=(function()\n'+(ROOT/'src/ReloadReader.lua').read_text()+'\nend)()\n'
        filename = re.sub(r'(?<!^)(?=[A-Z])', '_', name).lower()
        (support / (filename + '.lua')).write_text(prefix + (ROOT / 'src' / (name + '.lua')).read_text() + '\nend\n')
    return target

if __name__ == '__main__':
    print(assemble())
