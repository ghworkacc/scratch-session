#!/usr/bin/env bash
#
# This script dumps the system message (instructions) for a Foundry prompt
# agent across all of the available versions of the agent.
#
# Usage: ./dump_agent_prompt_history.sh <agent-uri>
#
# The agent URI is self-contained (account + project + agent), e.g.:
#   https://FOUNDRY.services.ai.azure.com/api/projects/FOUNDRY-PROJ/agents/wifi-helper-luna/endpoint/protocols/openai/responses
#
# Output: ./output/<agent-name>/<version>_prompt.md

set -euo pipefail

API_VERSION="v1"
RESOURCE="https://ai.azure.com"

# --- dependency checks -------------------------------------------------------
for dep in az curl jq; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "Error: required command '$dep' is not installed or not on PATH." >&2
    exit 1
  fi
done

# --- argument parsing --------------------------------------------------------
AGENT_URI="${1:-}"
if [ -z "$AGENT_URI" ]; then
  echo "Usage: $0 <agent-uri>" >&2
  exit 1
fi

if [[ ! "$AGENT_URI" =~ ^https://[^/]+/api/projects/[^/]+/agents/[^/]+ ]]; then
  echo "Error: '$AGENT_URI' does not look like a Foundry agent URI." >&2
  echo "Expected: https://<account>.services.ai.azure.com/api/projects/<project>/agents/<agent-name>/..." >&2
  exit 1
fi

# Extract the project (base) endpoint and the agent name from the URI.
# BASE_URL captures everything up to and including /api/projects/<project>.
# AGENT_NAME is the segment after /agents/ (the /endpoint/... tail is ignored).
if [[ "$AGENT_URI" =~ ^(https://[^/]+/api/projects/[^/]+)/agents/([^/]+) ]]; then
  BASE_URL="${BASH_REMATCH[1]}"
  AGENT_NAME="${BASH_REMATCH[2]}"
else
  echo "Error: could not parse account/project/agent from URI." >&2
  exit 1
fi

echo "Base endpoint: $BASE_URL"
echo "Agent name:    $AGENT_NAME"

# --- authentication ----------------------------------------------------------
TOKEN="$(az account get-access-token --resource "$RESOURCE" --query accessToken -o tsv)"
if [ -z "$TOKEN" ]; then
  echo "Error: failed to acquire an access token. Run 'az login' first." >&2
  exit 1
fi

# Helper: perform an authenticated GET and echo the response body.
api_get() {
  curl -sS --fail-with-body \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/json" \
    "$1"
}

# --- collect all version ids (with pagination) -------------------------------
echo "Listing versions..."
versions=()
after=""
while :; do
  url="${BASE_URL}/agents/${AGENT_NAME}/versions?api-version=${API_VERSION}&include_drafts=true"
  if [ -n "$after" ]; then
    url="${url}&after=${after}"
  fi

  if ! page="$(api_get "$url")"; then
    echo "Error: failed to list versions for '$AGENT_NAME'." >&2
    echo "$page" >&2
    exit 1
  fi

  # Response is an OpenAI-style list ({data:[...]}); fall back to {value:[...]}.
  while IFS= read -r v; do
    [ -n "$v" ] && versions+=("$v")
  done < <(echo "$page" | jq -r '(.data // .value // [])[].version')

  has_more="$(echo "$page" | jq -r '.has_more // false')"
  if [ "$has_more" = "true" ]; then
    after="$(echo "$page" | jq -r '.last_id // empty')"
    [ -n "$after" ] && continue
  fi
  break
done

if [ "${#versions[@]}" -eq 0 ]; then
  echo "No versions found for agent '$AGENT_NAME'." >&2
  exit 1
fi

echo "Found ${#versions[@]} version(s): ${versions[*]}"

# --- dump the system prompt for each version ---------------------------------
OUT_DIR="./output/${AGENT_NAME}"
mkdir -p "$OUT_DIR"

written=0
for version in "${versions[@]}"; do
  url="${BASE_URL}/agents/${AGENT_NAME}/versions/${version}?api-version=${API_VERSION}"
  if ! body="$(api_get "$url")"; then
    echo "Warning: failed to fetch version '$version'; skipping." >&2
    echo "$body" >&2
    continue
  fi

  instructions="$(echo "$body" | jq -r '.definition.instructions // empty')"

  # Zero-pad numeric versions to 3 digits so files sort naturally; leave
  # non-numeric versions (e.g. draft-<timestamp>) untouched.
  if [[ "$version" =~ ^[0-9]+$ ]]; then
    version_label="$(printf '%03d' "$version")"
  else
    version_label="$version"
  fi
  out_file="${OUT_DIR}/${version_label}_prompt.md"

  if [ -z "$instructions" ]; then
    printf '<!-- Agent %s version %s has no instructions (not a prompt agent, or empty). -->\n' \
      "$AGENT_NAME" "$version" > "$out_file"
    echo "Wrote (no instructions): $out_file"
  else
    printf '%s\n' "$instructions" > "$out_file"
    echo "Wrote: $out_file"
  fi
  written=$((written + 1))
done

echo "Done. Wrote $written file(s) to $OUT_DIR"
