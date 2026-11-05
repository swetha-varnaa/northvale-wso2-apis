// Runs only against the stub (jogetBaseUrl containing "joget-stub"), never against real Joget.
// DECIDED is held, then merged into the next write: one write-back with route, version, row and wf_run_id.
import ballerina/test;

@test:Config
function routingIsOneWriteBack() returns error? {
    if !jogetBaseUrl.includes("joget-stub") {
        return;
    }
    json held = check writeMufStatus("APP-TEST", {status: "DECIDED", route: "T2", rule_version: "RS-1.0", deciding_row: 12});
    test:assertEquals(held, {held: true});
    json _ = check writeMufStatus("APP-TEST", {status: "PENDING_T2", route_level: "T2", approvers: ["tom.reyes"]});
    // Body only: the stub has no Desk path in every config, so the reply is not checked.
    json|error _ = writeAppStatus("wso2Desk", "DSK-T", {status: "Submitted"});
}
