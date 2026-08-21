#!/bin/sh
set -e

if [ -z "$CRUNCH_EMAIL" ] || [ -z "$CRUNCH_PASSWORD" ]; then
    echo "CRUNCH_EMAIL and CRUNCH_PASSWORD must be set" >&2
    exit 1
fi

CRUNCH_DIR="${CRUNCH_DIR:-/data}"
mkdir -p "$CRUNCH_DIR"

COOKIE_JAR="$(mktemp)"

echo "Authenticating with primecrunch..." >&2
HTTP_CODE=$(curl -sf \
    -X POST "https://api.primecrunch.com/v2/login" \
    -H "Content-Type: application/json" \
    -d "$(jq -cn --arg e "$CRUNCH_EMAIL" --arg p "$CRUNCH_PASSWORD" \
         '{email: $e, password: $p, scope: "client"}')" \
    -c "$COOKIE_JAR" \
    -o /dev/null \
    -w "%{http_code}")

if [ "$HTTP_CODE" != "200" ]; then
    echo "Login failed: HTTP ${HTTP_CODE}" >&2
    rm -f "$COOKIE_JAR"
    exit 1
fi

AT=$(awk 'BEGIN{FS="\t"} $6=="at"{print $7}' "$COOKIE_JAR")
RT=$(awk 'BEGIN{FS="\t"} $6=="rt"{print $7}' "$COOKIE_JAR")
rm -f "$COOKIE_JAR"

if [ -z "$AT" ] || [ -z "$RT" ]; then
    echo "Login response missing tokens" >&2
    exit 1
fi

# The server keys job allocation to client_id (/jobs/allocated?client_id=...), so a
# worker that returns with a fresh id abandons whatever it had checked out. Reuse the
# id already in the working directory when there is one; when the field is empty the
# client generates and saves its own on first run. Each replica has its own CRUNCH_DIR,
# so replicas still end up with distinct ids.
CLIENT_ID=""
if [ -f "$CRUNCH_DIR/crunch.yaml" ]; then
    CLIENT_ID=$(sed -n 's/^client_id:[[:space:]]*//p' "$CRUNCH_DIR/crunch.yaml" \
                | head -n1 | tr -d '"\r' | tr -d "'")
fi

WORKER_NAME="${NAME_PREFIX:-k8s}-${POD_NAME:-$(hostname)}"

cat > "$CRUNCH_DIR/crunch.yaml" << EOF
name: ${WORKER_NAME}
at: ${AT}
rt: ${RT}
channel: ${CRUNCH_CHANNEL:-stable}
version: ""
client_revision: 1
last_update_check: ""
client_id: ${CLIENT_ID}
client_report_signature: ""
EOF

chmod 600 "$CRUNCH_DIR/crunch.yaml"
if [ -n "$CLIENT_ID" ]; then
    echo "Authenticated as ${WORKER_NAME} (reusing client_id ${CLIENT_ID})" >&2
else
    echo "Authenticated as ${WORKER_NAME} (new client_id will be generated)" >&2
fi

# Auto-update is disabled (-u defaults to true upstream). The client replaces its own
# binary at /usr/local/bin/crunch, which is not owned by the runtime user (uid 1000),
# so the update can only ever fail.
# The image tag is the unit of versioning instead. Passing -u=true in args still overrides.
exec /usr/local/bin/crunch -c "$CRUNCH_DIR" -tui=false -u=false "$@"
