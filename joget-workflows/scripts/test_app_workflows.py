"""Runs each app workflow end to end through WSO2's Management API, acting as the Joget inbox would.
Usage: python3 scripts/test_app_workflows.py [base_url]. Reads the API key from ~/vexa-system/.secrets/env."""
import json, os, sys, time, urllib.request, urllib.error
BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8234/workflow"
KEY = [l.split("=", 1)[1].strip() for l in open(os.path.expanduser("~/vexa-system/.secrets/env")) if l.startswith("WSO2_WORKFLOW_MGMT_API_KEY=")][0]
RUN = time.strftime("%H%M%S")

def call(method, path, body=None, user="wf.admin", roles="WORKFLOW_ADMIN"):
    req = urllib.request.Request(BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"x-api-key": KEY, "Content-Type": "application/json", "x-user-id": user, "x-user-roles": roles})
    try:
        with urllib.request.urlopen(req) as r: return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b"null")

def task(wid, name):
    time.sleep(2)
    s, page = call("GET", "/human-tasks?status=PENDING")
    for t in page["items"]:
        if t["parentWorkflowId"] == wid and t["taskName"].endswith("." + name): return t["taskId"]
    raise SystemExit(f"FAIL {wid}: no pending task {name}")

def act(wid, name, user, roles, result):
    s, b = call("POST", f"/human-tasks/{task(wid, name)}/complete", {"result": result}, user, roles)
    print(f"   {name} by {user} ({roles}) -> {s}")

def start(wtype, rec, requester):
    wid = f"{wtype}-{rec}-{RUN}"
    s, b = call("POST", "/workflows", {"workflowType": wtype, "workflowId": wid, "input": {"recordId": rec, "requester": requester}})
    print(f"{wtype}: start {s} {wid}"); return wid

def result(wid):
    time.sleep(2); s, b = call("GET", f"/workflows/{wid}"); print(f"   result {b.get('status')} {json.dumps(b.get('result'))}")

w = start("bizOnboardingApproval", "BO-1", "ro.01")
act(w, "managerReview", "mgr.01", "MANAGER", {"decision": "Return", "comment": "missing trade licence"})
act(w, "officerFix", "ro.01", "RELATIONSHIP_OFFICER", {"comment": "licence attached"})
act(w, "managerReview", "mgr.01", "MANAGER", {"decision": "Approve"}); result(w)
w = start("wso2DeskApproval", "DESK-1", "dev.01")
act(w, "platformReview", "rev.01", "PLATFORM_REVIEWER", {"decision": "Approved"})
act(w, "raiseInChoreo", "dev.01", "REQUESTER", {"comment": "raised"}); result(w)
w = start("wso2HrLeaveApproval", "LV-1", "emp.01")
s, b = call("POST", f"/human-tasks/{task(w, 'leaveManagerReview')}/complete", {"result": {"decision": "Approve"}}, "emp.01", "MANAGER")
print(f"   self-approval by emp.01 -> {s} (expect 403)")
act(w, "leaveManagerReview", "mgr.01", "MANAGER", {"decision": "Return", "comment": "dates overlap"})
act(w, "requesterFix", "emp.01", "EMPLOYEE", {"comment": "dates moved"})
act(w, "leaveManagerReview", "mgr.01", "MANAGER", {"decision": "Approve"}); result(w)
w = start("wso2LoanApproval", "LN-1", "cust.01")
act(w, "underwriting", "uw.01", "UNDERWRITER", {"decision": "Request info", "comment": "send payslips"})
act(w, "provideInfo", "cust.01", "APPLICANT", {"comment": "uploaded"})
act(w, "underwriting", "uw.01", "UNDERWRITER", {"decision": "Approve"}); result(w)
w = start("wso2OnboardingApproval", "ONB-1", "hr.01")
act(w, "hrPreparation", "hr.01", "HR", {})
act(w, "itSetup", "it.01", "IT", {})
act(w, "managerSignoff", "hm.01", "HIRING_MANAGER", {"decision": "Return", "comment": "no laptop"})
act(w, "itSetup", "it.01", "IT", {})
act(w, "managerSignoff", "hm.01", "HIRING_MANAGER", {"decision": "Sign off"}); result(w)
