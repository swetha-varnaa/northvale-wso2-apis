#!/usr/bin/env bash
# Checks that everything the cloud move needs is in place. One check per item, no waiting loops.
# Exit 0 = ready; exit 1 = at least one FAIL. UNVERIFIED lines are known open items, not failures.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
SECRETS="$HOME/vexa-system/.secrets/env"; fail=0
ok() { echo "PASS  $*"; }; bad() { echo "FAIL  $*"; fail=1; }
secret() { cat "$SECRETS" "$HOME/vexa-system/.secrets/wso2-joget-api.env" 2>/dev/null | grep "^$1=" | head -1 | cut -d= -f2-; }

[ -f migration.env ] && ok "migration.env present" || { bad "migration.env missing (copy migration.env.example)"; }
if [ -f migration.env ]; then
  set -a; . ./migration.env; set +a
  grep -q CHANGE_ME migration.env && bad "migration.env still has CHANGE_ME values: $(grep '^[A-Z_]*=.*CHANGE_ME' migration.env | cut -d= -f1 | tr '\n' ' ')" || ok "migration.env filled"
  for n in "${TEMPORAL_API_KEY_SECRET_NAME:-}" "${MGMT_API_KEY_SECRET_NAME:-}" "${JOGET_API_ID_SECRET_NAME:-}" "${JOGET_API_KEY_SECRET_NAME:-}" "${SMTP_PASSWORD_SECRET_NAME:-}"; do
    [ -z "$n" ] && continue
    [ -n "$(secret "$n")" ] && ok "secret $n present" || bad "secret $n missing from ~/vexa-system/.secrets"
  done
  for a in ${JOGET_APP_KEY_PREFIXES:-}; do
    for n in "JOGET_${a}_API_ID" "JOGET_${a}_API_KEY"; do
      [ -n "$(secret "$n")" ] && ok "secret $n present" || bad "secret $n missing from ~/vexa-system/.secrets"
    done
  done
  host="${TEMPORAL_URL%:*}"; port="${TEMPORAL_URL##*:}"
  nc -z -w 5 "$host" "$port" >/dev/null 2>&1 && ok "Temporal endpoint $TEMPORAL_URL reachable" || bad "Temporal endpoint $TEMPORAL_URL not reachable"
  code=$(curl -s -o /dev/null -w '%{http_code}' -m 10 -H "api_id: $(secret "${JOGET_API_ID_SECRET_NAME:-x}")" -H "api_key: $(secret "${JOGET_API_KEY_SECRET_NAME:-x}")" "${JOGET_BASE_URL:-}${MUF_RULES_PATH:-}")
  [ "$code" = 200 ] && ok "Joget rules endpoint answers 200" || bad "Joget rules endpoint ${JOGET_BASE_URL:-}${MUF_RULES_PATH:-} answered $code"
fi
export JAVA_HOME="${JAVA_HOME_BAL:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}"
bal build >/tmp/joget-workflows-build.log 2>&1 && ok "bal build" || bad "bal build (see /tmp/joget-workflows-build.log)"
python3 /Users/varnaa/claude-shared/skills/joget-api-connector/scripts/check_openapi_for_connector.py openapi/wso2-workflow-management.joget.oas.json >/dev/null 2>&1 && ok "Joget OpenAPI spec passes the connector check" || bad "Joget OpenAPI spec check"
../scripts/secret-scan.sh --all >/dev/null && ok "secret scan of tracked files" || bad "secret scan of tracked files"
echo "UNVERIFIED  WSO2 Cloud does not run durable workflows today (github.com/wso2/docs-integrator/pull/870)"
echo "UNVERIFIED  Devant marked our workflow component 'Not Supported' (31 Oct); hosting the runtime on WSO2 Cloud is not proven"
echo "UNVERIFIED  WSO2 managed Temporal promised around 10 Nov 2026; endpoint, namespace and key format unknown until then"
echo "UNVERIFIED  Joget Cloud must reach the runtime's Management API over HTTPS; no hosted URL exists yet"
[ $fail -eq 0 ] && echo "READY" || echo "NOT READY"
exit $fail
