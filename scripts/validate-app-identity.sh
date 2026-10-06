#!/bin/bash
# Validate Xcode's effective identity, not just project.yml's intended values.
set -euo pipefail

fail() { printf '[App Identity] ERROR: %s\n' "$1" >&2; exit 1; }

case "${CONFIGURATION:-}" in
  Debug) suffix='.dev'; display_suffix=' Dev'; icon='AppIcon-Dev' ;;
  Release) suffix=''; display_suffix=''; icon='AppIcon' ;;
  *) fail "Unsupported or missing CONFIGURATION: ${CONFIGURATION:-<missing>}" ;;
esac

case "${TARGET_NAME:-}" in
  ChatFileViewer)
    expected_id="com.10x.chatfileviewer${suffix}"
    expected_name="Chat File Viewer${display_suffix}"
    [[ "${ASSETCATALOG_COMPILER_APPICON_NAME:-}" == "$icon" ]] || fail "Expected icon $icon."
    ;;
  ChatFileViewerShare)
    expected_id="com.10x.chatfileviewer${suffix}.share"
    expected_name="Open in Chat File Viewer${display_suffix}"
    ;;
  *) fail "Unsupported or missing TARGET_NAME: ${TARGET_NAME:-<missing>}" ;;
esac

[[ "${PRODUCT_BUNDLE_IDENTIFIER:-}" == "$expected_id" ]] || fail "Expected bundle ID $expected_id."
[[ "${CHAT_FILE_VIEWER_DISPLAY_NAME:-}" == "$expected_name" ]] || fail "Expected display name $expected_name."
printf '[App Identity] Valid %s %s identity.\n' "$TARGET_NAME" "$CONFIGURATION"
