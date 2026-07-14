# Contributing

Thanks for improving Chat File Viewer.

## Development

1. Fork or branch from `main`.
2. Keep changes focused and avoid committing generated build state or private files.
3. Build the project and compile its tests:

```bash
xcodebuild \
  -project ChatFileViewer.xcodeproj \
  -scheme ChatFileViewer \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build-for-testing
```

4. Explain the user-visible impact and validation in the pull request.

Use public issues for ordinary bugs. Follow [SECURITY.md](SECURITY.md) for vulnerabilities and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for conduct expectations.
