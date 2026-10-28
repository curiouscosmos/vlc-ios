#!/usr/bin/env python3
"""Replace only the iOS slices of the checksum-verified upstream XCFramework."""
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

work, destination = map(Path, sys.argv[1:])
upstream = work / "upstream"
if upstream.exists():
    shutil.rmtree(upstream)
# Preserve framework symlinks and permissions from the official archive.
subprocess.run(["ditto", "-x", "-k", str(work / "upstream.zip"), str(upstream)], check=True)
original, = upstream.glob("**/VLCKit.xcframework")
patched = work / "VLCKit/build/iOS/VLCKit.xcframework"
with (original / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
with (patched / "Info.plist").open("rb") as stream:
    replacement = plistlib.load(stream)
ios = replacement["AvailableLibraries"]
assert ios and all(item["SupportedPlatform"] == "ios" for item in ios)
assert any(item.get("SupportedPlatformVariant") == "simulator" for item in ios)
assert any("SupportedPlatformVariant" not in item for item in ios)
destination.mkdir(parents=True, exist_ok=True)
shutil.copy2(upstream / "COPYING.txt", destination / "COPYING.txt")
staging = destination / "staging.xcframework"
if staging.exists():
    shutil.rmtree(staging)
shutil.copytree(original, staging, symlinks=True)
# The modified container cannot retain the upstream container's signature.
if (staging / "_CodeSignature").exists():
    shutil.rmtree(staging / "_CodeSignature")
for item in info["AvailableLibraries"]:
    if item["SupportedPlatform"] == "ios":
        shutil.rmtree(staging / item["LibraryIdentifier"])
for item in ios:
    shutil.copytree(patched / item["LibraryIdentifier"], staging / item["LibraryIdentifier"], symlinks=True)
info["AvailableLibraries"] = [item for item in info["AvailableLibraries"]
                              if item["SupportedPlatform"] != "ios"] + ios
with (staging / "Info.plist").open("wb") as stream:
    plistlib.dump(info, stream)
target = destination / "VLCKit.xcframework"
if target.exists():
    shutil.rmtree(target)
staging.rename(target)
