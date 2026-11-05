// Read-only: pulls the real MUF rule rows from Joget's API Builder and runs the same chain as the
// workflow (DT-01, 03, 04, 05, 06) on the stub facts of P-05 and P-11. Expected from the stub run:
// P-05 -> T2 at DT-06 row 12, P-11 -> T3 at DT-06 row 5.
import ballerina/io;
import ballerina/test;

function decideWithRealRules(string caseId) returns [string, int, string]|error {
    json all = check io:fileReadJson("stub-data/muf-applications.json");
    map<json> cases = check all.ensureType();
    map<json> facts = check cases[caseId].ensureType();
    map<json> rs = check readRuleSet((check facts.submitted).toString());
    map<json> t = check (check rs.tables).ensureType();
    string v = (check rs.version).toString();
    facts["knockout_count"] = check rowCount(check evaluateTable(check t["DT-01"].ensureType(), facts, "DT-01", v));
    facts["dup_flag"] = check rowCount(check evaluateTable(check t["DT-03"].ensureType(), facts, "DT-03", v)) > 0 ? "yes" : "no";
    facts["score"] = check (check evaluateTable(check t["DT-04"].ensureType(), facts, "DT-04", v)).sum;
    facts["grade"] = check firstOut(check evaluateTable(check t["DT-05"].ensureType(), facts, "DT-05", v), "grade");
    map<json> rt = check evaluateTable(check t["DT-06"].ensureType(), facts, "DT-06", v);
    string out = (check firstOut(rt, "outcome")).toString();
    int row = check (check firstRow(rt)).ensureType();
    io:println(string `REAL JOGET RULES ${caseId}: ${v} score ${(check facts.score).toString()} grade ${(check facts.grade).toString()} => ${out} (DT-06 row ${row})`);
    return [out, row, v];
}

@test:Config
function realRulesMatchStub() returns error? {
    [string, int, string] p05 = check decideWithRealRules("APP-P05");
    [string, int, string] p11 = check decideWithRealRules("APP-P11");
    test:assertEquals([p05[0], p05[1]], ["T2", 12]);
    test:assertEquals([p11[0], p11[1]], ["T3", 5]);
}
