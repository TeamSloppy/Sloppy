# Delivering user documentation

Features require a new article or substantial update under authored `docs/` user surfaces,
with a usable example, relevant setup, platform/performance limits and navigation.
Use `docs/guides/`, `docs/agents/`, `docs/channels/`, `docs/dashboard/` or another existing
user-facing section. Internal design/spec/product/ADR/plan/legal documents do not qualify.

Public improvements update their guide. Internal improvements record why no user-facing
instruction changes, and the independent reviewer examines that explanation. Bugs update
guides when their correction affects documented usage; no artificial article is needed.

Declare article/navigation paths using the runner's `documentation` command before code.
Accepted navigation includes a Markdown link from another user page or `CONTRIBUTING.md`,
and static `link: "/guides/example"` entries in `docs/.vitepress/config.ts`. Keep existing
navigation changes intact. Generated `.vitepress/dist/` files are not article sources.

Before review, the article must exist, differ from its task baseline and be linked from
the declared navigation. The script checks structure and freshness; the reviewer checks
accuracy, examples and completeness against actual shipped APIs. Run the VitePress build.
