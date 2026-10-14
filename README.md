---
tags: [wso2, apis, northvale, choreo]
---
# Northvale Bank mock APIs

Four small mock services for the Northvale Bank WSO2 showcase. Each folder is one Choreo
Service component. They hold demo data only. Answers are deterministic, so a demo gives the
same result every time. There is no auth inside the services; the Choreo gateway applies OAuth2.

| Service | Joget app | What it answers |
|---|---|---|
| `kyb-screening` | Business Account Opening | Who the company is (registry) and whether it is on a sanctions, PEP or adverse-media list |
| `credit-bureau` | Loan Origination | Credit score, band, exposure and an approve / review / decline recommendation |
| `identity-provisioning` | Onboarding | Creates a joiner's accounts in email, core banking, CRM and VPN; disables them on exit |
| `workforce-calendar` | HR Leave | The real cost of a leave request: working days, UAE holidays, team coverage, payroll effect |
| `fx-rates` | none (Choreo subscription demo) | AED exchange rates |
| `branch-locator` | none (Choreo subscription demo) | Branch and ATM finder |
| `card-status` | none (Choreo subscription demo) | Card status by last four digits |

The exact request and response each Joget connector uses is in
`/Users/varnaa/joget-dev/poc-apps/wso2-showcase/apis/api-contracts.md`.

## Demo levers

- **KYB:** CR number starting with `7` gives HIT, `5` gives REVIEW, anything else CLEAR. `0` gives a registry 404. `9` gives a SUSPENDED company.
- **Credit:** score comes from a hash of `nationalIdOrCr`. Try several ids to find the band you want; the same id always returns the same band.
- **Provisioning:** POST returns `IN_PROGRESS`; the first GET returns `COMPLETED`; DELETE disables everything.
- **Workforce:** 30 Nov to 4 Dec 2026 shows three National Day holidays inside the range. Dates must be in 2026.

Screening results, credit reports and provisioning requests are kept in memory. A restart or a
second replica loses them, so a GET after a redeploy returns 404. Run one replica for the demo.

## Run locally

Node 20, no dependencies.

```
cd kyb-screening        # or any service folder
npm test                # node:test suite
PORT=18080 npm start    # default port is 8080; a local Joget Tomcat may already hold 8080
curl localhost:18080/health
```


`src/http.js` in each service is a copy of `_shared/http.js`. Edit the shared file, then run
`node scripts/sync-shared.js`.

## Deploy on Choreo

Create one **Service** component per row, all from this repository.

| Component | Type | Build preset | Directory path | Port | Endpoint name | API to publish |
|---|---|---|---|---|---|---|
| Northvale KYB Screening | Service | NodeJS buildpack (Node 20) | `/kyb-screening` | 8080 | `kyb-screening-api` | Northvale KYB Screening API 1.0.0 |
| Northvale Credit Bureau | Service | NodeJS buildpack (Node 20) | `/credit-bureau` | 8080 | `credit-bureau-api` | Northvale Credit Bureau API 1.0.0 |
| Northvale Identity Provisioning | Service | NodeJS buildpack (Node 20) | `/identity-provisioning` | 8080 | `identity-provisioning-api` | Northvale Identity Provisioning API 1.0.0 |
| Northvale Workforce Calendar | Service | NodeJS buildpack (Node 20) | `/workforce-calendar` | 8080 | `workforce-calendar-api` | Northvale Workforce Calendar API 1.0.0 |

Each folder carries `.choreo/component.yaml` (schemaVersion 1.2) with one REST endpoint,
base path `/`, Public visibility, and `schemaFilePath: openapi.yaml`. The schema path is relative to the component directory.
Format reference: https://wso2.com/choreo/docs/develop-components/manage-component-source-configurations/
(endpoint attributes: https://wso2.com/choreo/docs/develop-components/configure-endpoints-body/).

After deploy, publish each endpoint to the Developer Portal, subscribe the Joget application,
and use the client-credentials token on calls. Health check path for every service: `/health`.
