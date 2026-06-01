"""Render V1 Spring Bloom at 4096 and install to AppIcon.appiconset."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from variants import V1_spring_bloom
from generate import squircle_mask, SS
from PIL import Image

SIZES = [16, 32, 64, 128, 256, 512, 1024]
DEST = "/Users/jmlee/Petals/Petals/Petals/Assets.xcassets/AppIcon.appiconset"

print("Rendering V1 Spring Bloom at 4096...")
hires = V1_spring_bloom()
mask = squircle_mask(SS)
masked = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
masked.paste(hires, mask=mask)

for s in SIZES:
    out = masked.resize((s, s), Image.LANCZOS)
    path = os.path.join(DEST, f"{s}.png")
    out.save(path, "PNG")
    print(f"  wrote {path} ({s}x{s})")

print("Done.")
