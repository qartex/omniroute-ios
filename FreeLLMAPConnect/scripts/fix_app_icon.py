#!/usr/bin/env python3
import subprocess
import os
import sys

icon_path = "/Users/qartex/FreeLLMAPConnect/Sources/Assets.xcassets/AppIcon.appiconset/icon_1024.png"
if not os.path.exists(icon_path):
    print(f"Icon not found at {icon_path}")
    sys.exit(1)

try:
    # Use native macOS sips tool to process the PNG and strip alpha/ensure RGB
    subprocess.run(["sips", "-s", "format", "png", icon_path, "--out", icon_path], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("App Icon processed successfully via sips.")
except Exception as e:
    print(f"Failed to process app icon via sips: {e}")
    sys.exit(1)
