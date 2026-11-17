"""Check .spell bundles against the convention (docs/spells.md, "Bundle format").

Usage: python3 server/check_bundle.py file.spell...   (exit 1 on violations)
"""

import io
import json
import sys
import zipfile

import forge
import sheet


def check(data: bytes) -> list[str]:
    try:
        z = zipfile.ZipFile(io.BytesIO(data))
        spell = json.loads(z.read("manifest.json"))
    except (zipfile.BadZipFile, KeyError, json.JSONDecodeError) as e:
        return [f"no readable manifest.json: {e}"]
    errors = []
    if spell.get("format") != forge.BUNDLE_FORMAT:
        errors.append(f"format {spell.get('format')} != {forge.BUNDLE_FORMAT}")
    files = set(z.namelist())
    icon = spell.get("icon_file")
    if icon:
        if icon not in files:
            errors.append(f"{icon}: missing")
        elif sheet.read_png(z.read(icon))[:2] != (sheet.ICON, sheet.ICON):
            errors.append(f"{icon}: not {sheet.ICON}x{sheet.ICON}")
    for i, body in enumerate(forge.bodies(spell.get("emit"))):
        for key, loop in (("sheet", True), ("burst_sheet", False)):
            meta = body.get(key)
            if not meta:
                continue
            name = meta.get("file", "?")
            if name not in files:
                errors.append(f"body {i} {key} {name}: missing")
                continue
            if meta.get("loop") is not loop:
                errors.append(f"body {i} {key} {name}: loop should be {loop}")
            errors += [f"body {i} {key} {name}: {e}" for e in sheet.check(z.read(name), meta)]
    return errors


if __name__ == "__main__":
    bad = False
    for path in sys.argv[1:]:
        errors = check(open(path, "rb").read())
        bad = bad or bool(errors)
        print(f"{path}: " + ("OK" if not errors else "\n  " + "\n  ".join(errors)))
    sys.exit(1 if bad else 0)
