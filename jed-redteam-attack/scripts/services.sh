#!/usr/bin/env bash
# Pause and resume non-JED Docker containers around a harness or vLLM run.
#
# Usage:
#   bash scripts/services.sh pause    # stop all running service containers;
#                                     # save names to .paused_containers
#   bash scripts/services.sh resume   # restart every container listed in .paused_containers
#
# "Service containers" are defined as: any container with a restart policy of
# unless-stopped or always (long-lived services, not one-shot runners).
# JED containers (images prefixed jed-) are excluded — they have no persistent
# restart policy and are never in the filtered set anyway.
#
# Containers already stopped (e.g. after a system reboot) are still written to
# the state file so resume can start them back up after the run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(dirname "$SCRIPT_DIR")"
STATE_FILE="${WORKSPACE}/.paused_containers"
OUR_IMAGE_PREFIX="jed-"

pause() {
  local services=()
  while IFS= read -r name; do
    local image
    image=$(docker inspect --format '{{.Config.Image}}' "$name" 2>/dev/null || true)
    # Skip our own JED containers
    [[ "$image" == ${OUR_IMAGE_PREFIX}* ]] && continue

    local policy
    policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$name" 2>/dev/null || true)
    if [[ "$policy" == "unless-stopped" || "$policy" == "always" ]]; then
      services+=("$name")
    fi
  done < <(docker ps -a --format '{{.Names}}')

  if [[ ${#services[@]} -eq 0 ]]; then
    echo "No non-JED service containers found — nothing to pause."
    return
  fi

  printf '%s\n' "${services[@]}" > "$STATE_FILE"
  echo "Service containers:"
  for name in "${services[@]}"; do
    if docker ps -q --filter "name=^${name}$" 2>/dev/null | grep -q .; then
      echo "  Stopping: $name"
      docker stop --time=60 "$name" > /dev/null
    else
      echo "  Already stopped: $name (will be started on resume)"
    fi
  done
  echo "Saved container list to ${STATE_FILE}"
}

resume() {
  if [[ ! -f "$STATE_FILE" ]]; then
    echo "No saved container list found at ${STATE_FILE} — nothing to resume."
    return
  fi

  echo "Starting service containers:"
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if docker start "$name" > /dev/null 2>&1; then
      echo "  Started: $name"
    else
      echo "  Skipped: $name (start failed — container may be stale or image missing)"
    fi
  done < "$STATE_FILE"

  rm "$STATE_FILE"
  echo "Done. Removed ${STATE_FILE}"
}

case "${1:-}" in
  pause)  pause  ;;
  resume) resume ;;
  *)
    echo "Usage: $0 {pause|resume}"
    exit 1
    ;;
esac
