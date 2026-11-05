// Generic decision-table evaluator. The rows are data read from Joget at run time,
// so a row edited in Joget changes the next decision without a redeploy.
import ballerina/lang.'decimal as decimals;

# Evaluates one table against the facts.
#
# + tbl - The table: {hit, rows: [{n, when: [[field, op, value]], out}]}
# + facts - Case facts
# + tableId - Table code, for the audit
# + version - Rule set version, for the audit
# + return - {table, version, hit, rows (the numbers that fired), outputs, sum?}
isolated function evaluateTable(map<json> tbl, map<json> facts, string tableId, string version)
        returns map<json>|error {
    string hit = (check tbl.hit).toString();
    json[] rows = check (check tbl.rows).ensureType();
    int[] fired = [];
    json[] outputs = [];
    foreach json r in rows {
        json[] conds = check (check r.when).ensureType();
        boolean ok = true;
        foreach json c in conds {
            json[] parts = check c.ensureType();
            if !(check holds(facts[parts[0].toString()], parts[1].toString(), parts[2])) {
                ok = false;
                break;
            }
        }
        if ok {
            fired.push(check (check r.n).ensureType(int));
            outputs.push(check r.out);
            if hit == "first" {
                break;
            }
        }
    }
    if hit == "unique" && fired.length() != 1 {
        return error(string `${tableId} ${version}: unique table matched ${fired.length()} rows`);
    }
    map<json> result = {'table: tableId, version, hit, rows: fired, outputs};
    if hit == "sum" {
        string sumField = (check tbl.sumField).toString();
        decimal total = 0;
        foreach json o in outputs {
            map<json> om = check o.ensureType();
            total += check toDecimal(om[sumField]);
        }
        result["sum"] = total;
    }
    return result;
}

isolated function holds(json fact, string op, json val) returns boolean|error {
    if fact is () {
        return false;
    }
    match op {
        "eq" => { return equal(fact, val); }
        "ne" => { return !equal(fact, val); }
        "in" => {
            json[] options = check val.ensureType();
            foreach json o in options {
                if equal(fact, o) { return true; }
            }
            return false;
        }
        "between" => {
            json[] range = check val.ensureType();
            decimal f = check toDecimal(fact);
            return f >= check toDecimal(range[0]) && f <= check toDecimal(range[1]);
        }
    }
    decimal f = check toDecimal(fact);
    decimal v = check toDecimal(val);
    match op {
        "lt" => { return f < v; }
        "le" => { return f <= v; }
        "gt" => { return f > v; }
        "ge" => { return f >= v; }
    }
    return error(string `unknown operator ${op}`);
}

isolated function equal(json a, json b) returns boolean {
    decimal|error x = toDecimal(a);
    decimal|error y = toDecimal(b);
    if x is decimal && y is decimal {
        return x == y;
    }
    return a.toString() == b.toString();
}

isolated function toDecimal(json v) returns decimal|error {
    if v is int { return <decimal>v; }
    if v is decimal { return v; }
    if v is float { return <decimal>v; }
    return decimals:fromString(v.toString());
}

# Picks the rule set in force on a date: the latest effectiveFrom on or before it.
#
# + all - The rule document {ruleSets: [...]}
# + onDate - yyyy-mm-dd
# + return - The rule set
isolated function ruleSetFor(json all, string onDate) returns map<json>|error {
    json[] sets = check (check all.ruleSets).ensureType();
    map<json>? best = ();
    string bestFrom = "";
    foreach json s in sets {
        string ef = (check s.effectiveFrom).toString();
        if ef <= onDate && ef > bestFrom {
            best = check s.ensureType();
            bestFrom = ef;
        }
    }
    if best is () {
        return error(string `no rule set in force on ${onDate}`);
    }
    return best;
}

# Reads one key of the first output of an evaluation.
#
# + r - Evaluation from evaluateTable
# + key - Output key
# + return - The value
isolated function firstOut(map<json> r, string key) returns json|error {
    json[] outs = check (check r.outputs).ensureType();
    map<json> o = check outs[0].ensureType();
    return o[key];
}

isolated function firstRow(map<json> r) returns json|error {
    json[] rows = check (check r.rows).ensureType();
    return rows[0];
}

isolated function outsOf(map<json> r) returns json[]|error => (check r.outputs).ensureType();

isolated function rowCount(map<json> r) returns int|error {
    json[] rows = check (check r.rows).ensureType();
    return rows.length();
}
