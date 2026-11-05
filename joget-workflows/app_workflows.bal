// The approval processes of the Joget apps, rebuilt as WSO2 durable workflows.
// Source of each flow: the app's package.xpdl in sync/cloud-exports/APP_<app>-1.jwa (5 Nov 2026).
// wso2AppCentre has no process in its export, so it has no workflow here.
// Every run starts with {recordId, requester}; the Joget record holds the form data, the workflow
// holds the case state and writes each status back to the record.
import ballerina/workflow;

type AppCase record {|
    string recordId;
    string requester;
    int deadlineSeconds = 86400;
    string? reference = ();
|};

# A reviewer's decision, sent from the Joget inbox as the task result.
#
# + decision - The app's own decision value (Approve, Reject, Return, Decline, Request info, Sign off)
# + comment - Free text
type Review record {|
    string decision;
    string? comment = ();
|};

# A requester's answer to a returned case.
#
# + comment - What was changed or added
type Resubmission record {|
    string? comment = ();
|};

// Inbox title: "<App label> <reference>" when Joget sends a reference. Runs started without one keep
// the exact title they were started with, so their replay is unchanged.
function taskTitle(AppCase c, string label, string withoutReference) returns string {
    string? ref = c.reference;
    return ref is string && ref.trim() != "" ? string `${label} ${ref}` : withoutReference;
}

function who(workflow:Context ctx, string taskName) returns string =>
    ctx.lastHumanTaskCompletion(taskName)?.completedBy ?: "unknown";

// bizOnboarding, "Business Account Opening": submit, KYC screening, Manager review
// (Approve opens the account; anything else returns it to the Relationship Officer, then screening again).
@workflow:Workflow
function bizOnboardingApproval(workflow:Context ctx, AppCase c) returns json|error {
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "bizOnboarding", "recordId": c.recordId, "update": {status: "Submitted"}});
    while true {
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "bizOnboarding", "recordId": c.recordId, "update": {status: "KYC screening"}});
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "bizOnboarding", "recordId": c.recordId, "update": {status: "Manager review"}});
        Review|workflow:HumanTaskError r = ctx->awaitHumanTask("managerReview", {recordId: c.recordId, requester: c.requester},
            userRoles = "MANAGER", excludedUsers = c.requester, administratorRoles = "WORKFLOW_ADMIN",
            title = taskTitle(c, "Account opening", string `Account opening ${c.recordId}: manager review`), timeout = {seconds: <decimal>c.deadlineSeconds});
        Review d;
        if r is workflow:HumanTaskTimeoutError {
            d = check ctx->awaitHumanTask("headReview", {recordId: c.recordId, reason: "manager deadline passed"},
                userRoles = "HEAD_OF_BRANCH", administratorRoles = "WORKFLOW_ADMIN",
                title = taskTitle(c, "Account opening", string `Escalated: account opening ${c.recordId}`));
        } else if r is Review {
            d = r;
        } else {
            return r;
        }
        if d.decision == "Approve" {
            json _ = check ctx->callActivity(writeAppStatus, {"appId": "bizOnboarding", "recordId": c.recordId,
                "update": {status: "Account opened", decision: d.decision, comment: d.comment}});
            string _ = check ctx->callActivity(notify, {"to": c.requester, "subject": string `${c.recordId}: account opened`, "body": d.comment ?: ""});
            return {recordId: c.recordId, status: "Account opened"};
        }
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "bizOnboarding", "recordId": c.recordId,
            "update": {status: "Returned", decision: d.decision, comment: d.comment}});
        Resubmission _ = check ctx->awaitHumanTask("officerFix", {recordId: c.recordId, comment: d.comment},
            userRoles = (), users = c.requester, administratorRoles = "WORKFLOW_ADMIN",
            title = taskTitle(c, "Account opening", string `Fix returned application ${c.recordId}`));
    }
}

// wso2Desk, "Platform Request Review": submit, Platform Reviewer review; Approved goes to the
// requester to raise it in Choreo, then waits for Choreo; anything else is rejected.
@workflow:Workflow
function wso2DeskApproval(workflow:Context ctx, AppCase c) returns json|error {
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Desk", "recordId": c.recordId, "update": {status: "Submitted"}});
    Review d = check ctx->awaitHumanTask("platformReview", {recordId: c.recordId, requester: c.requester},
        userRoles = "PLATFORM_REVIEWER", excludedUsers = c.requester, administratorRoles = "WORKFLOW_ADMIN",
        title = taskTitle(c, "Platform request", string `Platform request ${c.recordId}: review`));
    if d.decision != "Approved" && d.decision != "Approve" {
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Desk", "recordId": c.recordId,
            "update": {status: "Rejected", reviewer: who(ctx, "platformReview"), comment: d.comment}});
        string _ = check ctx->callActivity(notify, {"to": c.requester, "subject": string `${c.recordId}: rejected`, "body": d.comment ?: ""});
        return {recordId: c.recordId, status: "Rejected"};
    }
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Desk", "recordId": c.recordId,
        "update": {status: "Ready to raise", reviewer: who(ctx, "platformReview"), comment: d.comment}});
    Resubmission _ = check ctx->awaitHumanTask("raiseInChoreo", {recordId: c.recordId},
        userRoles = (), users = c.requester, administratorRoles = "WORKFLOW_ADMIN",
        title = taskTitle(c, "Platform request", string `Raise ${c.recordId} in Choreo`));
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Desk", "recordId": c.recordId, "update": {status: "Waiting for Choreo approval"}});
    return {recordId: c.recordId, status: "Waiting for Choreo approval"};
}

// wso2HrLeave, "Leave approval": submit and balance check, Manager review with a deadline
// (escalates to HR), Approve / Reject / Return; a return goes back to the employee and then to the manager.
@workflow:Workflow
function wso2HrLeaveApproval(workflow:Context ctx, AppCase c) returns json|error {
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2HrLeave", "recordId": c.recordId, "update": {status: "Submitted"}});
    while true {
        Review|workflow:HumanTaskError r = ctx->awaitHumanTask("leaveManagerReview", {recordId: c.recordId, requester: c.requester},
            userRoles = "MANAGER", excludedUsers = c.requester, administratorRoles = "WORKFLOW_ADMIN",
            title = taskTitle(c, "Leave request", string `Leave ${c.recordId}: manager review`), timeout = {seconds: <decimal>c.deadlineSeconds});
        Review d;
        if r is workflow:HumanTaskTimeoutError {
            json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2HrLeave", "recordId": c.recordId, "update": {status: "Escalated to HR"}});
            d = check ctx->awaitHumanTask("leaveHrReview", {recordId: c.recordId, reason: "manager deadline passed"},
                userRoles = "HR", excludedUsers = c.requester, administratorRoles = "WORKFLOW_ADMIN",
                title = taskTitle(c, "Leave request", string `Escalated leave ${c.recordId}`));
        } else if r is Review {
            d = r;
        } else {
            return r;
        }
        if d.decision == "Approve" || d.decision == "Reject" {
            string status = d.decision == "Approve" ? "Approved" : "Rejected";
            json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2HrLeave", "recordId": c.recordId,
                "update": {status, decision: d.decision, comment: d.comment}});
            string _ = check ctx->callActivity(notify, {"to": c.requester, "subject": string `Leave ${c.recordId}: ${status}`, "body": d.comment ?: ""});
            return {recordId: c.recordId, status};
        }
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2HrLeave", "recordId": c.recordId,
            "update": {status: "Returned", decision: d.decision, comment: d.comment}});
        Resubmission _ = check ctx->awaitHumanTask("requesterFix", {recordId: c.recordId, comment: d.comment},
            userRoles = (), users = c.requester, administratorRoles = "WORKFLOW_ADMIN", title = taskTitle(c, "Leave request", string `Fix returned leave ${c.recordId}`));
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2HrLeave", "recordId": c.recordId, "update": {status: "Resubmitted"}});
    }
}

// wso2Loan, "Loan Origination": submit, credit bureau check, Underwriter review,
// Approve / Decline / Request info; requested info goes to the applicant and back to underwriting.
@workflow:Workflow
function wso2LoanApproval(workflow:Context ctx, AppCase c) returns json|error {
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Loan", "recordId": c.recordId, "update": {status: "Submitted"}});
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Loan", "recordId": c.recordId, "update": {status: "Credit check"}});
    while true {
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Loan", "recordId": c.recordId, "update": {status: "Underwriting"}});
        Review d = check ctx->awaitHumanTask("underwriting", {recordId: c.recordId, requester: c.requester},
            userRoles = "UNDERWRITER", excludedUsers = c.requester, administratorRoles = "WORKFLOW_ADMIN",
            title = taskTitle(c, "Loan application", string `Loan ${c.recordId}: underwriting`));
        if d.decision == "Approve" || d.decision == "Decline" {
            string status = d.decision == "Approve" ? "Approved" : "Declined";
            json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Loan", "recordId": c.recordId,
                "update": {status, underwriter: who(ctx, "underwriting"), comment: d.comment}});
            string _ = check ctx->callActivity(notify, {"to": c.requester, "subject": string `Loan ${c.recordId}: ${status}`, "body": d.comment ?: ""});
            return {recordId: c.recordId, status};
        }
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Loan", "recordId": c.recordId,
            "update": {status: "More information requested", comment: d.comment}});
        Resubmission _ = check ctx->awaitHumanTask("provideInfo", {recordId: c.recordId, question: d.comment},
            userRoles = (), users = c.requester, administratorRoles = "WORKFLOW_ADMIN", title = taskTitle(c, "Loan application", string `Provide information for loan ${c.recordId}`));
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Loan", "recordId": c.recordId, "update": {status: "Information received"}});
    }
}

// wso2Onboarding, "New Joiner Onboarding": open case, HR preparation, IT setup, Hiring manager
// sign-off; anything but "Sign off" returns it to IT.
@workflow:Workflow
function wso2OnboardingApproval(workflow:Context ctx, AppCase c) returns json|error {
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Onboarding", "recordId": c.recordId, "update": {status: "Case opened"}});
    Resubmission _ = check ctx->awaitHumanTask("hrPreparation", {recordId: c.recordId},
        userRoles = "HR", administratorRoles = "WORKFLOW_ADMIN", title = taskTitle(c, "Onboarding", string `Onboarding ${c.recordId}: HR preparation`));
    json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Onboarding", "recordId": c.recordId, "update": {status: "HR done, provisioning"}});
    while true {
        Resubmission _ = check ctx->awaitHumanTask("itSetup", {recordId: c.recordId},
            userRoles = "IT", administratorRoles = "WORKFLOW_ADMIN", title = taskTitle(c, "Onboarding", string `Onboarding ${c.recordId}: IT setup`));
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Onboarding", "recordId": c.recordId, "update": {status: "IT done, waiting for sign-off"}});
        Review d = check ctx->awaitHumanTask("managerSignoff", {recordId: c.recordId},
            userRoles = "HIRING_MANAGER", administratorRoles = "WORKFLOW_ADMIN", title = taskTitle(c, "Onboarding", string `Onboarding ${c.recordId}: sign-off`));
        if d.decision == "Sign off" {
            json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Onboarding", "recordId": c.recordId,
                "update": {status: "Complete", signed_off_by: who(ctx, "managerSignoff")}});
            string _ = check ctx->callActivity(notify, {"to": c.requester, "subject": string `Onboarding ${c.recordId}: complete`, "body": ""});
            return {recordId: c.recordId, status: "Complete"};
        }
        json _ = check ctx->callActivity(writeAppStatus, {"appId": "wso2Onboarding", "recordId": c.recordId,
            "update": {status: "Returned to IT", comment: d.comment}});
    }
}
