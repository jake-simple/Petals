"""Take the high-quality 4096 render of Concept C, downsample to each
required macOS app icon size with LANCZOS, and install into
Petals/Petals/Petals/Assets.xcassets/AppIcon.appiconset/.

Re-renders Concept C at SS=4096 (not the cached 1024) so each downscale
starts from maximum detail.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from generate import concept_C, squircle_mask, SS
from PIL import Image

SIZES = [16, 32, 64, 128, 256, 512, 1024]
DEST = "/Users/jmlee/Petals/Petals/Petals/Assets.xcassets/AppIcon.appiconset"
BACKUP = "/Users/jmlee/Petals/AppStore/icon-preview/concepts/backup_previous"

# Back up the existing icon set first.
os.makedirs(BACKUP, exist_ok=True)
for fname in os.listdir(DEST):
    if fname.endswith(".png"):
        src = os.path.join(DEST, fname)
        with open(src, "rb") as f:
            data = f.read()
        with open(os.path.join(BACKUP, fname), "wb") as f:
            f.write(data)
print(f"Backed up previous icons to: {BACKUP}")

print("Re-rendering Concept C at 4096...")
hires = concept_C()  # 4096 RGBA, no mask
mask = squircle_mask(SS)
masked = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
masked.paste(hires, mask=mask)

for s in SIZES:
    out = masked.resize((s, s), Image.LANCZOS)
    path = os.path.join(DEST, f"{s}.png")
    out.save(path, "PNG")
    print(f"  wrote {path} ({s}x{s})")

print("Done.")
