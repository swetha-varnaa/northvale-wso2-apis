// Northvale daily payment limit increase: a hand-wired WSO2 Integrator durable workflow
// with an "Await Human Task" step for the risk manager, and a WSO2 AI agent called as an activity.
// Structure follows WSO2's module-ballerina-workflow example "human-in-the-loop".
import ballerina/http;
import ballerina/io;
import ballerina/workflow;
import ballerina/workflow.management;

type LimitRequest record {|
    string requestId;
    string accountId;
    string companyName;
    decimal currentLimit;
    decimal requestedLimit;
    string reason;
|};

type LimitResult record {|
    string requestId;
    string status;
    string assessment;
    string message;
|};

# Risk manager's decision, submitted through the task inbox.
#
# + approved - true to approve the new limit
# + comment - The risk manager's comment
type RiskDecision record {|
    boolean approved;
    string? comment;
|};

configurable string anthropicApiKey = "";

final http:Client anthropicApi = check new ("https://api.anthropic.com", timeout = 60);

# Reads the account's payment history (stand-in data for the demo account).
#
# + accountId - Account identifier
# + return - Payment history summary
@workflow:Activity
function getPaymentHistory(string accountId) returns string|error {
    io:println(string `[Activity] getPaymentHistory(${accountId})`);
    return string `Account ${accountId}: 212 payments in the last 90 days, no returns, ` +
        "average USD 18,400, largest USD 47,900. Risk rating Low.";
}

# Asks the WSO2 AI agent for a short credit risk assessment.
#
# + companyName - Customer name
# + currentLimit - Current daily limit
# + requestedLimit - Requested daily limit
# + reason - Customer's reason
# + history - Payment history summary
# + return - The agent's assessment
@workflow:Activity
function assessRisk(string companyName, decimal currentLimit, decimal requestedLimit,
        string reason, string history) returns string|error {
    io:println(string `[Activity] assessRisk(${companyName})`);
    string prompt = string `Customer: ${companyName}. Current daily limit USD ${currentLimit}. ` +
        string `Requested limit USD ${requestedLimit}. Reason: ${reason}. History: ${history}`;
    json reply = check anthropicApi->post("/v1/messages", {
        model: "claude-sonnet-4-6",
        max_tokens: 400,
        system: "You are a risk analyst at Northvale Bank, corporate banking. Write a 3-sentence assessment of a daily "
            + "payment limit increase request for a risk manager. End with one line: 'Recommendation: approve' or "
            + "'Recommendation: decline'.",
        messages: [{role: "user", content: prompt}]
    }, {"x-api-key": anthropicApiKey, "anthropic-version": "2023-06-01"});
    json[] content = check (check reply.content).ensureType();
    return (check content[0].text).toString();
}

# Applies the approved limit (records the outcome for the demo).
#
# + accountId - Account identifier
# + newLimit - Approved limit
# + return - Confirmation
@workflow:Activity
function applyLimit(string accountId, decimal newLimit) returns string|error {
    io:println(string `[Activity] applyLimit(${accountId}, ${newLimit})`);
    return string `LIMIT-SET-${accountId}`;
}

@workflow:Workflow
function limitIncrease(workflow:Context ctx, LimitRequest input) returns LimitResult|error {
    string history = check ctx->callActivity(getPaymentHistory, {"accountId": input.accountId});
    string assessment = check ctx->callActivity(assessRisk, {
        "companyName": input.companyName,
        "currentLimit": input.currentLimit,
        "requestedLimit": input.requestedLimit,
        "reason": input.reason,
        "history": history
    });
    RiskDecision decision = check ctx->awaitHumanTask("approveLimitIncrease",
            {requestId: input.requestId, companyName: input.companyName,
             currentLimit: input.currentLimit.toString(), requestedLimit: input.requestedLimit.toString(),
             reason: input.reason, assessment: assessment},
            userRoles = "RISK_MANAGER",
            title = string `Approve limit USD ${input.requestedLimit} for ${input.companyName}`);
    if !decision.approved {
        return {requestId: input.requestId, status: "REJECTED", assessment,
                message: decision.comment ?: "Rejected by risk manager"};
    }
    string ref = check ctx->callActivity(applyLimit, {"accountId": input.accountId, "newLimit": input.requestedLimit});
    return {requestId: input.requestId, status: "APPROVED", assessment,
            message: string `${decision.comment ?: "Approved"} (${ref})`};
}

@http:ServiceConfig {cors: {allowOrigins: ["*"], allowMethods: ["GET", "POST", "OPTIONS"], allowHeaders: ["Content-Type"]}}
service /limits on new http:Listener(8085) {

    resource function post requests(@http:Payload LimitRequest input) returns record {|string workflowId;|}|error {
        string workflowId = check workflow:run(limitIncrease, input);
        return {workflowId};
    }

    resource function get requests/[string workflowId]/tasks() returns management:HumanTaskGroup[]|error {
        return management:listPendingHumanTasks(workflowId);
    }

    # Every waiting approval task (the risk manager's inbox across all requests).
    # + status - Optional status filter, for example RUNNING
    # + return - Task summaries
    resource function get tasks(string? status = "RUNNING") returns management:HumanTaskSummary[]|error {
        return management:listAllHumanTasks(status, taskQueue = management:getWorkflowTaskQueue());
    }

    # One task's details, including the AI assessment passed as task input.
    # + taskId - The human task ID
    # + return - Task details
    resource function get tasks/[string taskId]() returns management:HumanTaskInfo|error {
        return management:getHumanTaskInfo(taskId);
    }

    resource function post tasks/[string taskId]/complete(@http:Payload RiskDecision decision)
            returns record {|string status;|}|error {
        check workflow:completeHumanTask(taskId, decision);
        return {status: "accepted"};
    }

    resource function get requests/[string workflowId]() returns anydata|error {
        return workflow:getWorkflowResult(workflowId);
    }
}
