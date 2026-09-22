#!/usr/bin/env bash
#
# Run a local OTLP "tap": a bare OpenTelemetry Collector that accepts whatever
# Copilot sends and writes it to disk so you can read it.
#
# No Docker. Use this when you want to answer "what does Copilot actually emit?"
# before you commit to a dashboard, or to prove a managed `telemetry` setting is
# reaching a client.
#
#   ./run-tap.sh
#
# Then point a managed-settings file at http://127.0.0.1:4319 and restart the
# client. Captured signals land in ./captured/*.jsonl.
#
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${OTELCOL_VERSION:-0.161.0}"
BIN="./otelcol-contrib"

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux)  OS="linux" ;;
  *)      echo "Unsupported OS: $(uname -s). Use the Docker stack instead." >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64)  ARCH="amd64" ;;
  *)             echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

if [[ ! -x "${BIN}" ]]; then
  URL="https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/v${VERSION}/otelcol-contrib_${VERSION}_${OS}_${ARCH}.tar.gz"
  echo "Downloading otelcol-contrib ${VERSION} (${OS}/${ARCH})"
  echo "  ${URL}"
  curl -fsSL "${URL}" -o otelcol.tar.gz
  tar xzf otelcol.tar.gz otelcol-contrib
  rm -f otelcol.tar.gz
  chmod +x "${BIN}"
fi

mkdir -p captured

echo ""
echo "Listening for OTLP/HTTP on http://127.0.0.1:4319"
echo "Writing captured signals to $(pwd)/captured/"
echo ""
echo "Point a client at it, for example:"
echo '  { "telemetry": { "enabled": true, "endpoint": "http://127.0.0.1:4319", "protocol": "http/protobuf" } }'
echo ""
echo "Or, without managed settings at all, for a single CLI run:"
echo '  OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4319 copilot -p "hello"'
echo ""
echo "Ctrl-C to stop."
echo ""

exec "${BIN}" --config otelcol-tap.yaml
