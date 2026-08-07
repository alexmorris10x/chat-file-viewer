# Chat File Viewer

This file applies to the entire `chat-file-viewer` repository.

## Product context

- Canonical app documentation: `docs/`
- Read `docs/product/Product Context Brief.md` before substantive product decisions.
- Keep dated work packets and temporary evidence in the owning 10x-os lifecycle department.

## Repository map

- `apps/ios/` — iOS app, share extension, tests, XcodeGen definition, Xcode project, and Xcode Cloud configuration
- `docs/` — canonical durable app-specific product and technical documentation
- `.github/` — repository-wide continuous-integration configuration

## Working rules

- Follow the global agent rules, then these repository-specific rules.
- Preserve unrelated local changes, including untracked Xcode Cloud configuration.
- Treat `apps/ios/project.yml` as the source of truth for the Xcode project.
- After iOS source or project changes, run the cheapest complete ChatFileViewer app-target build.
- Do not treat generated build output, `.DS_Store`, dependencies, or tool state as durable source.
