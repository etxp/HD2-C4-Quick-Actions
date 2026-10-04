"""Turn a C4QuickActionsProfile.log into the tables used in GitHub issue #1.

The issue counted calls to the addon's api.read per Lua update over foreground
intervals, by context. The diagnostic build counts the same thing per 30-second
window. Updates per second are Lua updates, not render FPS from a capture tool.
"""
import argparse, re, statistics
from pathlib import Path

CONTEXT = {'waiting_for_mission': 'ship / no mission', 'selected_weapon_observed': 'primary weapon',
           'c4_context_observed': 'C4'}

def parse(text):
    rows = []
    for report in re.split(r'(?m)^(?=== C4 profile)', text)[1:]:
        head = re.search(r'profile (\S+) report (\d+): ([\d.]+) s, (\d+) updates \(([\d.]+)/s\).*status (\S+)', report)
        reads = float(re.search(r'reads: ([\d.]+) per update', report).group(1))
        before = float(re.search(r'total\.before_update\s+[\d.]+\s+[\d.]+\s+([\d.]+)', report).group(1))
        after = float(re.search(r'total\.after_update\s+[\d.]+\s+[\d.]+\s+([\d.]+)', report).group(1))
        routing = report.split('cache routing')[1]
        contexts = {m.group(1): int(m.group(2)) for m in re.finditer(r'context ([\w/:]+): (\d+)', routing)}
        top = max(contexts, key=contexts.get)
        action = re.search(r'cache action: calls (\d+).*?kept (\d+), changed (\d+)', report)
        rebuilt = int(action.group(3)); checked = int(action.group(2)) + rebuilt
        context = CONTEXT.get(top, top)
        if top == 'c4_context_observed':
            context = 'C4, throw/detonate/reload' if checked and rebuilt / checked > 0.2 else 'C4, idle or moving'
        if contexts[top] < 0.95 * sum(contexts.values()): context += ' (mixed window)'
        rows.append(dict(version=head.group(1), report=int(head.group(2)), updates=int(head.group(4)),
                         rate=float(head.group(5)), status=head.group(6), reads=reads, us=before + after, context=context))
    return rows

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('log', type=Path)
    args = parser.parse_args()
    rows = parse(args.log.read_text())
    print('| window | context | Lua updates | reads per Lua update | addon time per update | status |')
    print('|---|---|---:|---:|---:|---|')
    for r in rows:
        print(f"| {r['report']} | {r['context']} | {r['updates']} | {r['reads']:.1f} | {r['us']:.0f} us | {r['status']} |")
    print()
    print('| context | windows | reads per Lua update (min / median / max) | Lua updates per second (min / median / max) |')
    print('|---|---:|---|---|')
    groups = {}
    for r in rows:
        if '(mixed window)' not in r['context'] and r['report'] > 1:
            groups.setdefault(r['context'], []).append(r)
    for context, items in groups.items():
        reads = [r['reads'] for r in items]; rate = [r['rate'] for r in items]
        print(f"| {context} | {len(items)} | {min(reads):.1f} / {statistics.median(reads):.1f} / {max(reads):.1f} | "
              f"{min(rate):.1f} / {statistics.median(rate):.1f} / {max(rate):.1f} |")

if __name__ == '__main__':
    main()
