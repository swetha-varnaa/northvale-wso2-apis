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
            string pv = opt(om, sumField);
            total += pv == "" ? 0d : check toDecimal(pv);
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
            decimal|error fe = toDecimal(fact);
            if fe is error {
                return false;
            }
            decimal f = fe;
            return f >= check toDecimal(range[0]) && f <= check toDecimal(range[1]);
        }
    }
    decimal|error fe = toDecimal(fact);
    if fe is error {
        return false;
    }
    decimal f = fe;
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

// ---- Joget API Builder rule rows -> the evaluator's table shape ----
// Row: {table_code, rule_set, effective_from, row_no, group_key, condition, out_code, out_label, out_value}.
// Condition grammar: tests joined by " and "; test = "field op value"; ops = != < <= > >= in between; "any".

final readonly & map<string> HIT_POLICY = {"DT-01": "collect", "DT-02": "collect", "DT-03": "collect",
    "DT-04": "sum", "DT-05": "unique", "DT-06": "first", "DT-07": "collect", "DT-08": "collect",
    "DT-09": "collect", "DT-10": "unique"};

final readonly & map<string> OPS = {"=": "eq", "!=": "ne", "<": "lt", "<=": "le", ">": "gt", ">=": "ge",
    "in": "in", "between": "between"};

isolated function unescape(string s) returns string {
    string r = re `&lt;`.replaceAll(s, "<");
    r = re `&gt;`.replaceAll(r, ">");
    return re `&amp;`.replaceAll(r, "&");
}

isolated function parseCondition(string raw) returns json[]|error {
    string c = unescape(raw).trim();
    if c == "any" || c == "" {
        return [];
    }
    json[] tests = [];
    foreach string t in re ` and `.split(c) {
        string[] p = re `\s+`.split(t.trim());
        if p.length() < 3 {
            return error(string `cannot read condition "${c}"`);
        }
        string? op = OPS[p[1]];
        if op is () {
            return error(string `unknown operator ${p[1]} in "${c}"`);
        }
        string v = string:'join(" ", ...p.slice(2));
        json value = v;
        if op == "in" {
            value = re `,`.split(v).map(x => <json>x.trim());
        } else if op == "between" {
            string[] ab = re `\.\.`.split(v);
            value = [ab[0], ab[1]];
        }
        tests.push([p[0], op, value]);
    }
    return tests;
}

# Builds the rule set in force on a date from Joget's flat rows: latest effective_from <= onDate.
#
# + data - The rows
# + onDate - yyyy-mm-dd
# + return - {version, effectiveFrom, tables}
isolated function ruleSetFromJogetRows(json[] data, string onDate) returns map<json>|error {
    string bestFrom = "";
    foreach json r in data {
        string ef = opt(check r.ensureType(), "effective_from");
        if ef <= onDate && ef > bestFrom {
            bestFrom = ef;
        }
    }
    if bestFrom == "" {
        return error(string `no rule set in force on ${onDate}`);
    }
    string version = "";
    map<json[]> rowsBy = {};
    foreach json r in data {
        map<json> rm = check r.ensureType();
        if opt(rm, "effective_from") != bestFrom {
            continue;
        }
        version = opt(rm, "rule_set");
        string tc = opt(rm, "table_code");
        string code = opt(rm, "out_code");
        json outValue = opt(rm, "out_value");
        json[] list = rowsBy[tc] ?: [];
        list.push({n: check int:fromString(opt(rm, "row_no")), when: check parseCondition(opt(rm, "condition")),
            out: {code, label: opt(rm, "out_label"), value: outValue, points: outValue, grade: code,
                outcome: code == "AUTO_REJECT" ? "Auto reject" : code, username: code, route_level: code, flag: "DUP"}});
        rowsBy[tc] = list;
    }
    map<json> tables = {};
    foreach [string, json[]] [tc, rows] in rowsBy.entries() {
        json[] sorted = from json r in rows order by <int>check r.n ascending select r;
        tables[tc] = {hit: HIT_POLICY[tc] ?: "collect", sumField: "points", rows: sorted};
    }
    return {version, effectiveFrom: bestFrom, tables};
}

# Reads a field that Joget may omit: its list and form APIs drop empty columns. Missing = "".
#
# + m - The row or record
# + key - Field id
# + return - The value as text, or ""
isolated function opt(map<json> m, string key) returns string {
    json v = m[key];
    return v is () ? "" : v.toString();
}
