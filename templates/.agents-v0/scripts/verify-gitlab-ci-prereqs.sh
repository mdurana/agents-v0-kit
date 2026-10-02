#!/bin/sh
# verify-gitlab-ci-prereqs.sh — check the GitLab token and print the Docker runner choice.
#
# Usage:
#   GITLAB_TOKEN=... GITLAB_HOST=https://gitlab.example GITLAB_PROJECT_ID=123 \
#     sh .agents-v0/scripts/verify-gitlab-ci-prereqs.sh
# Inside GitLab CI, GITLAB_HOST defaults to CI_SERVER_URL and GITLAB_PROJECT_ID to CI_PROJECT_ID.
# GITLAB_TOKEN must be a project access token with read_api, masked, and scoped only to the
# delivery-approval environment. Set DOCKER_REQUIRED=1 to fail when docker info does not succeed.
set -eu

fail=0
err() { printf 'FAIL: %s\n' "$1" >&2; fail=1; }
ok() { printf 'OK: %s\n' "$1"; }

python3 -c 'import yaml' >/dev/null 2>&1 \
  || err "PyYAML is missing (pip install pyyaml, or apk add py3-yaml)"

token="${GITLAB_TOKEN:-}"
host="${GITLAB_HOST:-${CI_SERVER_URL:-}}"
project="${GITLAB_PROJECT_ID:-${CI_PROJECT_ID:-}}"

if [ -z "$token" ]; then
  err "GITLAB_TOKEN is unset. Create a project access token with read_api, mask it, and scope it to the delivery-approval environment only."
elif [ -z "$host" ] || [ -z "$project" ]; then
  err "Set GITLAB_HOST and GITLAB_PROJECT_ID (or run inside GitLab CI) to check the token."
elif ! command -v curl >/dev/null 2>&1; then
  err "curl is required to check GITLAB_TOKEN"
else
  host="${host%/}"
  body="$(mktemp)"
  code="$(curl -sS -o "$body" -w '%{http_code}' --header "PRIVATE-TOKEN: ${token}" \
    "${host}/api/v4/projects/${project}")" || code="000"
  rm -f "$body"
  case "$code" in
    200) ok "GITLAB_TOKEN can read project ${project} (read_api)" ;;
    401) err "GITLAB_TOKEN was rejected (401)" ;;
    403) err "GITLAB_TOKEN cannot read the project (403). It needs read_api, scoped to delivery-approval." ;;
    *) err "GitLab project API returned HTTP ${code}" ;;
  esac
fi

printf '%s\n' "Docker: the build job uses docker:27-dind and needs a runner that allows privileged jobs."
printf '%s\n' "When privileged jobs are forbidden, delete the dind service and the DOCKER_* / TESTCONTAINERS_* variables and mount /var/run/docker.sock (see the comment on the build job in .gitlab-ci.yml)."
if [ "${DOCKER_REQUIRED:-0}" = 1 ]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    ok "docker info succeeded"
  else
    err "docker info failed (DOCKER_REQUIRED=1)"
  fi
fi

if [ "$fail" -ne 0 ]; then
  printf 'verify-gitlab-ci-prereqs: FAILED\n' >&2
  exit 1
fi
printf 'verify-gitlab-ci-prereqs: OK\n'
