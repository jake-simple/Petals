#!/usr/bin/env python3
"""Validate every shipped locale, format argument, and extracted UI key."""
import collections
import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
LANGUAGES = {'en', 'ko', 'de', 'es', 'fr', 'ja', 'pt-BR'}
ARGUMENT = re.compile(r'%(?:(\d+)\$)?(lld|ld|llu|lu|@|d|u|f)')


def arguments(value):
    # Ignore escaped literal percent signs; positional arguments may reorder.
    matches = ARGUMENT.findall(value.replace('%%', ''))
    return collections.Counter((int(position) if position else i, kind)
                               for i, (position, kind) in enumerate(matches, 1))


catalogs = {}
for name in ['Localizable', 'InfoPlist']:
    data = json.loads((ROOT / f'Petals/Petals/{name}.xcstrings').read_text())
    catalogs[name] = data['strings']
    for key, item in data['strings'].items():
        translations = item.get('localizations', {})
        assert set(translations) == LANGUAGES, (name, key, set(translations))
        reference = translations['en']['stringUnit']['value']
        for language, translation in translations.items():
            unit = translation['stringUnit']
            assert unit['state'] == 'translated', (name, key, language)
            assert unit['value'].strip() or not reference.strip(), (name, key, language)
            assert arguments(unit['value']) == arguments(reference), (name, key, language)
            assert language == 'ko' or not re.search('[가-힣]', unit['value']), (key, language)
    print(f'{name}: {len(data["strings"])} keys × {len(LANGUAGES)} languages passed')

if len(sys.argv) > 1:
    extracted = set()
    files = list(pathlib.Path(sys.argv[1]).rglob('*.stringsdata'))
    assert files, 'No compiler string extraction found'
    for file in files:
        data = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(file)]))
        for item in data.get('tables', {}).get('Localizable', []):
            extracted.add(item['key'])
    assert not (missing := extracted - catalogs['Localizable'].keys()), missing
    print(f'All {len(extracted)} compiler-extracted UI keys are translated')
