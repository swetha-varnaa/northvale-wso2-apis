// Activities: every call to Joget or to mail is a recorded, replay-safe step.
import ballerina/email;
import ballerina/http;
import ballerina/io;
import ballerina/lang.regexp;
import ballerina/workflow;

final http:Client joget = check new (jogetBaseUrl, timeout = 30);

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
    io:println(string `[Activity] writeMufStatus(${applicationId}) ${update.toJsonString()}`);
    return joget->post(withId(mufStatusPath, applicationId), update, jogetHeaders());
}

# Writes a status back to any of the six apps' records in Joget.
#
# + appId - Joget app id
# + recordId - Record id
# + update - Fields to write
# + return - Joget's reply
@workflow:Activity
function writeAppStatus(string appId, string recordId, map<json> update) returns json|error {
    string? path = appStatusPaths[appId];
    if path is () {
        return error(string `no status path configured for ${appId}`);
    }
    io:println(string `[Activity] writeAppStatus(${appId}, ${recordId}) ${update.toJsonString()}`);
    return joget->post(withId(path, recordId), update, jogetHeaders());
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
