#!/bin/bash
# Format stream-json output to human-readable format
# Passthrough mode: just stream raw JSON lines for debugging/visibility
# TODO: Replace with a proper single-process formatter (Node.js or jq --stream)
set -euo pipefail

cat
