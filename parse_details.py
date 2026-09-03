#!/usr/bin/env python3
import sys, re, json

period = sys.argv[1] if len(sys.argv) > 1 else "unknown"
raw = sys.stdin.read()

# Handle null case: ...[],null)  -> no data
if "null" in raw and "rows" not in raw:
    print(json.dumps({"usage":0,"limit":0,"pct":0,"rows":[]}))
    sys.exit(0)

# Extract usage, limit, usagePercent
usage = 0
limit = 0
pct = 0
m = re.search(r'usage\s*:\s*(\d+)', raw)
if m: usage = int(m.group(1))
m = re.search(r'limit\s*:\s*(\d+)', raw)
if m: limit = int(m.group(1))
m = re.search(r'usagePercent\s*:\s*([0-9.]+)', raw)
if m: pct = float(m.group(1))

rows = []
# Extract model rows: model:"...",name:"...",cost:...,quotaCost:...,multiplier:...,contributionPercent:...
# Pattern may be "model" then "name" then "cost"
for mm in re.finditer(r'model\s*:\s*"([^"]+)"\s*,\s*name\s*:\s*"([^"]+)"\s*,\s*cost\s*:\s*(\d+)\s*,\s*quotaCost\s*:\s*(\d+)\s*,\s*multiplier\s*:\s*(\d+)[^}]*contributionPercent\s*:\s*([0-9.]+)', raw):
    model, name, cost, quota, mult, contrib = mm.groups()
    rows.append({
        "model": model,
        "name": name,
        "cost": int(cost),
        "quotaCost": int(quota),
        "multiplier": int(mult),
        "contributionPercent": float(contrib)
    })
# Fallback: try without name
if not rows:
    for mm in re.finditer(r'model\s*:\s*"([^"]+)"[^}]*cost\s*:\s*(\d+)[^}]*quotaCost\s*:\s*(\d+)[^}]*contributionPercent\s*:\s*([0-9.]+)', raw):
        model, cost, quota, contrib = mm.groups()
        rows.append({
            "model": model,
            "name": model,
            "cost": int(cost),
            "quotaCost": int(quota),
            "multiplier": 1,
            "contributionPercent": float(contrib)
        })

out = {
    "usage": usage,
    "limit": limit,
    "pct": pct,
    "rows": rows
}
print(json.dumps(out))
