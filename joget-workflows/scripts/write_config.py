"""Writes Config.toml (git-ignored) from Config.example.toml, filling every empty secret from
~/vexa-system/.secrets/env and ~/vexa-system/.secrets/wso2-joget-api.env, by the name in the line's comment
or by the known key names. Prints names only, never values."""
import os, re, sys
here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sec = {}
for f in ("env", "wso2-joget-api.env"):
    p = os.path.expanduser(f"~/vexa-system/.secrets/{f}")
    if os.path.exists(p):
        for l in open(p):
            if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", l):
                k, v = l.rstrip("\n").split("=", 1); sec[k] = v.strip().strip('"')
fixed = {"jogetApiId": "JOGET_MUF_API_ID", "jogetApiKey": "JOGET_MUF_API_KEY", "apiKeyValue": "WSO2_WORKFLOW_MGMT_API_KEY"}
out, missing = [], []
for line in open(os.path.join(here, "Config.example.toml")):
    m = re.match(r'^(\w+) = ""\s*(#\s*(\S+))?', line)
    if m:
        name = fixed.get(m.group(1)) or (m.group(3) if m.group(3) and m.group(3).startswith(("JOGET_", "WSO2_", "TEMPORAL_")) else None)
        if name:
            if name in sec: line = f'{m.group(1)} = "{sec[name]}"\n'
            else: missing.append(name)
    out.append(line)
open(os.path.join(here, "Config.toml"), "w").writelines(out)
os.chmod(os.path.join(here, "Config.toml"), 0o600)
print("Config.toml written" + (f"; missing secrets: {', '.join(missing)}" if missing else "; all secrets filled"))
