#!/usr/bin/env bash
# Starts Temporal, Mailpit and the Joget workflows (with WSO2's Management API on 8234) on this Mac.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUNTIME="${RUNTIME_DIR:-/Users/varnaa/joget-dev/poc-apps/wso2-agents-workflow/runtime}"
export JAVA_HOME="${JAVA_HOME_BAL:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}"
mkdir -p "$RUNTIME"
up() { nc -z localhost "$1" >/dev/null 2>&1; }

if up 7233; then echo "Temporal already on 7233"; else
  nohup temporal server start-dev --db-filename "$RUNTIME/temporal.db" --ui-port 8233 > "$RUNTIME/temporal.log" 2>&1 &
  sleep 5; up 7233 && echo "Temporal started: 7233, UI http://localhost:8233"; fi
if up 1026; then echo "Mailpit already on 1026"; else
  nohup mailpit --smtp 127.0.0.1:1026 --listen 127.0.0.1:8026 --smtp-auth-accept-any --smtp-auth-allow-insecure > "$RUNTIME/mailpit.log" 2>&1 &
  sleep 2; up 1026 && echo "Mailpit started: SMTP 1026, UI http://localhost:8026"; fi

cd "$HERE"
if [ ! -f Config.toml ]; then
  key=$(grep '^WSO2_WORKFLOW_MGMT_API_KEY=' "$HOME/vexa-system/.secrets/env" | cut -d= -f2)
  [ -n "$key" ] || { echo "WSO2_WORKFLOW_MGMT_API_KEY missing from ~/vexa-system/.secrets/env"; exit 1; }
  sed "s|^apiKeyValue = \"\"|apiKeyValue = \"$key\"|" Config.example.toml > Config.toml
  echo "Config.toml written from Config.example.toml"
fi
[ -f target/bin/joget_workflows.jar ] || bal build
if up 8234; then echo "Workflows already on 8234"; else
  # Run a copy, so a later `bal build` cannot replace the jar under the running process.
  cp target/bin/joget_workflows.jar "$RUNTIME/joget_workflows.jar"
  nohup "$JAVA_HOME/bin/java" -jar "$RUNTIME/joget_workflows.jar" > "$RUNTIME/joget-workflows.log" 2>&1 &
  sleep 10; up 8234 && echo "Workflows started: Management API http://localhost:8234/workflow, Joget stub http://localhost:8099/joget-stub"; fi
up 8234 || { echo "Workflows did not start; see $RUNTIME/joget-workflows.log"; exit 1; }
