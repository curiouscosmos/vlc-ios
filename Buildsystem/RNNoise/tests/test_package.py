"""Exercise artifact merging without downloading or compiling VLCKit."""
import plistlib
import json
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


class PackageTests(unittest.TestCase):
    def test_activation_replaces_the_remote_package(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            script_dir = root / "Buildsystem/RNNoise"
            (script_dir / "Artifacts/VLCKit.xcframework").mkdir(parents=True)
            shutil.copy(Path(__file__).parents[1] / "activate.rb", script_dir)
            lock = root / "VLC.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            lock.parent.mkdir(parents=True)
            lock.write_text(json.dumps(dict(version=3, pins=[dict(identity="vlckit"), dict(identity="other")])))
            fixture = """
require 'xcodeproj'
project = Xcodeproj::Project.new(ARGV[0])
remote = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
remote.repositoryURL = 'https://code.videolan.org/videolan/VLCKit.git'
remote.requirement = { 'kind' => 'exactVersion', 'version' => '4.0.0-a25' }
project.root_object.package_references << remote
target = project.new_target(:application, 'App', :ios, '15.0')
product = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
product.product_name = 'VLCKit'
product.package = remote
target.package_product_dependencies << product
project.save
"""
            subprocess.run(["ruby", "-e", fixture, str(root / "VLC.xcodeproj")], check=True)
            subprocess.run(["ruby", str(script_dir / "activate.rb")], check=True, capture_output=True)
            project = (root / "VLC.xcodeproj/project.pbxproj").read_text()
            self.assertIn("XCLocalSwiftPackageReference", project)
            self.assertNotIn("XCRemoteSwiftPackageReference", project)
            self.assertIn("relativePath = Buildsystem/RNNoise;", project)
            self.assertEqual(json.loads(lock.read_text())["pins"], [dict(identity="other")])
            subprocess.run(["ruby", str(script_dir / "activate.rb")], check=True, capture_output=True)
            self.assertEqual((root / "VLC.xcodeproj/project.pbxproj").read_text(), project)

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
