"""Embed a reviewed airportsdata snapshot without adding a runtime network dependency.

Download airportsdata/airports.csv and LICENSE from the same pinned revision of
https://github.com/mborsetti/airportsdata, then pass their paths and revision.
"""
import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--csv', required=True, type=Path)
    parser.add_argument('--license', required=True, type=Path)
    parser.add_argument('--revision', required=True)
    args = parser.parse_args()
    if not re.fullmatch(r'[0-9a-f]{40}', args.revision):
        parser.error('Use the full source commit SHA.')
    airports = {}
    with args.csv.open(encoding='utf-8-sig', newline='') as source:
        for row in csv.DictReader(source):
            code, zone = row['iata'].strip(), row['tz'].strip()
            if not re.fullmatch(r'[A-Z]{3}', code) or not zone:
                continue
            if code in airports and airports[code] != zone:
                raise ValueError(f'Conflicting time zones for {code}')
            airports[code] = zone
    if len(airports) < 7000 or airports.get('PRG') != 'Europe/Prague':
        raise ValueError('Incomplete or unexpected airport data')
    groups = defaultdict(list)
    for code, zone in sorted(airports.items()):
        groups[zone].append(code)
    license_text = args.license.read_text().strip()
    if 'MIT License' not in license_text or '*/' in license_text:
        raise ValueError('Unexpected source license')
    root = Path(__file__).resolve().parents[1] / 'assets' / 'data'
    root.mkdir(parents=True, exist_ok=True)
    (root / 'airport_timezones.json').write_text(json.dumps(airports, sort_keys=True, separators=(',', ':')))
    (root / 'airport-data-license.txt').write_text(
        f'Source: https://github.com/mborsetti/airportsdata\nRevision: {args.revision}\n\n{license_text}\n')
    print(f'Updated {len(airports)} IATA airports across {len(groups)} time zones.')


if __name__ == '__main__':
    main()
