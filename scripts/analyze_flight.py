"""Summarize saved flight evidence without treating sampled velocity as launch velocity."""
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
source = json.loads((ROOT/'private/logs/latest-flight-session.json').read_text())
rows = source['rows']
result = {'session': source['session'], 'captures': [],
          'limits': 'New charge candidate ownership is unconfirmed. Velocities are frame averages. A collision within a frame can distort them. Aiming angles and trajectories differ.'}
for begin in (r for r in rows if r.get('record_type') == 'flight_begin'):
    cid = begin['flight_capture_id']
    samples = [r for r in rows if r.get('record_type') == 'flight_sample' and r.get('flight_capture_id') == cid]
    points = [(r,p) for r in samples for p in r['flight_units'] if p['candidate']==1]
    item = {'capture': cid, 'vehicle_config': begin.get('vehicle_config'), 'vehicle_seat': begin.get('vehicle_seat'), 'samples': len(samples)}
    if points:
        first, point = points[0]
        item['first_seen_ms'] = first['flight_age_ms']
        velocities = [(r,p,math.sqrt(sum(v*v for v in p['sampled_velocity']))) for r,p in points if 'sampled_velocity' in p]
        item['first_sampled_speed_m_s'] = velocities[0][2] if velocities else None
        stopped = next(((r,p) for r,p,speed in velocities if speed < 0.05), None)
        if stopped: item['first_nearly_stationary_ms'] = stopped[0]['flight_age_ms']
        item['observed_displacement_m'] = math.dist(point['position'], points[-1][1]['position'])
        for row in rows:
            if row.get('record_type')!='pose_context' or not begin['elapsed_ms']<=row['elapsed_ms']<=first['elapsed_ms']: continue
            relation = bytes.fromhex(row.get('pose_seat_relation',''))
            if len(relation)==64 and relation[48:50]==b'\1\0':
                item['return_to_seat_observed_ms'] = row['elapsed_ms']-begin['elapsed_ms'];break
        if first.get('flight_hand_position') and samples[0].get('flight_hand_position'):
            item['hand_height_change_before_first_seen_m'] = first['flight_hand_position'][2]-samples[0]['flight_hand_position'][2]
    result['captures'].append(item)
target = ROOT/'evidence/vehicle-flight-analysis.json'
target.write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result, indent=2))
