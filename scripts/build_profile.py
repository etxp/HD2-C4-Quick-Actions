"""Build the diagnostic test package: the Off runtime plus timers and counters.

The instrumentation is injected into the assembled entry; src/ is not changed.
It writes C4QuickActionsProfile.log every 30 seconds: reads per update, time
per section, snapshot-cache decisions and the guarded bytes that changed.
Not a public release and not installed anywhere by this script.
"""
import argparse, hashlib, json, re, struct, sys, zipfile
from pathlib import Path
from assemble import ROOT, VERSION, assemble

GUID = 'b0aa8e22-956d-4c7d-973c-937085f9c0d8'
MODULES = ('ContextReader', 'RoutingReader', 'ActionReader', 'ReloadReader', 'AvatarScope')
CALLS = ('read(', 'ptr(', 'lookup(', 'global(', 'component(', 'index(', 'resource_count(', 'extension', 'avatar_scope(')

def replace_once(text, old, new):
    assert text.count(old) == 1, (old, text.count(old))
    return text.replace(old, new)

def instrument(text):
    core = (ROOT / 'profile/core.lua').read_text()
    hooks = (ROOT / 'profile/hooks.lua').read_text()
    text = replace_once(text, 'local R,D\n', 'local R,D\n' + core)
    text = replace_once(text,
        'if guard then guards[#guards+1]={at=at,bytes=b};guarded_bytes=guarded_bytes+n else reusable=false end',
        'if guard then local g={at=at,bytes=b};guards[#guards+1]=g;guarded_bytes=guarded_bytes+n;'
        'if P.labeling then P.label(g) end else reusable=false end')
    text = replace_once(text, "local existing = rawget(_G, 'HD2C4BoundaryProbe')",
                        hooks + "local existing = rawget(_G, 'HD2C4BoundaryProbe')")
    text = replace_once(text, '    ReadMemo(api)\n', '    ReadMemo(api);P.wrap_api(api)\n')
    text = replace_once(text, 'local ok,why=pcall(after_update)\n        action_backend.end_phase()\n',
        "local __t=P.now();local ok,why=pcall(after_update)\n"
        "        action_backend.end_phase();P.add('total.after_update',__t);P.frame(M)\n")
    text = replace_once(text, 'local success,err=pcall(tick,dt)\n        action_backend.end_phase()\n',
        "local __t=P.now();local success,err=pcall(tick,dt)\n"
        "        action_backend.end_phase();P.add('total.before_update',__t)\n")
    lines = text.split('\n')
    marker = next(i for i, line in enumerate(lines, 1) if '@@LINE@@' in line)
    module, source = None, {}
    for number, line in enumerate(lines, 1):
        match = re.match(r'local (\w+)=\(function\(\)', line)
        if match: module = match[1]
        if line.startswith('local existing = rawget'): module = None
        if module in MODULES and any(call in line for call in CALLS):
            stripped = ' '.join(line.split()).encode('ascii', 'replace').decode()
            source[number] = module + ': ' + stripped[:110]
    table = '{' + ','.join('[%d]=%s' % (n, json.dumps(s)) for n, s in sorted(source.items())) + '}'
    text = text.replace('@@LINE@@', str(marker)).replace('@@SOURCE@@', table)
    assert '@@' not in text
    return text

def build():
    assemble()
    out = ROOT / 'private/build/profile'
    out.mkdir(parents=True, exist_ok=True)
    for name in ('c4_quick_actions.lua', 'c4_quick_actions.off.lua'):
        (out / name).write_text(instrument((ROOT / 'private/build' / name).read_text()))
    return out

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--loader', type=Path, help='BingusSharedLoader checkout; omit to build the entries only')
    args = parser.parse_args()
    out = build()
    print(out)
    if not args.loader: return
    helper = args.loader.resolve()
    lock = json.loads((ROOT / 'dependencies.lock.json').read_text())['loader']
    for name, digest in lock['files'].items():
        assert hashlib.sha256((helper / name).read_bytes()).hexdigest() == digest, 'Unverified helper: ' + name
    sys.path.insert(0, str(helper / 'scripts'))
    from archive import make_archive, resource_hash, ARCHIVE
    from build_addon import entry_source
    manifest = {'Version': 1, 'Guid': GUID, 'Name': 'HD2 C4 Quick Actions ' + VERSION + ' profile',
        'Description': 'Diagnostic test build of C4 Quick Actions ' + VERSION + '. Same gameplay; additionally writes '
                       'timing and read statistics to C4QuickActionsProfile.log every 30 seconds. '
                       'Requires Mod Bindings Menu v2 and Bingus Shared Loader v17+.',
        'IconPath': None}
    entries = {'manifest.json': (json.dumps(manifest, ensure_ascii=False, indent=2) + '\n').encode(),
               'README.txt': (ROOT / 'profile/INSTALL-PROFILE.txt').read_bytes(),
               'LICENSE.txt': (ROOT / 'LICENSE').read_bytes()}
    body = entry_source('mods/etxp/c4_quick_actions', (out / 'c4_quick_actions.lua').read_bytes())
    payloads = [(ARCHIVE, 'mods/etxp/c4_quick_actions', body),
                (ARCHIVE[:-1] + '1', 'mods/etxp/c4_quick_actions_catalog', (ROOT / 'private/build/c4_catalog.lua').read_bytes()),
                (ARCHIVE[:-1] + '2', 'mods/etxp/c4_quick_actions_config', (ROOT / 'private/build/c4_config.off.lua').read_bytes())]
    names = []
    for name, key, value in payloads:
        entries[name] = make_archive({resource_hash(key): struct.pack('<II', len(value), 2) + value})
        names.append(name)
        for suffix in ('.stream', '.gpu_resources'):
            entries[name + suffix] = b''; names.append(name + suffix)
    target = ROOT / 'dist' / ('HD2-C4-Quick-Actions-' + VERSION + '-profile.zip')
    target.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, (1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            z.writestr(info, data)
    with zipfile.ZipFile(target) as z:
        assert z.testzip() is None and {n: z.read(n) for n in z.namelist()} == entries
    (ROOT / 'evidence').mkdir(exist_ok=True)
    (ROOT / 'evidence/profile-package.json').write_text(json.dumps(dict(
        version=VERSION, kind='diagnostic test build', package=str(target.relative_to(ROOT)),
        sha256=hashlib.sha256(target.read_bytes()).hexdigest(), manifest=manifest,
        payloads={n: hashlib.sha256(entries[n]).hexdigest() for n in names},
        live_gameplay_verified=False), indent=2, ensure_ascii=False) + '\n')
    print(target)

if __name__ == '__main__':
    main()
