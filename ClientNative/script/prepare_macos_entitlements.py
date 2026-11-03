#!/usr/bin/env python3
"""Resolve source entitlements against the profile used for a local signature."""
import datetime
import hashlib
import os
import plistlib
import sys

PASSKEY = "com.apple.developer.web-browser.public-key-credential"
KVS = "com.apple.developer.ubiquity-kvstore-identifier"


def prepare(entitlements, profile, bundle_id, team_id, identity, require_passkeys=False):
    result = dict(entitlements)
    granted = profile.get("Entitlements", {}) if profile and identity != "-" else {}
    if KVS in result:
        identifier = granted.get(KVS, "")
        if identifier and "*" not in identifier:
            result[KVS] = identifier
        else:
            result.pop(KVS)
            print("warning: no iCloud key-value provisioning profile; browser history will stay local in this build.", file=sys.stderr)
    if result.get(PASSKEY):
        if granted.get(PASSKEY) is True:
            app_id = granted.get("com.apple.application-identifier", granted.get("application-identifier"))
            if app_id != f"{team_id}.{bundle_id}" or team_id not in profile.get("TeamIdentifier", []):
                raise ValueError("passkey profile does not match the signing team and application identifier")
            if "OSX" not in profile.get("Platform", []):
                raise ValueError("passkey profile is not for macOS")
            expires = profile.get("ExpirationDate")
            if not expires or expires.replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
                raise ValueError("passkey provisioning profile is expired or has no expiration date")
            fingerprints = {hashlib.sha1(cert).hexdigest().upper() for cert in profile.get("DeveloperCertificates", [])}
            if identity.upper() not in fingerprints:
                raise ValueError("passkey profile does not include the selected signing certificate; use its SHA-1 identity")
            result["com.apple.application-identifier"] = app_id
            result["com.apple.developer.team-identifier"] = team_id
        elif require_passkeys:
            raise ValueError("passkeys require an Apple-approved macOS profile containing the browser public-key-credential entitlement")
        else:
            result.pop(PASSKEY)
            print("warning: no approved browser passkey profile; passkeys are unavailable in this build. Set MACOS_PASSKEY_PROVISIONING_PROFILE and MACOS_REQUIRE_PASSKEYS=1 to require support.", file=sys.stderr)
    return result


if __name__ == "__main__":
    source, output, bundle_id, team_id, identity, profile_path = sys.argv[1:]
    try:
        with open(source, "rb") as stream:
            entitlements = plistlib.load(stream)
        profile = None
        if profile_path:
            with open(profile_path, "rb") as stream:
                profile = plistlib.load(stream)
        result = prepare(entitlements, profile, bundle_id, team_id, identity,
                         os.environ.get("MACOS_REQUIRE_PASSKEYS") == "1")
        with open(output, "wb") as stream:
            plistlib.dump(result, stream)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        sys.exit(f"error: {error}")
