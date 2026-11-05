// Joget's list and form APIs omit empty columns. A row without group_key, out_code, out_label
// and out_value, and a case without optional facts, must still evaluate.
import ballerina/test;

@test:Config
function rowsWithoutOptionalColumns() returns error? {
    json[] rows = [
        {table_code: "DT-01", rule_set: "RS-1.0", effective_from: "2026-10-12", row_no: "01", condition: "age_at_application &lt; 21", out_code: "K-01"},
        {table_code: "DT-01", rule_set: "RS-1.0", effective_from: "2026-10-12", row_no: "02", condition: "nik_on_blacklist = yes"},
        {table_code: "DT-06", rule_set: "RS-1.0", effective_from: "2026-10-12", row_no: "01", condition: "knockout_count >= 1", out_code: "AUTO_REJECT"},
        {table_code: "DT-06", rule_set: "RS-1.0", effective_from: "2026-10-12", row_no: "02", condition: "any", out_code: "T1"}
    ];
    map<json> rs = check ruleSetFromJogetRows(rows, "2026-11-05");
    map<json> t = check (check rs.tables).ensureType();
    map<json> facts = {nik_on_blacklist: "yes"}; // age_at_application missing
    map<json> ko = check evaluateTable(check t["DT-01"].ensureType(), facts, "DT-01", "RS-1.0");
    test:assertEquals(check ko.rows, [2]);
    facts["knockout_count"] = check rowCount(ko);
    map<json> rt = check evaluateTable(check t["DT-06"].ensureType(), facts, "DT-06", "RS-1.0");
    test:assertEquals((check firstOut(rt, "outcome")).toString(), "Auto reject");
    test:assertEquals(opt({}, "preparer"), "");
}
