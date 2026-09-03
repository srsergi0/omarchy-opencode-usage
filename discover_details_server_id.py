#!/usr/bin/env python3
import sys, re, subprocess, json

wrk = sys.argv[1] if len(sys.argv) > 1 else ""
auth = sys.argv[2] if len(sys.argv) > 2 else ""

if not wrk or not auth:
    print(json.dumps({"error": "missing wrk or auth"}))
    sys.exit(0)

def fetch(url, headers={}):
    cmd = ["curl", "--silent", url]
    for k,v in headers.items():
        cmd.extend(["-H", f"{k}: {v}"])
    if "Cookie" not in headers:
        cmd.extend(["-b", f"auth={auth}"])
    try:
        out = subprocess.check_output(cmd, timeout=10).decode('utf-8', errors='ignore')
        return out
    except:
        return ""

# Try /go page first, then /usage page, and also JS assets
headers_go = {
    "accept": "text/html",
    "Cookie": f"auth={auth}",
    "referer": f"https://opencode.ai/workspace/{wrk}/go",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
}
headers_usage = {
    "accept": "text/html",
    "Cookie": f"auth={auth}",
    "referer": f"https://opencode.ai/workspace/{wrk}/usage",
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"
}
candidates = set()
for headers, path in [(headers_go, f"https://opencode.ai/workspace/{wrk}/go"), (headers_usage, f"https://opencode.ai/workspace/{wrk}/usage")]:
    html = fetch(path, headers)
    for m in re.finditer(r"[a-f0-9]{64}", html):
        candidates.add(m.group(0))
    scripts = re.findall(r'src="([^"]*\.js[^"]*)"', html)
    for src in scripts:
        if src.startswith("/"):
            src = "https://opencode.ai" + src
        js = fetch(src, {"Cookie": f"auth={auth}"})
        for m in re.finditer(r"_server\?id=([a-f0-9]{64})", js):
            candidates.add(m.group(1))
        for m in re.finditer(r"[a-f0-9]{64}", js):
            candidates.add(m.group(0))
        if len(candidates) > 30:
            break

import urllib.parse
def test_details_sid(sid):
    # test with l=2 rolling
    args = urllib.parse.quote('{"t":{"t":9,"i":0,"l":2,"a":[{"t":1,"s":"'+wrk+'"},{"t":1,"s":"rolling"}],"o":0},"f":31,"m":[]}')
    url = f"https://opencode.ai/_server?id={sid}&args={args}"
    cmd = ["curl", "--silent", url, "-H", "accept: */*", "-b", f"auth={auth}", "-H", f"referer: https://opencode.ai/workspace/{wrk}/go", "-H", f"x-server-id: {sid}", "-H", "x-server-instance: server-fn:1"]
    try:
        body = subprocess.check_output(cmd, timeout=10).decode('utf-8', errors='ignore')
        return "rows" in body and "usagePercent" in body and "model" in body
    except:
        return False

candidates = list(candidates)
for sid in candidates:
    if test_details_sid(sid):
        print(json.dumps({"serverId": sid}))
        sys.exit(0)

print(json.dumps({"error": "no valid detailsServerId found", "candidates": candidates[:5]}))
