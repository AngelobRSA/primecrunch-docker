# primecrunch container image

Unofficial container image for the [primecrunch](https://primecrunch.com) client — a distributed prime number search project. This image lets you run the client as a managed container rather than a bare binary tied to a single machine or session.

Images are published to GHCR and tagged by upstream client version:

```
ghcr.io/angelobrsa/primecrunch:3.3.7
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
          image: ghcr.io/angelobrsa/primecrunch:3.3.7
          args: ["-u=false", "-p", "2"]
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

Each pod's working directory is an `emptyDir` volume — in-progress work units are ephemeral and redownloaded on restart. Completed results are uploaded to the server before the pod ever stops, so nothing is lost.

Worker names on the dashboard follow the pattern `{NAME_PREFIX}-{POD_NAME}`, e.g. `k8s-primecrunch-7d9c8b7f4-abc12`.

---

## Updating to a new client version

When the upstream primecrunch client releases a new version, bump `ARG VERSION` and `ARG SHA256` in the `Dockerfile` and push. The GitHub Actions workflow builds and publishes the new image automatically. Update your deployment's image tag to pick it up.

The SHA-256 hash for each release is listed on the [primecrunch download page](https://primecrunch.com).

---

## Building locally

```bash
docker build -t primecrunch:local .
```

---

## Credits

The primecrunch project and client binary are by [Andy](https://primecrunch.com/blog). This repo only provides the container wrapper — go sign up and contribute some primes!
