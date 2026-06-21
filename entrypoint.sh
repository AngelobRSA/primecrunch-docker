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

CLIENT_ID="$(cat /proc/sys/kernel/random/uuid)"
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
echo "Authenticated as ${WORKER_NAME} (${CLIENT_ID})" >&2

exec /usr/local/bin/crunch -c "$CRUNCH_DIR" -tui=false "$@"
