#!/bin/sh
# test-release-pipeline.sh — behavior test suite runner for release and local release pipelines.
# Covers: MR body rendering, release notes extraction & changelog insertion,
# local release checkpoints, and integration branch resolution.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

printf 'Running release pipeline test suites...\n'
sh "$DIR/test-release.sh"

printf 'test-release-pipeline: OK\n'
