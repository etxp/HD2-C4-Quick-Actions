"""Read saved C4 logs; separate aim loss, seat return and projectile travel.

Never attaches to the game. No candidate is assumed to be player-owned, and a
frame-average velocity is not treated as the exact launch velocity.
"""
import argparse
import collections
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def aim(row):
    try:
        value = bytes.fromhex(row.get('pose_input_8', ''))
    except ValueError:
        return None
    return bool(value[0]) if len(value) == 8 and value[0] in (0, 1) else None


def seat(row):
    try:
        value = bytes.fromhex(row.get('pose_seat_relation', ''))
    except ValueError:
        return None
    if len(value) != 64 or value[48] > 1 or value[49] > 1:
        return None
    return dict(transition=bool(value[48]), leaned=bool(value[49]),
                config=int.from_bytes(value[4:8], 'little'),
                role=int.from_bytes(value[8:12], 'little'),
                seat=int.from_bytes(value[28:32], 'little'))


def analyze(rows):
    # Preserve record order: poses emitted before an action in the same Lua
    # callback are meaningful. Do not use the inherited/stale avatar_flags.
    poses = [(i, r) for i, r in enumerate(rows) if r.get('record_type') == 'pose_context']
    items = []
    for index, begin in enumerate(rows):
        if begin.get('record_type') != 'flight_begin':
            continue
        cid, start = begin['flight_capture_id'], begin['elapsed_ms']
        samples = [r for r in rows[index + 1:] if r.get('record_type') == 'flight_sample'
                   and r.get('flight_capture_id') == cid]
        ending = next((r for r in rows[index + 1:] if r.get('record_type') == 'flight_end'
                       and r.get('flight_capture_id') == cid), {})
        before = [r for i, r in poses if i <= index]
        baseline = before[-1] if before else {}
        native_seat = seat(baseline)
        item = dict(capture=cid, request=begin.get('flight_request_id'),
                    elapsed_ms=start, sample_count=len(samples),
                    end_reason=ending.get('flight_reason', 'not_observed'),
                    seat_at_start=native_seat,
                    pose_age_at_start_ms=start - baseline['elapsed_ms'] if baseline else None,
                    aim_at_start=aim(baseline),
                    candidate_ownership='UNCONFIRMED')
        candidates = collections.defaultdict(list)
        for sample in samples:
            for point in sample['flight_units']:
                candidates[point['candidate']].append((sample, point))
        item['candidate_count'] = len(candidates)
        # Multiple newly seen units cannot be attributed to this throw.
        if len(candidates) != 1:
            item['trajectory_status'] = 'no_candidate' if not candidates else 'ambiguous_candidates'
            items.append(item)
            continue
        points = next(iter(candidates.values()))
        first, origin = points[0]
        until_release = [r for i, r in poses if index < i and r['elapsed_ms'] <= first['elapsed_ms']]
        interval_poses = [baseline] + until_release if baseline else until_release
        values = [aim(r) for r in interval_poses]
        # This is sampled evidence, never a claim about the physical button.
        item['aim_active_in_all_recorded_poses_until_first_seen'] = (
            all(values) if baseline and all(v is not None for v in values) else None)
        returns = [r for r in interval_poses if (s := seat(r)) and s['transition'] and not s['leaned']]
        item['return_before_first_seen_ms'] = returns[0]['elapsed_ms'] - start if returns else None
        item['first_seen_ms'] = first['flight_age_ms']
        item['trajectory_status'] = 'single_unattributed_candidate'
        item['observed_displacement_m'] = math.dist(origin['position'], points[-1][1]['position'])
        item['observed_horizontal_displacement_m'] = math.dist(origin['position'][:2], points[-1][1]['position'][:2])
        velocities = [(r, p) for r, p in points if 'sampled_velocity' in p]
        if velocities:
            r, p = velocities[0]
            v = p['sampled_velocity']
            horizontal = math.hypot(v[0], v[1])
            item['first_sampled_velocity_m_s'] = v
            item['first_sampled_speed_m_s'] = math.hypot(*v)
            item['first_sampled_elevation_deg'] = math.degrees(math.atan2(v[2], horizontal))
            item['first_velocity_interval_ms'] = p.get('sample_interval_ms')
            stopped = next((r for r, p in velocities if math.hypot(*p['sampled_velocity']) < .05), None)
            item['first_nearly_stationary_ms'] = stopped['flight_age_ms'] if stopped else None
        # No 'range' field: the observation window can end while still airborne.
        items.append(item)
    return dict(captures=items, limits=[
        'Projectile ownership and collision objects are not identified.',
        'Aim is the sampled native action output, not the physical button.',
        'Pose logs report changes and heartbeats; missing segments can hide transitions.',
        'Velocities/elevation are frame averages and may include a collision.',
        'Displacement within the observation window is not necessarily landing range.',
        'Different angles, terrain and vehicle motion prevent a direct range comparison.',
    ])


def load(paths):
    sessions = collections.defaultdict(list)
    warnings = []
    # Rolling filenames reuse slots. Segment sequence is in the first row.
    for path in paths:
        parsed = []
        for lineno, line in enumerate(path.read_bytes().splitlines(), 1):
            try:
                parsed.append(json.loads(line))
            except (ValueError, UnicodeError):
                warnings.append(f'{path.name}:{lineno}: incomplete or invalid record skipped')
        if not parsed:
            continue
        header = parsed[0]
        sessions[header['session_id']].append((header['segment'], header.get('version'), parsed))
    results = {}
    for sid, segments in sessions.items():
        segments.sort(key=lambda entry: entry[0])
        numbers = [segment[0] for segment in segments]
        if len(set(numbers)) != len(numbers):
            raise ValueError(f'Duplicate segments in {sid}; provide one copy of each log')
        report = analyze([row for _, _, rows in segments for row in rows])
        report.update(version=segments[0][1], segments=numbers,
                      complete_segment_sequence=numbers == list(range(1, numbers[-1] + 1)))
        results[sid] = report
    return dict(sessions=results, warnings=warnings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('logs', nargs='+', type=Path)
    parser.add_argument('--output', type=Path, default=ROOT / 'evidence/vehicle-throw-comparison.json')
    args = parser.parse_args()
    report = load(args.logs)
    output = args.output.resolve()
    assert output.is_relative_to(ROOT), 'Keep analysis output inside this project'
    output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(output)
    for sid, result in report['sessions'].items():
        print(sid, result['version'], len(result['captures']), 'captures')


if __name__ == '__main__':
    main()
