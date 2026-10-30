"""Create tiny ignored fixtures shared with UTTDB's /source-files mount.

Run from the repository root: python tests/create-mirror-fixtures.py
These are opaque test bytes, not valid NetCDF files: registration must not parse them.
"""
import json
from pathlib import Path

fixture_dir = Path(__file__).resolve().parents[1] / 'uttdb/source-files/.utt-ver03-check'
fixture_dir.mkdir(parents=True, exist_ok=True)
(fixture_dir / 'v1.nc').write_bytes(b'native-v1')
(fixture_dir / 'v2.nc').write_bytes(b'native-v2' + b'x' * 1_100_000)
(fixture_dir / 'sample.geojson').write_text(json.dumps({
    'type': 'FeatureCollection',
    'features': [{
        'type': 'Feature', 'properties': {'id': 1},
        'geometry': {'type': 'Point', 'coordinates': [13.4, 52.5]},
    }],
}), encoding='utf-8')
print(f'Created mirror test fixtures in {fixture_dir}')
