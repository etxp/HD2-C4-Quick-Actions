#!/usr/bin/env python3
# Historical research entry point; see research/README.md.
import os
"""Run bounded offline checks; never reports these as in-game validation."""
import hashlib
import json
import subprocess
from pathlib import Path

ROOT = Path(os.environ.get('C4_RESEARCH_WORKSPACE',str(Path(__file__).resolve().parents[2])))


def main():
    result = subprocess.run(['luajit', 'tests/test_probe.lua'], cwd=ROOT,
                            text=True, capture_output=True)
    checks = [line[5:] for line in result.stdout.splitlines() if line.startswith('PASS ')]
    report = dict(evidence_kind='MOCK', command=['luajit', 'tests/test_probe.lua'],
                  exit_code=result.returncode, passed=len(checks), checks=checks,
                  stdout=result.stdout, stderr=result.stderr,
                  game_executed=False, direct_actions_tested=False,
                  multiplayer_tested=False,
                  source_sha256=hashlib.sha256((ROOT/'src/c4_probe.lua').read_bytes()).hexdigest())
    if result.returncode == 0:
        try:
            rows = [json.loads(line) for line in (ROOT/'evidence/mock-input-trace.jsonl').read_text().splitlines()]
            assert all(row['evidence_kind'] == 'MOCK' and row['executed_action'] == 'NONE' for row in rows)
            required = {'timestamp_utc','tick','current_weapon','current_fire_mode','input',
                        'requested_action','executed_action','pending_action','action_lock','action_result'}
            assert all(required <= row.keys() for row in rows)
            report['jsonl_rows_validated'] = len(rows)
            report['required_logging_fields'] = 'passed; unavailable gameplay values remain UNKNOWN'
        except Exception as exc:
            report['exit_code'] = 1
            report['validation_error'] = str(exc)
    (ROOT/'evidence/offline-tests.json').write_text(json.dumps(report,indent=2)+'\n')
    print(result.stdout,end='')
    if result.stderr:
        print(result.stderr,end='')
    if report.get('validation_error'):
        print(report['validation_error'])
    raise SystemExit(report['exit_code'])


if __name__ == '__main__':
    main()
