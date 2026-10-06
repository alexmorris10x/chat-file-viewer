#!/usr/bin/env python3
"""Offline identity-guard regression tests. Does not build or install an app."""
import json
import os
from pathlib import Path
import plistlib
import subprocess
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "scripts/validate-app-identity.sh"


class AppIdentityTests(unittest.TestCase):
    def settings(self, target="ChatFileViewer", configuration="Debug"):
        dev = configuration == "Debug"
        suffix = ".dev" if dev else ""
        name_suffix = " Dev" if dev else ""
        share = target == "ChatFileViewerShare"
        return {
            "TARGET_NAME": target,
            "CONFIGURATION": configuration,
            "PRODUCT_BUNDLE_IDENTIFIER": "com.10x.chatfileviewer" + suffix + (".share" if share else ""),
            "CHAT_FILE_VIEWER_DISPLAY_NAME": ("Open in " if share else "") + "Chat File Viewer" + name_suffix,
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon-Dev" if dev else "AppIcon",
        }

    def run_guard(self, settings):
        result = subprocess.run(["/bin/bash", str(GUARD)], env={"PATH": os.defpath, **settings}, capture_output=True, text=True)
        return result.returncode

    def test_valid_app_and_share_in_both_configurations(self):
        for target in ("ChatFileViewer", "ChatFileViewerShare"):
            for configuration in ("Debug", "Release"):
                with self.subTest(target=target, configuration=configuration):
                    self.assertEqual(self.run_guard(self.settings(target, configuration)), 0)

    def test_each_wrong_identity_field_is_rejected(self):
        for target in ("ChatFileViewer", "ChatFileViewerShare"):
            for configuration in ("Debug", "Release"):
                for key in ("PRODUCT_BUNDLE_IDENTIFIER", "CHAT_FILE_VIEWER_DISPLAY_NAME"):
                    with self.subTest(target=target, configuration=configuration, key=key):
                        values = self.settings(target, configuration)
                        values[key] = "wrong"
                        self.assertNotEqual(self.run_guard(values), 0)

    def test_wrong_app_icon_is_rejected_in_both_configurations(self):
        for configuration in ("Debug", "Release"):
            values = self.settings(configuration=configuration)
            values["ASSETCATALOG_COMPILER_APPICON_NAME"] = "wrong"
            self.assertNotEqual(self.run_guard(values), 0)

    def test_missing_settings_are_rejected(self):
        for key in self.settings():
            values = self.settings()
            del values[key]
            self.assertNotEqual(self.run_guard(values), 0, key)

    def test_unknown_configuration_is_rejected(self):
        values = self.settings()
        values["CONFIGURATION"] = "Staging"
        self.assertNotEqual(self.run_guard(values), 0)

    def test_plists_take_resolved_display_and_icon_settings(self):
        for target in ("ChatFileViewer", "ChatFileViewerShare"):
            with (ROOT / "apps/ios" / target / "Info.plist").open("rb") as file:
                info = plistlib.load(file)
            self.assertEqual(info["CFBundleDisplayName"], "$(CHAT_FILE_VIEWER_DISPLAY_NAME)")
            self.assertEqual(info["CFBundleIdentifier"], "$(PRODUCT_BUNDLE_IDENTIFIER)")
            if target == "ChatFileViewer":
                self.assertEqual(info["CFBundleIconName"], "$(ASSETCATALOG_COMPILER_APPICON_NAME)")

    def test_dev_icon_is_real_opaque_1024_png_and_distinct_from_production(self):
        assets = ROOT / "apps/ios/ChatFileViewer/Assets.xcassets"
        dev = assets / "AppIcon-Dev.appiconset"
        manifest = json.loads((dev / "Contents.json").read_text())
        self.assertEqual(manifest["images"], [{
            "filename": "AppIcon-1024.png", "idiom": "universal",
            "platform": "ios", "size": "1024x1024"
        }])
        image = (dev / "AppIcon-1024.png").read_bytes()
        self.assertEqual(image[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(struct.unpack(">II", image[16:24]), (1024, 1024))
        self.assertEqual(image[25], 2, "Use opaque RGB, without an alpha channel")
        self.assertNotEqual(image, (assets / "AppIcon.appiconset/AppIcon-1024.png").read_bytes())


if __name__ == "__main__":
    unittest.main()
