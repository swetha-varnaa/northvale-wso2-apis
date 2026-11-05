// MUF financing decision: a durable workflow whose rules are read from Joget at run time.
// Steps: 1 read application, 2 read rule set in force, 3 knock-outs DT-01, 4 duplicates DT-03,
// 5 scorecard DT-04, 6 grade DT-05, 7 route DT-06 (deciding row recorded), 8 write decision,
// 9 auto-reject / auto-approve branch, 10 approvers DT-08 minus exclusions, 11 human task at the
// level with a deadline, 12 escalation DT-10 on timeout or ESCALATE, 13 final status write-back,
// 14 mail the outcome.
import ballerina/workflow;

type MufInput record {|
    string applicationId;
    int deadlineSeconds = 120;
|};

# The approver's decision from the Joget inbox.
#
# + action - APPROVE, REJECT, RETURN or ESCALATE
# + comment - Required for everything but APPROVE
type MufDecision record {|
    string action;
    string? comment = ();
|};

@workflow:Workflow
function mufApplication(workflow:Context ctx, MufInput input) returns json|error {
    string id = input.applicationId;
    map<json> app = check ctx->callActivity(readApplication, {"applicationId": id});
    string submitted = opt(app, "submitted");
    map<json> rs = check ctx->callActivity(readRuleSet, {"submitted": submitted});
    string version = (check rs.version).toString();
    map<json> facts = app.clone();
    json[] audit = [];

    map<json> ko = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-01", "facts": facts});
    facts["knockout_count"] = check rowCount(ko);
    audit.push(ko);

    map<json> dup = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-03", "facts": facts});
    facts["dup_flag"] = check rowCount(dup) > 0 ? "yes" : "no";
    audit.push(dup);

    map<json> sc = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-04", "facts": facts});
    facts["score"] = check sc.sum;
    audit.push(sc);

    map<json> gr = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-05", "facts": facts});
    facts["grade"] = check firstOut(gr, "grade");
    audit.push(gr);

    map<json> rt = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-06", "facts": facts});
    string outcome = (check firstOut(rt, "outcome")).toString();
    json decidingRow = check firstRow(rt);
    audit.push(rt);

    map<json> decision = {status: "DECIDED", route: outcome, rule_version: version, deciding_table: "DT-06",
        deciding_row: decidingRow, score: check facts.score, grade: check facts.grade,
        knockout_count: check facts.knockout_count, dup_flag: check facts.dup_flag, audit};
    json _ = check ctx->callActivity(writeMufStatus, {"applicationId": id, "update": decision});

    if outcome == "Auto reject" || outcome == "T0" {
        string status = outcome == "T0" ? "APPROVED" : "REJECTED";
        json _ = check ctx->callActivity(writeMufStatus, {"applicationId": id,
            "update": {status, decided_by: "rules", route_level: outcome, rule_version: version, deciding_row: decidingRow, wf_run_id: check ctx.getWorkflowId()}});
        json _ = check ctx->callActivity(notify, {"to": opt(app, "preparer"),
            "subject": string `${id}: ${status} by rules`, "body": string `Route ${outcome}, ${version} DT-06 row ${decidingRow.toString()}.`});
        return {applicationId: id, status, route: outcome, rule_version: version, deciding_row: decidingRow};
    }

    string level = outcome;
    json exJson = app["excluded_users"];
    string[] excluded = exJson is json[] ? check exJson.cloneWithType() : [];
    excluded.push(opt(app, "preparer"));
    while true {
        facts["route_level"] = level;
        map<json> ap = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-08", "facts": facts});
        string[] approvers = [];
        json[] apOuts = check outsOf(ap);
        foreach json o in apOuts {
            string u = (check o.username).toString();
            if excluded.indexOf(u) is () {
                approvers.push(u);
            }
        }
        if approvers.length() == 0 {
            json _ = check ctx->callActivity(writeMufStatus, {"applicationId": id,
                "update": {status: "ERROR_NO_APPROVER", route_level: level, rule_version: version}});
            return {applicationId: id, status: "ERROR_NO_APPROVER", route_level: level};
        }
        json _ = check ctx->callActivity(writeMufStatus, {"applicationId": id,
            "update": {status: string `PENDING_${level}`, route_level: level, approvers: approvers,
                approver_rows: check ap.rows, rule_version: version}});
        [string, string...] people = [approvers[0], ...approvers.slice(1)];
        map<json> taskInput = {applicationId: id, routeLevel: level, amount: opt(app, "amount"),
            grade: check facts.grade, score: check facts.score, ruleVersion: version, decidingRow: decidingRow};
        workflow:Duration deadline = {seconds: <decimal>input.deadlineSeconds};
        string title = string `MUF ${id} - ${(app["applicant"] ?: "").toString()}`;
        string taskName;
        MufDecision|workflow:HumanTaskError d;
        if level == "T1" {
            taskName = "approveT1";
            d = ctx->awaitHumanTask("approveT1", taskInput, userRoles = (), users = people, administratorRoles = "WORKFLOW_ADMIN", title = title, timeout = deadline);
        } else if level == "T2" {
            taskName = "approveT2";
            d = ctx->awaitHumanTask("approveT2", taskInput, userRoles = (), users = people, administratorRoles = "WORKFLOW_ADMIN", title = title, timeout = deadline);
        } else {
            taskName = "approveT3";
            // T3 has no level above it: no deadline, the task waits for the division head.
            d = ctx->awaitHumanTask("approveT3", taskInput, userRoles = (), users = people, administratorRoles = "WORKFLOW_ADMIN", title = title);
        }
        string action;
        string? comment = ();
        string decidedBy = "deadline";
        if d is workflow:HumanTaskTimeoutError {
            action = "ESCALATE";
            comment = string `No decision at ${level} within ${input.deadlineSeconds} seconds`;
        } else if d is MufDecision {
            action = d.action;
            comment = d.comment;
            decidedBy = ctx.lastHumanTaskCompletion(taskName)?.completedBy ?: "unknown";
        } else {
            return d;
        }
        if action == "ESCALATE" {
            map<json> nx = check ctx->callActivity(runDecisionTable, {"ruleSet": rs, "tableId": "DT-10", "facts": facts});
            string next = (check firstOut(nx, "route_level")).toString();
            json _ = check ctx->callActivity(notify, {"to": opt(app, "preparer"),
                "subject": string `${id}: escalated ${level} to ${next}`, "body": comment ?: ""});
            level = next;
            continue;
        }
        string status = action == "APPROVE" ? "APPROVED" : action == "REJECT" ? "REJECTED" : "RETURNED";
        map<json> fin = {status, decided_by: decidedBy, route_level: level, comment, rule_version: version,
            deciding_row: decidingRow};
        json _ = check ctx->callActivity(writeMufStatus, {"applicationId": id, "update": fin});
        json _ = check ctx->callActivity(notify, {"to": opt(app, "preparer"),
            "subject": string `${id}: ${status} at ${level} by ${decidedBy}`, "body": comment ?: ""});
        return {applicationId: id, status, route_level: level, decided_by: decidedBy, rule_version: version,
            deciding_row: decidingRow};
    }
}
