// Local stand-in for the Joget API Builder endpoints. Off on cloud (enableJogetStub = false).
// Reads the JSON files on every call, so editing stub-data/muf-rules.json acts like a rule edit in Joget.
import ballerina/http;
import ballerina/io;
import ballerina/lang.runtime;
import ballerina/time;

isolated function stubWrite(string app, string id, json body) returns error? {
    json line = {at: time:utcToString(time:utcNow()), app, id, body};
    check io:fileWriteString(stubDataDir + "/writeback.jsonl", line.toJsonString() + "\n", io:APPEND);
}

isolated service class JogetStub {
    *http:Service;
    resource function get muf/rules() returns json|error => io:fileReadJson(stubDataDir + "/muf-rules.json");

    resource function get muf/applications/[string id]() returns json|http:NotFound|error {
        json all = check io:fileReadJson(stubDataDir + "/muf-applications.json");
        map<json> m = check all.ensureType();
        return m.hasKey(id) ? m.get(id) : http:NOT_FOUND;
    }

    resource function post muf/applications/[string id]/status(@http:Payload json body) returns json|error {
        check stubWrite("muf", id, body);
        return {ok: true};
    }

    resource function post [string app]/records/[string id]/status(@http:Payload json body) returns json|error {
        check stubWrite(app, id, body);
        return {ok: true};
    }
}

function init() returns error? {
    if enableJogetStub {
        http:Listener l = check new (jogetStubPort);
        check l.attach(new JogetStub(), "/joget-stub");
        check l.'start();
        runtime:registerListener(l);
    }
}
