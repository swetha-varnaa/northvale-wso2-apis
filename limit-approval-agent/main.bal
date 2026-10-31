// Northvale payment-limit approval: a durable WSO2 agent with a human approval task.
// Adapted from WSO2's module-ballerina-workflow example "agent-human-approval".
import ballerina/ai;
import ballerina/http;
import ballerina/io;
import ballerina/workflow;
import ballerina/workflow.management;

# The risk manager's decision on a limit increase.
#
# + approved - Whether the new limit is approved
# + comment - The risk manager's comment, relayed to the customer by the agent
type LimitDecision record {|
    boolean approved;
    string comment;
|};

final ai:Wso2ModelProvider limitModel = check ai:getDefaultModelProvider();

@workflow:Activity
function getCurrentLimit(string accountId) returns string|error {
    io:println(string `[activity] getCurrentLimit(${accountId})`);
    return string `Account ${accountId}: current daily payment limit USD 50,000. ` +
        "Last 90 days: 212 payments, no returns, average USD 18,400. Risk rating: Low.";
}

final workflow:DurableAgent limitAgent = check new ({
    systemPrompt: {
        role: "You are the corporate banking assistant at Northvale Bank.",
        instructions: string `Use the getCurrentLimit tool to read the customer's limit and history.
                Any increase of the daily payment limit needs risk manager approval:
                call the approveLimitIncrease tool with the account id, the requested limit,
                the customer's reason and your one-paragraph assessment of the payment history,
                then tell the customer the risk manager's decision and comment.
                When the customer says goodbye, call the endConversation tool with a short farewell.`
    },
    model: limitModel,
    activities: [getCurrentLimit],
    events: {
        chat: {request: string, response: string, cardinality: workflow:MULTI_EVENT}
    },
    humanTasks: {
        approveLimitIncrease: {
            userRoles: "RISK_MANAGER",
            resultType: LimitDecision,
            title: "Approve daily payment limit increase",
            description: "Asks a risk manager to approve a higher daily payment limit. "
                + "Pass the account id, requested limit, customer's reason and your assessment as fields."
        }
    }
});

service /limits on new http:Listener(8085, timeout = 0) {

    # Starts a new limit-request conversation.
    # + return - The agent ID used by the other resources
    resource function post 'start() returns json|error {
        string agentId = check limitAgent.run("");
        return {agentId: agentId};
    }

    # Sends a customer message and returns the agent's reply. Blocks while the
    # agent waits on the risk manager.
    # + agentId - The agent ID
    # + message - The customer's message
    # + return - The agent's reply
    resource function post [string agentId]/chat(@http:Payload string message) returns string|error {
        string token = check limitAgent.sendData(agentId, "chat", message);
        return limitAgent.waitForDataResult(agentId, token);
    }

    # Lists the conversation's pending approval tasks (the risk manager's inbox).
    # + agentId - The agent ID
    # + return - Pending human task groups
    resource function get [string agentId]/tasks() returns management:HumanTaskGroup[]|error {
        return management:listPendingHumanTasks(agentId);
    }

    # Completes a pending approval as RISK_MANAGER; the agent resumes.
    # + taskId - The human task ID
    # + decision - The decision
    # + return - A confirmation message
    resource function post tasks/[string taskId]/complete(LimitDecision decision) returns string|error {
        check management:completeHumanTask(taskId, decision, ["RISK_MANAGER"]);
        return "Task " + taskId + " completed";
    }
}
