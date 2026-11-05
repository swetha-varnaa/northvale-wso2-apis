#!/usr/bin/env bash
# One command for the cloud move. Dry run by default: prints the cloud config with secrets masked
# and changes nothing. With --apply: writes Config.cloud.toml (git-ignored), runs the readiness
# check, and starts this runtime against the cloud Temporal with the Joget stub off.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; cd "$HERE"
APPLY=0; [ "${1:-}" = "--apply" ] && APPLY=1
SECRETS="$HOME/vexa-system/.secrets/env"
[ -f migration.env ] || { echo "migration.env missing: copy migration.env.example and fill it"; exit 1; }
set -a; . ./migration.env; set +a
if [ $APPLY -eq 1 ] && grep -q CHANGE_ME migration.env; then echo "migration.env still has CHANGE_ME values; fill them first"; exit 1; fi
secret() { if [ $APPLY -eq 1 ]; then cat "$SECRETS" "$HOME/vexa-system/.secrets/wso2-joget-api.env" 2>/dev/null | grep "^$1=" | head -1 | cut -d= -f2-; else echo "<$1>"; fi; }

render() {
cat <<TOML
[northvale.joget_workflows]
jogetBaseUrl = "$JOGET_BASE_URL"
jogetApiId = "$(secret "$JOGET_API_ID_SECRET_NAME")"
jogetApiKey = "$(secret "$JOGET_API_KEY_SECRET_NAME")"
rulesFormat = "joget"
appsBaseUrl = "$JOGET_BASE_URL"
mufRulesPath = "$MUF_RULES_PATH"
mufRecordPath = "$MUF_RECORD_PATH"
mufStatusPath = "$MUF_STATUS_PATH"
enableJogetStub = false
enableEmail = false
smtpHost = "$SMTP_HOST"
smtpPort = $SMTP_PORT
smtpUser = "$SMTP_USER"
smtpPassword = "$(secret "$SMTP_PASSWORD_SECRET_NAME")"
smtpStartTls = $SMTP_STARTTLS

[ballerina.workflow]
mode = "$TEMPORAL_MODE"
url = "$TEMPORAL_URL"
namespace = "$TEMPORAL_NAMESPACE"
taskQueue = "$TEMPORAL_TASK_QUEUE"
authApiKey = "$(secret "$TEMPORAL_API_KEY_SECRET_NAME")"

[ballerina.workflow.management.rest]
port = $MGMT_PORT
enableBasicAuth = false
enableApiKey = true
apiKeyHeader = "x-api-key"
apiKeyValue = "$(secret "$MGMT_API_KEY_SECRET_NAME")"
trustForwardedIdentity = true

[northvale.joget_workflows.appApiIds]
$(for a in wso2Desk:WSO2DESK wso2HrLeave:WSO2HRLEAVE wso2Loan:WSO2LOAN wso2Onboarding:WSO2ONBOARDING bizOnboarding:BIZONBOARDING; do echo "${a%%:*} = \"$(secret "JOGET_${a##*:}_API_ID")\""; done)

[northvale.joget_workflows.appApiKeys]
$(for a in wso2Desk:WSO2DESK wso2HrLeave:WSO2HRLEAVE wso2Loan:WSO2LOAN wso2Onboarding:WSO2ONBOARDING bizOnboarding:BIZONBOARDING; do echo "${a%%:*} = \"$(secret "JOGET_${a##*:}_API_KEY")\""; done)
TOML
}

if [ $APPLY -eq 0 ]; then
  echo "DRY RUN. Nothing written, nothing started. Config.cloud.toml would be:"; echo; render; echo
  echo "Joget values to change after the move (by hand in the builders):"
  echo "  1. API Connector 'WSO2 workflow' base URL -> $MGMT_PUBLIC_URL"
  echo "  2. API Connector x-api-key -> the value of $MGMT_API_KEY_SECRET_NAME"
  echo "  3. API Builder keys used by the workflows -> $JOGET_API_ID_SECRET_NAME / $JOGET_API_KEY_SECRET_NAME on the target Joget"
  echo "Run with --apply to do it."; exit 0
fi
umask 077; render > Config.cloud.toml
./check-migration-readiness.sh || { echo "Readiness failed; Config.cloud.toml written, runtime not started"; exit 1; }
export JAVA_HOME="${JAVA_HOME_BAL:-/opt/homebrew/opt/openjdk/libexec/openjdk.jdk/Contents/Home}"
pkill -f joget_workflows.jar || true
cp target/bin/joget_workflows.jar ./joget_workflows.cloud.jar
BAL_CONFIG_FILES=Config.cloud.toml nohup "$JAVA_HOME/bin/java" -jar ./joget_workflows.cloud.jar > cloud-runtime.log 2>&1 &
sleep 10; nc -z localhost "$MGMT_PORT" && echo "Runtime up on $MGMT_PORT against $TEMPORAL_URL. Expose it at $MGMT_PUBLIC_URL." || { echo "Runtime did not start; see cloud-runtime.log"; exit 1; }
