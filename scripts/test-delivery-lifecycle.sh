#!/bin/sh
# test-delivery-lifecycle.sh — behavior test suite runner for the delivery lifecycle.
# Covers: onboarding, architecture/milestones/intake CI checks, design pins & locks,
# build plans with red-test enforcement, endpoint authorization, and maintenance.
set -eu

DIR="$(cd "$(dirname "$0")" && pwd)"

printf 'Running delivery lifecycle test suites...\n'
sh "$DIR/test-onboard.sh"
sh "$DIR/test-ci-checks.sh"
sh "$DIR/test-design-build.sh"
sh "$DIR/test-maintain.sh"

printf 'test-delivery-lifecycle: OK\n'
