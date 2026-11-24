#!/usr/bin/env bash
# Continuous deployment step. Runs on the VM through the self-hosted GitHub runner.
#
#   1. Copies docker-compose.yml from the checked-out commit into the deploy folder
#   2. Updates the image tag in that Compose file to the image CI just pushed
#   3. Pulls the new image and recreates the container
#   4. Checks the container is healthy, and rolls back to the last good tag if not
#
# Required environment variables:
#   APP_NAME       Compose project and container name (client / server)
#   IMAGE          Image without tag, e.g. docker.io/amin0513/devops-capstone-client
#   IMAGE_TAG      Tag to deploy, e.g. sha-1a2b3c4
# Optional:
#   DEPLOY_DIR     Where the live Compose file is kept (default: $HOME/deploy/$APP_NAME)
#   HEALTH_CMD     Command that must succeed once the container is up
#   HEALTH_TIMEOUT Seconds to wait for HEALTH_CMD (default: 60)
set -euo pipefail

: "${APP_NAME:?APP_NAME is required}"
: "${IMAGE:?IMAGE is required}"
: "${IMAGE_TAG:?IMAGE_TAG is required}"
DEPLOY_DIR="${DEPLOY_DIR:-$HOME/deploy/$APP_NAME}"
HEALTH_TIMEOUT="${HEALTH_TIMEOUT:-60}"
SRC_COMPOSE="${SRC_COMPOSE:-docker-compose.yml}"

COMPOSE_FILE="$DEPLOY_DIR/docker-compose.yml"
LAST_GOOD="$DEPLOY_DIR/.last_successful_tag"

log() { echo "[deploy:$APP_NAME] $*"; }

# Variables such as SERVER_HOST are written to /etc/environment by Terraform.
# The runner service does not read that file, so pick those two values up here
# (only these, so PATH and the rest of the runner's environment stay as they are).
if [ -r /etc/environment ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      SERVER_HOST|SERVER_PORT) [ -n "${!key:-}" ] || export "$key=${value//\"/}" ;;
    esac
  done < /etc/environment
fi

mkdir -p "$DEPLOY_DIR"
cp "$SRC_COMPOSE" "$COMPOSE_FILE"

set_tag() {
  # Point the service at the pushed image and drop the local build section,
  # so the VM always runs exactly what CI built.
  sed -i -E \
    -e "s#^([[:space:]]*)image:.*#\1image: ${IMAGE}:$1#" \
    -e '/^[[:space:]]*build:/d' \
    "$COMPOSE_FILE"
  log "docker-compose.yml now uses $(grep -E '^[[:space:]]*image:' "$COMPOSE_FILE" | xargs)"
}

compose() { docker compose -p "$APP_NAME" -f "$COMPOSE_FILE" "$@"; }

healthy() {
  local deadline=$((SECONDS + HEALTH_TIMEOUT))
  while [ $SECONDS -lt $deadline ]; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$APP_NAME" 2>/dev/null)" = "true" ] &&
       { [ -z "${HEALTH_CMD:-}" ] || bash -c "$HEALTH_CMD" >/dev/null 2>&1; }; then
      return 0
    fi
    sleep 3
  done
  return 1
}

deploy() {
  # Chained with && because `set -e` is ignored inside an `if` condition
  set_tag "$1" && compose pull && compose up -d --remove-orphans
}

# Shared network used by client and server (created once, outside Compose)
docker network inspect filenet >/dev/null 2>&1 || docker network create filenet >/dev/null

# A container with the same name started earlier by hand (for example by
# `docker compose up --build` in another folder) belongs to another Compose
# project and would block the new one. Named volumes keep the data.
owner=$(docker inspect -f '{{ index .Config.Labels "com.docker.compose.project" }}' "$APP_NAME" 2>/dev/null || true)
if docker inspect "$APP_NAME" >/dev/null 2>&1 && [ "$owner" != "$APP_NAME" ]; then
  log "Removing old '$APP_NAME' container from project '${owner:-none}'"
  docker rm -f "$APP_NAME" >/dev/null
fi

log "Deploying ${IMAGE}:${IMAGE_TAG}"
if deploy "$IMAGE_TAG" && healthy; then
  echo "$IMAGE_TAG" > "$LAST_GOOD"
  docker image prune -f >/dev/null || true
  log "Deployed ${IMAGE}:${IMAGE_TAG}"
  exit 0
fi

log "Health check failed for ${IMAGE_TAG}"
docker logs --tail 50 "$APP_NAME" 2>&1 || true
if [ -s "$LAST_GOOD" ] && [ "$(cat "$LAST_GOOD")" != "$IMAGE_TAG" ]; then
  prev=$(cat "$LAST_GOOD")
  log "Rolling back to ${prev}"
  deploy "$prev" && healthy && log "Rolled back to ${prev}"
fi
exit 1
