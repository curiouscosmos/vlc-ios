"""Exercise artifact merging without downloading or compiling VLCKit."""
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


class PackageTests(unittest.TestCase):
    def test_replaces_both_ios_slices_and_preserves_watch(self):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            ios = [dict(LibraryIdentifier="ios-arm64", SupportedPlatform="ios"),
                   dict(LibraryIdentifier="ios-sim", SupportedPlatform="ios",
                        SupportedPlatformVariant="simulator")]
            watch = dict(LibraryIdentifier="watch-arm64", SupportedPlatform="watchos")
            with zipfile.ZipFile(work / "upstream.zip", "w") as archive:
                archive.writestr("COPYING.txt", "upstream license")
                archive.writestr("VLCKit.xcframework/Info.plist",
                                 plistlib.dumps(dict(AvailableLibraries=ios + [watch])))
                archive.writestr("VLCKit.xcframework/_CodeSignature/CodeResources", "old signature")
                for item in ios + [watch]:
                    archive.writestr("VLCKit.xcframework/" + item["LibraryIdentifier"] + "/binary", "stock")
                link = zipfile.ZipInfo("VLCKit.xcframework/watch-arm64/link")
                link.create_system = 3
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(link, "binary")
            patched = work / "VLCKit/build/iOS/VLCKit.xcframework"
            patched.mkdir(parents=True)
            (patched / "Info.plist").write_bytes(plistlib.dumps(dict(AvailableLibraries=ios)))
            for item in ios:
                folder = patched / item["LibraryIdentifier"]
                folder.mkdir()
                (folder / "binary").write_text("patched")
            subprocess.run([sys.executable, str(Path(__file__).parents[1] / "package.py"),
                            str(work), str(work / "Artifacts")], check=True)
            result = work / "Artifacts/VLCKit.xcframework"
            info = plistlib.loads((result / "Info.plist").read_bytes())
            self.assertEqual(len(info["AvailableLibraries"]), 3)
            self.assertEqual((work / "Artifacts/COPYING.txt").read_text(), "upstream license")
            self.assertFalse((result / "_CodeSignature").exists())
            for item in ios:
                self.assertEqual((result / item["LibraryIdentifier"] / "binary").read_text(), "patched")
            self.assertEqual((result / "watch-arm64/binary").read_text(), "stock")
            self.assertTrue((result / "watch-arm64/link").is_symlink())


if __name__ == "__main__":
    unittest.main()
