"""Collect the offline measurements of this build into docs/performance-summary.json."""
import json
from pathlib import Path
from assemble import ROOT, VERSION

def load(name):
    path = ROOT / 'evidence' / name
    return json.loads(path.read_text()) if path.exists() else None

def medians(report):
    if not report: return None
    out = {}
    for case, row in report['medians'].items():
        out[case] = {variant: {key: round(value, 4) for key, value in row[variant].items()}
                     for variant in ('release_1_12', 'lean_1', 'candidate')}
        out[case]['candidate_vs_release_1_12_percent'] = {k: round(v, 1) for k, v in row['change_percent'].items()}
        out[case]['candidate_vs_lean_1_percent'] = {k: round(v, 1) for k, v in row['change_vs_lean_1_percent'].items()}
    return out

def main():
    c, wine = load('comparison-c.json'), load('comparison-wine.json')
    differential, soak, checks = load('differential.json'), load('soak.json'), load('checks.json')
    summary = {
        'version': VERSION,
        'variants': {
            'release_1_12': 'preserved formal 1.12 Off runtime (optimization/1.12 build; src identical to releases/1.12)',
            'lean_1': 'preserved 1.12-lean.1 Off runtime, the base of this build; profiled in the live game 2026-10-04',
            'candidate': 'this build; not run in the live game',
        },
        'method': {
            'statistic': 'median of three alternating-order trials, separate process per trial',
            'updates': '300 warmup, 600 counted with a read meter, 300 unmetered warmup, 600 timed without the meter',
            'configuration': 'Off diagnostics, JIT enabled, identical scenario scripts and complete backpack reload fixture',
            'linux_memory': 'compiled C store; a page holding fixture data is readable as a whole',
            'windows_memory': 'standalone Wine host, local game Lua DLL, real ReadProcessMemory on its own invented pages',
            'native_game_actions': 'mocked',
            'limitations': [
                'Synthetic whole-update time including fixture work; neither game FPS nor live addon self time.',
                'Page layout of the live process is not reproduced. Guards that share a page there decide the live read count.',
                'The harness mocks the engine window API, Mod Bindings Menu and the focus query; the live fixed cost is higher.',
                'c4_volatile is the every-update worst case; in the live profile of 1.12-lean.1 retained snapshots held outside actions.',
                'The idle fixtures do not initialise the optional Contact catalog; mode-label maintenance is measured by its own test.',
            ],
        },
        'linux_c_memory': medians(c),
        'wine_read_process_memory': medians(wine),
        'wine_runtime': wine and wine.get('runtime'),
        'differential': differential and {
            'sessions': differential['sessions'], 'updates_per_session': differential['ticks'],
            'identical_to': {name: entry['identical'] for name, entry in differential['baselines'].items()},
            'different': {name: len(entry['different']) for name, entry in differential['baselines'].items()},
            'activity': differential['activity'],
            'compared': 'every native call with arguments, every data write, Fire flags, Aim/Fire inhibition state '
                        'and call counts, reload calls and eligibility queries, mapping queries, lean calls, '
                        'vanilla Fire events and addon status, on every update',
        },
        'retained_heap_KiB': soak and soak['summary'],
        'offline_checks': checks and {'passed': checks['passed'], 'pass_lines': checks['checks']},
        'live_gameplay_verified': False,
        'live_performance_verified': False,
    }
    (ROOT / 'docs/performance-summary.json').write_text(json.dumps(summary, indent=2) + '\n')
    print(ROOT / 'docs/performance-summary.json')

if __name__ == '__main__':
    main()
