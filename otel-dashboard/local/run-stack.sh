#!/usr/bin/env bash
#
# Run the whole observability stack without Docker.
#
# Grafana, Prometheus, Tempo, and the OpenTelemetry Collector all ship
# standalone binaries, so a laptop with no container runtime can still run the
# full demo. This downloads them, rewrites the Docker-compose hostnames to
# localhost, and starts everything.
#
#   ./run-stack.sh          start
#   ./run-stack.sh stop     stop
#
# Grafana ends up on http://127.0.0.1:3000 with anonymous admin, same as the
# Compose stack.
#
set -euo pipefail
cd "$(dirname "$0")"

STACK="${STACK_DIR:-$PWD/.stack}"
REPO="$(cd .. && pwd)"
PIDFILE="$STACK/pids"

OTELCOL_VERSION="${OTELCOL_VERSION:-0.161.0}"
GRAFANA_VERSION="${GRAFANA_VERSION:-11.5.1}"
PROM_VERSION="${PROM_VERSION:-3.1.0}"
TEMPO_VERSION="${TEMPO_VERSION:-2.7.0}"

case "$(uname -s)" in
  Darwin) OS=darwin ;;
  Linux)  OS=linux ;;
  *) echo "Unsupported OS. Use the Docker stack instead." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=amd64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

stop_stack() {
  [[ -f "$PIDFILE" ]] || { echo "Nothing running."; return; }
  local pids=()
  while read -r pid name; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "Stopping $name ($pid)"
      kill "$pid" 2>/dev/null || true
      pids+=("$pid")
    fi
  done < "$PIDFILE"

  # Tempo in particular can take a while to release its listener, and
  # sometimes ignores the first TERM outright. Wait, then insist, so a
  # restart does not fail on an address already in use.
  for pid in "${pids[@]:-}"; do
    [[ -n "$pid" ]] || continue
    for _ in $(seq 1 20); do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "  $pid did not exit, sending KILL"
      kill -9 "$pid" 2>/dev/null || true
    fi
  done

  rm -f "$PIDFILE"
  echo "Stopped."
}

if [[ "${1:-start}" == "stop" ]]; then
  stop_stack
  exit 0
fi

mkdir -p "$STACK"/{bin,run,logs}
cd "$STACK"

fetch() { # url, test-path
  [[ -e "$2" ]] && return 0
  echo "Downloading $(basename "$1")"
  curl -fsSL "$1" -o dl.tar.gz
  tar xzf dl.tar.gz
  rm -f dl.tar.gz
}

fetch "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${OTELCOL_VERSION}/otelcol-contrib_${OTELCOL_VERSION}_${OS}_${ARCH}.tar.gz" otelcol-contrib
fetch "https://dl.grafana.com/oss/release/grafana-${GRAFANA_VERSION}.${OS}-${ARCH}.tar.gz" "grafana-v${GRAFANA_VERSION}"
fetch "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.${OS}-${ARCH}.tar.gz" "prometheus-${PROM_VERSION}.${OS}-${ARCH}"
if [[ ! -x tempo ]]; then
  echo "Downloading tempo"
  curl -fsSL "https://github.com/grafana/tempo/releases/download/v${TEMPO_VERSION}/tempo_${TEMPO_VERSION}_${OS}_${ARCH}.tar.gz" -o tempo.tar.gz
  tar xzf tempo.tar.gz tempo && rm -f tempo.tar.gz
fi

# The committed configs address services by their Compose hostnames. Running
# bare metal, everything is on loopback instead.
mkdir -p run/grafana/provisioning/datasources run/grafana/provisioning/dashboards run/grafana/dashboards run/tempo
sed 's/endpoint: tempo:4317/endpoint: 127.0.0.1:4317/' "$REPO/otel-collector-config.yaml" > run/otelcol.yaml
sed -e 's/"collector:8889"/"127.0.0.1:8889"/' -e 's/"collector:8888"/"127.0.0.1:8888"/' "$REPO/prometheus.yml" > run/prometheus.yml
sed -e "s#/var/tempo#$STACK/run/tempo#g" -e 's#http://prometheus:9090#http://127.0.0.1:9090#' "$REPO/tempo.yaml" > run/tempo.yaml
sed -e 's#http://prometheus:9090#http://127.0.0.1:9090#' -e 's#http://tempo:3200#http://127.0.0.1:3200#' \
  "$REPO/grafana/provisioning/datasources/datasources.yaml" > run/grafana/provisioning/datasources/datasources.yaml
sed "s#/var/lib/grafana/dashboards#$STACK/run/grafana/dashboards#" \
  "$REPO/grafana/provisioning/dashboards/dashboards.yaml" > run/grafana/provisioning/dashboards/dashboards.yaml
cp "$REPO/grafana/dashboards/"*.json run/grafana/dashboards/

: > "$PIDFILE"
start() { # name, command...
  local name="$1"; shift
  "$@" > "$STACK/logs/$name.log" 2>&1 &
  echo "$! $name" >> "$PIDFILE"
  echo "  $name started (pid $!)"
}

echo "Starting:"
start tempo ./tempo -config.file=run/tempo.yaml
# Tempo refuses traffic until its ingester reports ready.
for _ in $(seq 1 30); do
  [[ "$(curl -s http://127.0.0.1:3200/ready || true)" == "ready" ]] && break
  sleep 2
done

start prometheus "./prometheus-${PROM_VERSION}.${OS}-${ARCH}/prometheus" \
  --config.file=run/prometheus.yml --storage.tsdb.path=run/prom-data \
  --web.enable-remote-write-receiver --web.listen-address=127.0.0.1:9090
start collector ./otelcol-contrib --config run/otelcol.yaml

GF_PATHS_DATA="$STACK/run/grafana-data" \
GF_PATHS_LOGS="$STACK/logs/grafana" \
GF_PATHS_PLUGINS="$STACK/run/grafana-plugins" \
GF_PATHS_PROVISIONING="$STACK/run/grafana/provisioning" \
GF_AUTH_ANONYMOUS_ENABLED=true GF_AUTH_ANONYMOUS_ORG_ROLE=Admin \
GF_AUTH_DISABLE_LOGIN_FORM=true GF_FEATURE_TOGGLES_ENABLE=traceqlEditor \
GF_SERVER_HTTP_ADDR=127.0.0.1 GF_SERVER_HTTP_PORT=3000 \
GF_ANALYTICS_REPORTING_ENABLED=false GF_ANALYTICS_CHECK_FOR_UPDATES=false \
  start grafana "$STACK/grafana-v${GRAFANA_VERSION}/bin/grafana" server \
    --homepath "$STACK/grafana-v${GRAFANA_VERSION}"

echo ""
echo "Waiting for Grafana…"
for _ in $(seq 1 45); do
  curl -sf http://127.0.0.1:3000/api/health >/dev/null 2>&1 && break
  sleep 2
done

cat <<EOF

Ready.

  Grafana      http://127.0.0.1:3000   (anonymous admin)
  Prometheus   http://127.0.0.1:9090
  Tempo        http://127.0.0.1:3200
  OTLP in      http://127.0.0.1:4319

Point a Copilot client at the OTLP endpoint, for example:

  OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4319 copilot -p "hello"

Logs are in $STACK/logs. Stop everything with:

  ./run-stack.sh stop
EOF
