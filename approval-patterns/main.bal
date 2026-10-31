// Capability tests for WSO2 Integrator durable workflows: multi-level approval with the
// four-eyes rule, parallel approvals, deadline escalation, and role checks on completion.
import ballerina/http;
import ballerina/workflow;
import ballerina/workflow.management;

type Req record {|
    string requestId;
    decimal amount;
|};

type Decision record {|
    boolean approved;
    string? comment;
|};

type ReviewIn record {|
    string requestId;
    string role;
|};

// Pattern 1: two levels, one after another. Level two may not be done by the level-one approver.
@workflow:Workflow
function twoLevel(workflow:Context ctx, Req input) returns json|error {
    Decision d1 = check ctx->awaitHumanTask("levelOne", {requestId: input.requestId, amount: input.amount.toString()},
            userRoles = "RISK_MANAGER", title = "Level 1 approval");
    if !d1.approved {
        return {status: "REJECTED_AT_LEVEL_1"};
    }
    workflow:HumanTaskCompletion? who = ctx.lastHumanTaskCompletion("levelOne");
    string firstApprover = who?.completedBy ?: "unknown";
    Decision d2 = check ctx->awaitHumanTask("levelTwo",
            {requestId: input.requestId, amount: input.amount.toString(), levelOneApprover: firstApprover},
            userRoles = ["RISK_MANAGER", "CREDIT_COMMITTEE"], excludedUsers = firstApprover,
            title = "Level 2 approval");
    workflow:HumanTaskCompletion? who2 = ctx.lastHumanTaskCompletion("levelTwo");
    return {status: d2.approved ? "APPROVED" : "REJECTED_AT_LEVEL_2", levelOne: firstApprover,
            levelTwo: who2?.completedBy};
}

// Pattern 2: two approvals at the same time, each its own child workflow; wait for both.
@workflow:Workflow
function oneReview(workflow:Context ctx, ReviewIn input) returns Decision|error {
    return ctx->awaitHumanTask("parallelReview", {requestId: input.requestId, reviewerRole: input.role},
            userRoles = input.role, title = string `${input.role} review`);
}

@workflow:Workflow
function parallelReviews(workflow:Context ctx, Req input) returns json|error {
    string risk = check ctx->runChildWorkflow(oneReview, {requestId: input.requestId, role: "RISK_MANAGER"});
    string compliance = check ctx->runChildWorkflow(oneReview, {requestId: input.requestId, role: "COMPLIANCE"});
    Decision r = check ctx->waitForChildWorkflow(risk);
    Decision c = check ctx->waitForChildWorkflow(compliance);
    return {status: (r.approved && c.approved) ? "APPROVED" : "REJECTED", risk: r.approved, compliance: c.approved,
            riskChild: risk, complianceChild: compliance};
}

// Pattern 3: deadline. If nobody decides within 20 seconds, the task escalates to HEAD_OF_RISK.
@workflow:Workflow
function withDeadline(workflow:Context ctx, Req input) returns json|error {
    Decision|workflow:HumanTaskError first = ctx->awaitHumanTask("firstLine", {requestId: input.requestId},
            userRoles = "RISK_MANAGER", title = "Decide within 20 seconds", timeout = {seconds: 20});
    if first is Decision {
        return {status: first.approved ? "APPROVED" : "REJECTED", decidedAt: "first line"};
    }
    if first is workflow:HumanTaskTimeoutError {
        Decision esc = check ctx->awaitHumanTask("escalated", {requestId: input.requestId, reason: "first line timed out"},
                userRoles = "HEAD_OF_RISK", title = "Escalated: first line missed the deadline");
        return {status: esc.approved ? "APPROVED" : "REJECTED", decidedAt: "escalation"};
    }
    return first;
}

@http:ServiceConfig {cors: {allowOrigins: ["*"]}}
service /patterns on new http:Listener(8086) {
    resource function post twoLevel(Req r) returns json|error => {workflowId: check workflow:run(twoLevel, r)};
    resource function post parallel(Req r) returns json|error => {workflowId: check workflow:run(parallelReviews, r)};
    resource function post deadline(Req r) returns json|error => {workflowId: check workflow:run(withDeadline, r)};

    resource function get tasks(string? status = "RUNNING") returns management:HumanTaskSummary[]|error {
        return management:listAllHumanTasks(status);
    }

    // The caller says who they are and which roles they hold, as the Management API does with
    // the x-user-id and x-user-roles headers.
    resource function post tasks/[string taskId]/complete(@http:Header {name: "x-user-id"} string userId,
            @http:Header {name: "x-user-roles"} string roles, Decision d) returns json|error {
        string[] parts = re `,`.split(roles);
        [string, string...] callerRoles = [parts[0], ...parts.slice(1)];
        check management:completeHumanTask(taskId, d, callerRoles, userId);
        return {status: "accepted"};
    }

    resource function get result/[string workflowId]() returns anydata|error => workflow:getWorkflowResult(workflowId);
}
