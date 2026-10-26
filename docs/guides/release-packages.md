# Ready-to-run release packages

End users install GitHub Release assets. Swift, Node.js and Windows Build Tools are build-host dependencies only.

For a CLI/runtime release, create a draft release for the intended version, then dispatch `release.yml` with `release_tag`, an immutable `source_ref`, `build_platform=cli`, and `publish_release=false`. The workflow builds macOS, Linux and Windows packages and preserves the separately versioned desktop app downloads and update feeds.

Before publication:

- Run the packaged CLI, SQLite-backed server, API health endpoint and web Dashboard.
- Verify Linux in the clean Ubuntu container without Swift.
- Run `verify-linux` or `verify-windows` with `artifact_run_id` to check an existing archive on a fresh runner without recompiling it.
- Check every asset against `SHA256SUMS.txt`, including the standalone `install.sh` and `install.ps1` assets.
- Keep the release as a draft until the package checks pass. Publishing exposes it to the one-command installers through GitHub's latest-release URLs.

For the macOS desktop download, a valid code signature alone is insufficient. Use the existing Developer ID identity and the local `AdaEngine` notarytool profile, require an `Accepted` response, staple both the application and final disk image, and verify Gatekeeper on the image and its mounted app. Keep the app's own version explicit when it differs from the CLI release version.

The release may be built from an earlier immutable product commit while workflow fixes are validated on the release branch. Before assigning the final tag, verify that all compiled product sources, dependency pins and shipped installer scripts are identical to the build source, and record the build and verification runs in `release-provenance.json`.
