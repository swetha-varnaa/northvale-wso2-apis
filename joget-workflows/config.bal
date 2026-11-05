// Every environment value lives in Config.toml (git-ignored). Config.example.toml lists them all.

# Joget base URL for API Builder calls. Use Tomcat's direct port: a reverse proxy drops the
# api_id / api_key headers because of the underscore.
configurable string jogetBaseUrl = "http://localhost:8099/joget-stub";
configurable string jogetApiId = "";
configurable string jogetApiKey = "";

# Paths on jogetBaseUrl. {id} is replaced with the record id.
# rulesFormat "joget" = API Builder list of flat rows with a text condition; "stub" = stub-data JSON.
configurable string rulesFormat = "stub";
configurable string mufRulesPath = "/muf/rules";
configurable string mufRecordPath = "/muf/applications/{id}";
configurable string mufStatusPath = "/muf/applications/{id}/status";

# Base URL for the six apps' write-back (stays on the stub until their API Builder paths exist).
configurable string appsBaseUrl = "http://localhost:8099/joget-stub";

# Per-app status write-back path, keyed by Joget app id. {id} is replaced with the record id.
configurable map<string> appStatusPaths = {
    "wso2AppCentre": "/wso2AppCentre/records/{id}/status",
    "bizOnboarding": "/bizOnboarding/records/{id}/status",
    "wso2Loan": "/wso2Loan/records/{id}/status",
    "wso2HrLeave": "/wso2HrLeave/records/{id}/status",
    "wso2Onboarding": "/wso2Onboarding/records/{id}/status",
    "wso2Desk": "/wso2Desk/records/{id}/status"
};

# Local stand-in for Joget, served by this program until the Joget API Builder endpoints exist.
configurable boolean enableJogetStub = true;
configurable int jogetStubPort = 8099;
configurable string stubDataDir = "stub-data";

# Mail. Locally this is Mailpit; on cloud, the customer's SMTP relay.
configurable boolean enableEmail = true;
configurable string smtpHost = "localhost";
configurable int smtpPort = 1026;
configurable string smtpUser = "workflow";
configurable string smtpPassword = "local";
configurable boolean smtpStartTls = false;
configurable string mailFrom = "workflow@northvale.local";
configurable string mailDomain = "northvale.local";
