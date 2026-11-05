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

# The apps' status write-back on Joget (API Builder, form saveOrUpdate; the record id goes in the body).
# Set appsBaseUrl to the stub (http://localhost:8099/joget-stub) and the stub paths to fall back.
configurable string appsBaseUrl = "http://localhost:8096/jw/api";
configurable map<string> appStatusPaths = {
    "wso2Desk": "/form/desk_wso2_writeback/saveOrUpdate",
    "wso2HrLeave": "/form/hr_wso2_writeback/saveOrUpdate",
    "wso2Loan": "/form/loan_wso2_writeback/saveOrUpdate",
    "wso2Onboarding": "/form/onb_wso2_writeback/saveOrUpdate",
    "bizOnboarding": "/form/bo_wso2_writeback/saveOrUpdate"
};
# Each Joget app has its own API key pair (secrets JOGET_<APP>_API_ID / _API_KEY).
configurable map<string> appApiIds = {};
configurable map<string> appApiKeys = {};

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
