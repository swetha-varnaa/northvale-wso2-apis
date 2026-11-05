---
tags: [wso2, migration, joget-workflows, runbook]
---
# Moving the Joget workflows from this Mac to WSO2 Cloud

## Position (5 Nov 2026)
Everything runs on V's Mac: Temporal, WSO2's workflow Management API, the MUF workflow, five app workflows and Mailpit. The move needs three things we do not have yet: a Temporal endpoint with a key, a place to host this runtime that Joget Cloud can reach over HTTPS, and the Joget API Builder keys on the target Joget.

## One command
With the Temporal keys and the hosting in hand:
1. `cp migration.env.example migration.env` and replace every `CHANGE_ME` value.
2. Add the secrets to `~/vexa-system/.secrets/env` under the names `migration.env` gives (`TEMPORAL_CLOUD_API_KEY`, `WSO2_WORKFLOW_MGMT_API_KEY`, `JOGET_MUF_API_ID`, `JOGET_MUF_API_KEY` and `JOGET_<APP>_API_ID` / `_API_KEY` per app (in `wso2-joget-api.env`), `WORKFLOW_SMTP_PASSWORD`).
3. `./check-migration-readiness.sh` until it prints `READY`.
4. `./migrate-to-wso2-cloud.sh` (dry run: shows the cloud config, secrets masked), then `./migrate-to-wso2-cloud.sh --apply`.

`--apply` writes `Config.cloud.toml` (git-ignored), runs the readiness check, and starts the runtime against the cloud Temporal with the local Joget stand-in switched off.

## What is not verified
| Item | Status | Source |
|---|---|---|
| Durable workflows hosted on WSO2 Cloud | Not available today | github.com/wso2/docs-integrator/pull/870 |
| Our workflow component on Devant | Shown as "Not Supported" (31 Oct); build failed | Devant console, component zz-showcase-limit-workflow |
| WSO2 managed Temporal | Promised around 10 Nov; URL, namespace and key format unknown | WSO2, by email |
| `mode = "CLOUD"` with `authApiKey` against that Temporal | Config keys exist in ballerina/workflow 1.0.2; never run by us | module config.bal |
| Running two runtimes on one task queue | Not tested. Stop the laptop runtime before `--apply` points at the same queue | Temporal model, inference |
| Runs started on the laptop | They stay in the laptop's `temporal.db`. They do not move to the cloud Temporal. Finish or terminate them first | Temporal dev server, local file |

## Joget values to change after the move
1. API Connector "WSO2 workflow" base URL: `http://localhost:8234/workflow` → the hosted `MGMT_PUBLIC_URL`.
2. API Connector `x-api-key` value: the value of `WSO2_WORKFLOW_MGMT_API_KEY`.
3. The API Builder `api_id` / `api_key` the workflows use, on the target Joget, saved as `JOGET_MUF_*` and `JOGET_<APP>_*` (WSO2DESK, WSO2HRLEAVE, WSO2LOAN, WSO2ONBOARDING, BIZONBOARDING).
4. Any Joget form or row action that starts a run keeps the same body; only the base URL changes.

## Local start and stop
- `./start-everything-locally.sh`: Temporal 7233 (UI 8233), Mailpit SMTP 1026 (UI 8026), Management API 8234, Joget stand-in 8099.
- `./stop-everything.sh`. Run history stays in `wso2-agents-workflow/runtime/temporal.db`.
