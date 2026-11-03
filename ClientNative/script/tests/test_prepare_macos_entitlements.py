import datetime
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("prepare", Path(__file__).parents[1] / "prepare_macos_entitlements.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PasskeySigningTests(unittest.TestCase):
    def setUp(self):
        self.certificate = b"test signing certificate"
        self.identity = hashlib.sha1(self.certificate).hexdigest().upper()
        self.entitlements = {module.PASSKEY: True, "com.apple.security.network.client": True}
        self.profile = {
            "Entitlements": {module.PASSKEY: True, "com.apple.application-identifier": "TEAM.team.sloppy.client"},
            "TeamIdentifier": ["TEAM"], "Platform": ["OSX"],
            "ExpirationDate": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=1),
            "DeveloperCertificates": [self.certificate],
        }

    def prepare(self, profile=None, identity=None, require=False):
        return module.prepare(self.entitlements, profile, "team.sloppy.client", "TEAM", identity or self.identity, require)

    def test_local_build_omits_managed_capability(self):
        result = self.prepare()
        self.assertNotIn(module.PASSKEY, result)
        self.assertTrue(result["com.apple.security.network.client"])
        self.assertTrue(self.entitlements[module.PASSKEY])

    def test_required_support_fails_without_profile(self):
        with self.assertRaisesRegex(ValueError, "Apple-approved"):
            self.prepare(require=True)

    def test_valid_profile_preserves_capability(self):
        result = self.prepare(self.profile, require=True)
        self.assertTrue(result[module.PASSKEY])
        self.assertEqual(result["com.apple.application-identifier"], "TEAM.team.sloppy.client")
        self.assertEqual(result["com.apple.developer.team-identifier"], "TEAM")

    def test_wrong_bundle_team_platform_expiration_or_certificate_fails(self):
        for field, value in [("TeamIdentifier", ["OTHER"]), ("Platform", ["iOS"]),
                             ("ExpirationDate", datetime.datetime(2020, 1, 1)), ("DeveloperCertificates", [b"other"])]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                self.prepare({**self.profile, field: value})
        with self.assertRaisesRegex(ValueError, "application identifier"):
            self.prepare({**self.profile, "Entitlements": {module.PASSKEY: True, "com.apple.application-identifier": "TEAM.other"}})

    def test_ad_hoc_identity_cannot_claim_managed_capability(self):
        with self.assertRaisesRegex(ValueError, "Apple-approved"):
            self.prepare(self.profile, identity="-", require=True)


if __name__ == "__main__":
    unittest.main()
