# primecrunch container image

Unofficial container image for the [primecrunch](https://primecrunch.com) client — a distributed prime number search project. This image lets you run the client as a managed container rather than a bare binary tied to a single machine or session.

Images are published to GHCR and tagged by upstream client version:

```
ghcr.io/angelobrsa/primecrunch:3.3.38
ghcr.io/angelobrsa/primecrunch:latest
```

---

## Quick start (Docker)

```bash
docker run -d \
  -e CRUNCH_EMAIL=you@example.com \
  -e CRUNCH_PASSWORD=yourpassword \
  ghcr.io/angelobrsa/primecrunch:latest
```

The container authenticates at startup and begins crunching immediately. No config files to pre-generate — just supply credentials.

Limit CPU usage with `-p`:

```bash
docker run -d \
  -e CRUNCH_EMAIL=you@example.com \
  -e CRUNCH_PASSWORD=yourpassword \
  ghcr.io/angelobrsa/primecrunch:latest \
  -p 4
```

---

## Kubernetes

Each pod authenticates independently at startup and registers as a distinct worker on your primecrunch dashboard. You can freely scale replicas — no per-pod credential management needed.

### Secret

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: primecrunch-credentials
  namespace: primecrunch
type: Opaque
stringData:
  email: you@example.com
  password: "yourpassword"  # quote if your password starts with a special character
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: primecrunch
  namespace: primecrunch
spec:
  replicas: 2
  selector:
    matchLabels:
      app: primecrunch
  template:
    metadata:
      labels:
        app: primecrunch
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
      containers:
        - name: crunch
          image: ghcr.io/angelobrsa/primecrunch:3.3.38
          args: ["-p", "2"]
          env:
            - name: CRUNCH_EMAIL
              valueFrom:
                secretKeyRef:
                  name: primecrunch-credentials
                  key: email
            - name: CRUNCH_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: primecrunch-credentials
                  key: password
            - name: POD_NAME
              valueFrom:
                fieldRef:
                  fieldPath: metadata.name
          resources:
            requests:
              cpu: "2"
              memory: 256Mi
          volumeMounts:
            - name: data
              mountPath: /data
      volumes:
        - name: data
          emptyDir: {}
```

Set `-p` to match your CPU request. Each replica gets 2 cores in the example above.

---

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `CRUNCH_EMAIL` | yes | — | Your primecrunch account email |
| `CRUNCH_PASSWORD` | yes | — | Your primecrunch account password |
| `CRUNCH_CHANNEL` | no | `stable` | Release channel: `stable`, `beta`, or `alpha` |
| `NAME_PREFIX` | no | `k8s` | Prefix for the worker name shown on your dashboard |
| `POD_NAME` | no | hostname | Set via the Kubernetes Downward API for meaningful dashboard names |
| `CRUNCH_DIR` | no | `/data` | Working directory for in-progress jobs and config |

---

## How it works

On startup the entrypoint:

1. Calls `POST https://api.primecrunch.com/v2/login` with `scope: client` to obtain a fresh access token and refresh token pair unique to this container instance
2. Generates a random UUID for `client_id` — the server treats each container as an independent worker
3. Writes a complete `crunch.yaml` to the working directory and launches the binary with `-tui=false` (no terminal dashboard in a container) and `-u=false` (auto-update disabled — version is managed via the image tag)

The client's `-u` flag (periodic update checks) **defaults to true**, but its updater replaces its own binary at `/usr/local/bin/crunch` — a path not owned by the runtime user (uid 1000), so an in-container update can only ever fail. The entrypoint therefore passes `-u=false` explicitly, and the image tag is the unit of versioning. Pass `-u=true` in `args` if you want the upstream default back.

Each pod's working directory is an `emptyDir` volume — in-progress work units are ephemeral and redownloaded on restart. Completed results are uploaded to the server before the pod ever stops, so nothing is lost.

Worker names on the dashboard follow the pattern `{NAME_PREFIX}-{POD_NAME}`, e.g. `k8s-primecrunch-7d9c8b7f4-abc12`.

---

## Updating to a new client version

Version bumps are automated. A scheduled workflow (`.github/workflows/update-check.yaml`)
runs daily and compares the `ARG VERSION` pinned in the `Dockerfile` against upstream's
release manifest:

```
https://api.primecrunch.com/v2/update
```

This is the same unauthenticated JSON the official download page reads. It is keyed
`[arch][os][channel]` and carries `filename`, `version`, `sha256`, `sha512` and `size`.

When a newer `stable` `linux/amd64` build appears, the workflow downloads the tarball,
verifies its SHA-256 against the manifest, and only then opens a pull request bumping both
`ARG VERSION` and `ARG SHA256`. Merging the PR triggers the build workflow, which publishes
the new image to GHCR.

It also corrects the pin if the version matches but the hash has drifted, and refuses to
move backwards if upstream ever serves an older version.

You can run it on demand from the Actions tab (**Check for client updates** →
*Run workflow*). To track `beta` or `alpha` instead, change `CHANNEL` in the workflow's
`env:` block.

Manual bumps still work — edit `ARG VERSION` and `ARG SHA256` together. Taking the hash
from the manifest above is safer than copying it by hand; mismatched pairs fail the build
at the `sha256sum -c` step.

---

## Building locally

```bash
docker build -t primecrunch:local .
```

---

## Credits

The primecrunch project and client binary are by [Andy](https://primecrunch.com/blog). This repo only provides the container wrapper — go sign up and contribute some primes!
