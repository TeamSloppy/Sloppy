---
name: site-publishing
description: Publish or manage a static website through Sloppy when a web project has a deployable build, the user asks to publish/host/share a site, or an existing Sloppy site must be updated or removed.
userInvocable: true
allowedTools: files.list, files.read, runtime.exec, sites.list, sites.publish, sites.update, sites.delete
---

# Site Publishing

Use Sloppy Sites for completed static build output. Sloppy serves each bundle at `/sites/<slug>/`; it does not run a Node.js application server.

When a web task produces a deployable site:

- inspect the project's real build scripts and output directory
- configure the application base path as `/sites/<slug>/` before building; do not rely on Sloppy to rewrite HTML
- run the project's existing verification and production build
- after a successful build, offer once to publish it; do not publish until the user agrees
- publish the build output directory, never the repository root or source tree
- default to `private`; changing to `public` requires explicit user confirmation
- use `sites.list` to find the existing `siteId` before updating a deployment
- call `sites.publish` with that `siteId` to replace an existing bundle atomically
- require explicit confirmation immediately before calling `sites.delete`

After publishing, return the site URL and visibility. If validation rejects the bundle, fix the build output rather than bypassing path, secret-file, symlink, file-count, or size protections.
