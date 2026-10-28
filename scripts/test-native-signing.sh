#!/bin/sh
set -eu
w=.github/workflows/huynle-release.yml
grep -q 'environment: fleet-code-signing' "$w"
grep -q 'id-token: write' "$w"
grep -q 'codesign --verify --deep --strict' "$w"
grep -q 'xcrun notarytool submit' "$w"
grep -q 'signtool verify /pa /all' "$w"
grep -q 'APPLE_CERTIFICATE_P12:' "$w"
grep -q 'AZURE_TRUSTED_SIGNING_ACCOUNT:' "$w"
! grep -q 'secrets: inherit' "$w"
