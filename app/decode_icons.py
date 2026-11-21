# Decode the bundled app icons (app/icons.json, base64 PNGs) into an .app bundle.
# Usage: python3 app/decode_icons.py <path-to-Subway Tools.app>
import base64, json, pathlib, sys

APP = pathlib.Path(sys.argv[1])
DATA = json.loads((pathlib.Path(__file__).resolve().parent / "icons.json").read_text(encoding="utf-8"))
for name, b64 in DATA.items():
    dest = APP / name
    dest.write_bytes(base64.b64decode(b64))
    print("wrote", dest, dest.stat().st_size)
