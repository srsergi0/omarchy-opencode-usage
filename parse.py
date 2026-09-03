import sys, re, json
raw = sys.stdin.read()
def g(field, key):
    m = re.search(rf"{field}.*?{key}\s*:\s*([0-9.]+)", raw)
    return m.group(1) if m else "0"
try:
    out = {
        "rolling": {
            "usage": int(float(g("rollingUsage", "usage"))),
            "limit": int(float(g("rollingUsage", "limit"))),
            "pct": float(g("rollingUsage", "usagePercent")),
            "resetSec": int(float(g("rollingUsage", "resetInSec")))
        },
        "weekly": {
            "usage": int(float(g("weeklyUsage", "usage"))),
            "limit": int(float(g("weeklyUsage", "limit"))),
            "pct": float(g("weeklyUsage", "usagePercent")),
            "resetSec": int(float(g("weeklyUsage", "resetInSec")))
        },
        "monthly": {
            "usage": int(float(g("monthlyUsage", "usage"))),
            "limit": int(float(g("monthlyUsage", "limit"))),
            "pct": float(g("monthlyUsage", "usagePercent")),
            "resetSec": int(float(g("monthlyUsage", "resetInSec")))
        }
    }
    print(json.dumps(out))
except Exception as e:
    print(json.dumps({"error": str(e), "raw": raw[:2000]}))
