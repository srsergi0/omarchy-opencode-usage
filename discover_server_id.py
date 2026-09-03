#!/usr/bin/env python3
import sys, re, subprocess, json, os

wrk = sys.argv[1] if len(sys.argv) > 1 else ""
auth = sys.argv[2] if len(sys.argv) > 2 else ""

if not wrk or not auth:
    print(json.dumps({"error": "missing wrk or auth"}))
    sys.exit(0)

# Try to discover serverId by fetching HTML and then JS assets
import urllib.request, urllib.error

def fetch(url, headers={}):
    # Use curl for more reliable headers (like we do in BarWidget)
    import subprocess, shlex
    cmd = ["curl", "--silent", url]
    for k,v in headers.items():
        cmd.extend(["-H", f"{k}: {v}"])
    # Always send auth cookie
    if "Cookie" not in headers:
        cmd.extend(["-b", f"auth={auth}"])
    try:
        out = subprocess.check_output(cmd, timeout=10).decode('utf-8', errors='ignore')
        return out
    except Exception as e:
        return ""

headers = {
    "accept": "text/html",
    "Cookie": f"auth={auth}",
    "referer": f"https://opencode.ai/workspace/{wrk}/usage",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
}
html = fetch(f"https://opencode.ai/workspace/{wrk}/usage", headers)
if not html:
    print(json.dumps({"error": "failed to fetch HTML"}))
    sys.exit(0)

# Find all script src
scripts = re.findall(r'src="([^"]*\.js[^"]*)"', html)
candidates = set()
# Also find any 64-char hex in HTML directly
for m in re.finditer(r"[a-f0-9]{64}", html):
    candidates.add(m.group(0))

# Fetch each script and look for _server?id=
for src in scripts:
    if src.startswith("/"):
        src = "https://opencode.ai" + src
    js = fetch(src, {"Cookie": f"auth={auth}"})
    for m in re.finditer(r"_server\?id=([a-f0-9]{64})", js):
        candidates.add(m.group(1))
    for m in re.finditer(r"[a-f0-9]{64}", js):
        # limit to plausible serverIds (64 hex)
        candidates.add(m.group(0))
    if len(candidates) > 20:
        break

# Try each candidate as serverId for the aggregated usage endpoint
# The correct one will return rollingUsage with status ok
import urllib.parse, http.client, ssl
def test_server_id(sid):
    import urllib.parse, subprocess
    args = urllib.parse.quote('{"t":{"t":9,"i":0,"l":1,"a":[{"t":1,"s":"'+wrk+'"}],"o":0},"f":31,"m":[]}')
    url = f"https://opencode.ai/_server?id={sid}&args={args}"
    cmd = ["curl", "--silent", url, "-H", "accept: */*", "-b", f"auth={auth}", "-H", f"referer: https://opencode.ai/workspace/{wrk}/usage", "-H", f"x-server-id: {sid}", "-H", "x-server-instance: server-fn:9"]
    try:
        body = subprocess.check_output(cmd, timeout=10).decode('utf-8', errors='ignore')
        return "rollingUsage" in body and "usagePercent" in body
    except:
        return False

candidates = list(candidates)

for sid in candidates:
    if test_server_id(sid):
        print(json.dumps({"serverId": sid}))
        sys.exit(0)

print(json.dumps({"error": "no valid serverId found", "candidates": list(candidates)[:5]}))
