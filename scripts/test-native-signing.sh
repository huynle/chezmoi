#!/bin/sh
set -eu
w=.github/workflows/huynle-release.yml
grep -q 'environment: fleet-code-signing' "$w"
grep -q 'id-token: write' "$w"
grep -q 'codesign --verify --deep --strict' "$w"
grep -q 'xcrun notarytool submit' "$w"
grep -q 'spctl --assess --type open --context context:primary-signature' "$w"
grep -q 'signtool verify /pa /all' "$w"
grep -q 'APPLE_CERTIFICATE_P12:' "$w"
grep -q 'AZURE_ARTIFACT_SIGNING_ACCOUNT:' "$w"
grep -q 'azure/artifact-signing-action@c7ab2a863ab5f9a846ddb8265964877ef296ee82' "$w"
! grep -q 'secrets: inherit' "$w"
