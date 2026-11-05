// Activities: every call to Joget or to mail is a recorded, replay-safe step.
import ballerina/email;
import ballerina/http;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/workflow;

final http:Client joget = check new (jogetBaseUrl, timeout = 30);
final http:Client appsJoget = check new (appsBaseUrl, timeout = 30);

isolated function jogetHeaders() returns map<string> => {"api_id": jogetApiId, "api_key": jogetApiKey};

isolated function withId(string path, string id) returns string => regexp:replaceAll(re `\{id\}`, path, id);

# Reads a MUF application record from Joget.
#
# + applicationId - Record id
# + return - The record's fields
@workflow:Activity
function readApplication(string applicationId) returns map<json>|error {
    io:println(string `[Activity] readApplication(${applicationId})`);
    return joget->get(withId(mufRecordPath, applicationId), jogetHeaders());
}

# Reads all MUF rule tables from Joget and picks the rule set in force on the submission date.
#
# + submitted - Submission date, yyyy-mm-dd
# + return - The rule set in force
@workflow:Activity
function readRuleSet(string submitted) returns map<json>|error {
    io:println(string `[Activity] readRuleSet(${submitted})`);
    if rulesFormat == "joget" {
        string sep = mufRulesPath.includes("?") ? "&" : "?";
        json page = check joget->get(string `${mufRulesPath}${sep}asOf=${submitted}`, jogetHeaders());
        json[] data = check (check page.data).ensureType();
        return ruleSetFromJogetRows(data, submitted);
    }
    json all = check joget->get(mufRulesPath, jogetHeaders());
    return ruleSetFor(all, submitted);
}

# Runs one decision table and returns the rows that fired and their outputs.
#
# + ruleSet - The rule set in force
# + tableId - Table code, e.g. DT-06
# + facts - Case facts
# + return - Evaluation with the deciding row numbers
@workflow:Activity
function runDecisionTable(map<json> ruleSet, string tableId, map<json> facts) returns map<json>|error {
    map<json> tables = check (check ruleSet.tables).ensureType();
    map<json> tbl = check tables[tableId].ensureType();
    map<json> r = check evaluateTable(tbl, facts, tableId, (check ruleSet.version).toString());
    io:println(string `[Activity] ${tableId} ${(check ruleSet.version).toString()} rows ${(check r.rows).toJsonString()}`);
    return r;
}

# Writes the status and the deciding rows back to the MUF record in Joget.
#
# + applicationId - Record id
# + update - Fields to write
# + return - Joget's reply
@workflow:Activity
function writeMufStatus(string applicationId, map<json> update) returns json|error {
    // Joget's write-back form takes flat text fields only.
    map<json> body = {id: applicationId};
    foreach string k in ["status", "route_level", "rule_version", "decided_by", "comment", "wf_run_id"] {
        json v = update[k];
        if v !is () {
            body[k] = v.toString();
        }
    }
    json row = update["deciding_row"];
    if row !is () {
        body["deciding_row"] = string `DT-06 row ${row.toString()}`;
    }
    json ap = update["approvers"];
    if ap is json[] {
        body["approvers"] = string:'join(",", ...ap.map(a => a.toString()));
    }
    io:println(string `[Activity] writeMufStatus(${applicationId}) ${body.toJsonString()}`);
    return joget->post(withId(mufStatusPath, applicationId), body, jogetHeaders());
}

final readonly & map<string[]> APP_FIELDS = {
    "wso2Desk": ["status", "decision", "reviewer", "comment", "wf_run_id"],
    "wso2HrLeave": ["status", "decision", "comment", "wf_run_id"],
    "wso2Loan": ["status", "decision", "underwriter", "comment", "wf_run_id"],
    "wso2Onboarding": ["status", "signed_off_by", "comment", "wf_run_id"],
    "bizOnboarding": ["status", "decision", "comment", "wf_run_id"]
};

# Writes a status back to an app's record in Joget. The id goes in the body: Joget's form API
# updates the row with that id, and creates a new row without it.
#
# + appId - Joget app id
# + recordId - Record id
# + update - Fields to write; only the app's accepted fields are sent
# + return - Joget's reply
@workflow:Activity
function writeAppStatus(string appId, string recordId, map<json> update) returns json|error {
    string? path = appStatusPaths[appId];
    if path is () {
        return error(string `no status path configured for ${appId}`);
    }
    map<json> body = {id: recordId};
    foreach string k in APP_FIELDS[appId] ?: [] {
        json v = update[k];
        if v !is () {
            body[k] = v.toString();
        }
    }
    io:println(string `[Activity] writeAppStatus(${appId}, ${recordId}) ${body.toJsonString()}`);
    return appsJoget->post(withId(path, recordId), body,
        {"api_id": appApiIds[appId] ?: "", "api_key": appApiKeys[appId] ?: ""});
}

# Sends a notification mail (Mailpit locally).
#
# + to - Recipient user id or address
# + subject - Subject line
# + body - Plain text body
# + return - "sent" or "skipped"
@workflow:Activity
function notify(string to, string subject, string body) returns string|error {
    if !enableEmail {
        return "skipped";
    }
    string address = to.includes("@") ? to : string `${to}@${mailDomain}`;
    email:SmtpClient smtp = check new (smtpHost, smtpUser, smtpPassword, port = smtpPort,
        security = smtpStartTls ? email:START_TLS_ALWAYS : email:START_TLS_NEVER);
    check smtp->sendMessage({to: address, 'from: mailFrom, subject, body});
    io:println(string `[Activity] notify(${address}) ${subject}`);
    return "sent";
}
