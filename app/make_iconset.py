# Generate an Assets.xcassets app-icon set from app/icons.json — the same
# base64 PNG source decode_icons.py decodes into loose bundle files.
# Every slot gets a default entry plus a dark entry (luminosity
# appearance), reusing the ~dark PNG filenames as iconset filenames.
# build.sh compiles the result with actool into Assets.car: iOS does not
# honour loose-file ~dark app icons in this hand-assembled bundle
# (26D109), but it does honour a catalog-compiled AppIcon set.
# Usage: python3 app/make_iconset.py <output Assets.xcassets dir>
import base64, json, pathlib, struct, sys

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

def png_size(raw, filename):
    # Pure-stdlib PNG dimension check (the CI runner's python3 has no
    # Pillow): after the 8-byte signature comes the IHDR chunk — its
    # length (4 bytes) and type (4 bytes) precede width/height as
    # big-endian uint32 at bytes 16-24.
    if len(raw) < 24 or raw[:8] != PNG_SIGNATURE or raw[12:16] != b"IHDR":
        sys.exit("ERROR: %s is not a valid PNG (bad signature or missing IHDR)" % filename)
    return struct.unpack(">II", raw[16:24])

# (idiom, size, scale or None, light filename, dark filename)
SLOTS = [
    ("iphone", "29x29", "3x", "AppIcon29x29@3x.png", "AppIcon29x29@3x~dark.png"),
    ("iphone", "40x40", "2x", "AppIcon40x40@2x.png", "AppIcon40x40@2x~dark.png"),
    ("iphone", "60x60", "2x", "AppIcon60x60@2x.png", "AppIcon60x60@2x~dark.png"),
    ("iphone", "60x60", "3x", "AppIcon60x60@3x.png", "AppIcon60x60@3x~dark.png"),
    ("ipad", "76x76", "2x", "AppIcon76x76@2x.png", "AppIcon76x76@2x~dark.png"),
    ("ipad", "83.5x83.5", "2x", "AppIcon83.5x83.5@2x.png", "AppIcon83.5x83.5@2x~dark.png"),
    ("ios-marketing", "1024x1024", None, "AppIcon1024.png", "AppIcon1024~dark.png"),
]

OUT = pathlib.Path(sys.argv[1])
DATA = json.loads((pathlib.Path(__file__).resolve().parent / "icons.json").read_text(encoding="utf-8"))

iconset = OUT / "AppIcon.appiconset"
iconset.mkdir(parents=True, exist_ok=True)

images = []
for idiom, size, scale, light, dark in SLOTS:
    for filename, appearances in ((light, None), (dark, [{"appearance": "luminosity", "value": "dark"}])):
        if filename not in DATA:
            sys.exit("ERROR: %s missing from icons.json" % filename)
        raw = base64.b64decode(DATA[filename])
        # Self-check: the decoded PNG must be exactly size x scale pixels.
        w, h = png_size(raw, filename)
        factor = int(scale[:-1]) if scale else 1
        expect = round(float(size.split("x")[0]) * factor)
        if (w, h) != (expect, expect):
            sys.exit("ERROR: %s is %dx%d, expected %dx%d for %s %s@%s"
                     % (filename, w, h, expect, expect, idiom, size, scale or "1x"))
        (iconset / filename).write_bytes(raw)
        entry = {"filename": filename, "idiom": idiom, "size": size}
        if scale:
            entry["scale"] = scale
        if appearances:
            entry["appearances"] = appearances
        images.append(entry)
        print("wrote", iconset / filename, len(raw))

# 26F130 (fold-in 4): the launch screen shows the SAME universal
# 城轨通 poster the native splash uses (splash-st / splash-st-dark),
# so the very first frame already matches the splash instead of a
# blank white/black beat while the app starts. The poster is not
# per-city, so this does not revive the build-45 problem (a static
# Beijing splash flashing for other cities). Light + dark variants
# ride the luminosity appearance like the app icon.
splashset = OUT / "LaunchSplash.imageset"
splashset.mkdir(parents=True, exist_ok=True)
splash_images = []
for src, filename, appearances in (
        ("splash-st.b64", "LaunchSplash.jpg", None),
        ("splash-st-dark.b64", "LaunchSplash~dark.jpg",
         [{"appearance": "luminosity", "value": "dark"}])):
    raw = base64.b64decode((pathlib.Path(__file__).resolve().parent / src).read_text(encoding="utf-8").strip())
    if raw[:2] != b"\xff\xd8":
        sys.exit("ERROR: %s is not a JPEG" % src)
    (splashset / filename).write_bytes(raw)
    entry = {"filename": filename, "idiom": "universal"}
    if appearances:
        entry["appearances"] = appearances
    splash_images.append(entry)
    print("wrote", splashset / filename, len(raw))
(splashset / "Contents.json").write_text(
    json.dumps({"images": splash_images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
    encoding="utf-8")
print("wrote", splashset / "Contents.json", "with", len(splash_images), "image entries")

(iconset / "Contents.json").write_text(
    json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
    encoding="utf-8")
(OUT / "Contents.json").write_text(
    json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n",
    encoding="utf-8")
print("wrote", iconset / "Contents.json", "with", len(images), "image entries")
