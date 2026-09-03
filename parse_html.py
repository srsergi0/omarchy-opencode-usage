import sys, re, json, datetime
html = sys.stdin.read()

# Extraer usage.list array del HTML
# Patrón: usage.list["wrk_..."] = $R[16] = [{id:"usg_...", ...}, ...]
# El HTML contiene $R[25]=[{id:"usg_...", cost:54361, timeCreated: new Date("2026-09-03T...")}, ...]
# Buscamos todos los costs y tiempos en el HTML
# Más robusto: buscar todos los objetos con cost: y timeCreated:
pattern = re.compile(r'\{id:"usg_[^"]*",workspaceID:"[^"]*",timeCreated:\$R\[\d+\]=new Date\("([^"]+)"\)[^}]*cost:(\d+)[^}]*inputTokens:(\d+)[^}]*outputTokens:(\d+)', re.S)
# Fallback más simple: buscar cost y timeCreated por separado
# Si no encuentra con el patrón complejo, busca todos los new Date y cost en orden

records = []
# Intenta extraer via cualquier array $R[xx]=[...usg_...]
# Buscar todos los $R[xx]=[ ... ] que contengan usg_
for m in re.finditer(r'\$R\[\d+\]=\[(.*?usg_.*?)\];', html, re.S):
    array_text = m.group(1)
    usg_pattern = re.compile(r'id:"(usg_[^"]*)".*?timeCreated:\$R\[\d+\]=new Date\("([^"]+)"\).*?cost:(\d+).*?inputTokens:(\d+).*?outputTokens:(\d+)', re.S)
    for mm in usg_pattern.finditer(array_text):
        try:
            tid, tstr, cost, inp, outp = mm.groups()
            # Evitar duplicados
            if not any(r["id"]==tid for r in records):
                records.append({
                    "id": tid,
                    "timeCreated": tstr,
                    "cost": int(cost),
                    "inputTokens": int(inp),
                    "outputTokens": int(outp)
                })
        except: pass
# Fallback: buscar directamente todos los usg en el HTML sin depender del array contenedor
if not records:
    usg_pattern2 = re.compile(r'id:"(usg_[^"]*)".*?timeCreated:\$R\[\d+\]=new Date\("([^"]+)"\).*?cost:(\d+).*?inputTokens:(\d+).*?outputTokens:(\d+)', re.S)
    for mm in usg_pattern2.finditer(html):
        try:
            tid, tstr, cost, inp, outp = mm.groups()
            if not any(r["id"]==tid for r in records):
                records.append({
                    "id": tid,
                    "timeCreated": tstr,
                    "cost": int(cost),
                    "inputTokens": int(inp),
                    "outputTokens": int(outp)
                })
        except: pass

# Fallback: si no encontró nada, busca cualquier cost/timeCreated en el HTML
if not records:
    dates = re.findall(r'new Date\("([^"]+)"\)', html)
    costs = re.findall(r'cost:(\d+)', html)
    # No fiable, solo para debug
    pass

now = datetime.datetime.now(datetime.timezone.utc)
# Calcular aggregates
def sum_window(hours):
    cutoff = now - datetime.timedelta(hours=hours)
    total_cost = 0
    total_in = 0
    total_out = 0
    cnt = 0
    for r in records:
        try:
            dt = datetime.datetime.fromisoformat(r["timeCreated"].replace("Z", "+00:00"))
            if dt >= cutoff:
                total_cost += r["cost"]
                total_in += r["inputTokens"]
                total_out += r["outputTokens"]
                cnt += 1
        except: pass
    return cnt, total_cost, total_in, total_out

cnt5, cost5, in5, out5 = sum_window(5)
cnt7, cost7, in7, out7 = sum_window(7*24)
cnt30, cost30, in30, out30 = sum_window(30*24)

# Límites observados en _server (lite plan)
LIMIT_5H = 1200000000
LIMIT_WEEKLY = 3000000000
LIMIT_MONTHLY = 6000000000

# Reset: para HTML no tenemos resetInSec del server, calculamos aproximado
# 5h rolling: reset cuando el registro más viejo de la ventana expire (now - oldest +5h)
# weekly: próximo lunes 00:00 UTC, monthly: próximo 25? Para estable usamos próximo lunes y 30d desde hoy
def next_monday_reset():
    # lunes = 0
    days_ahead = (7 - now.weekday()) % 7
    if days_ahead == 0:
        days_ahead = 7
    # Si hoy es lunes y ya pasó medianoche, sería próximo lunes; pero _server daba 3.9d desde jueves -> lunes
    next_monday = (now + datetime.timedelta(days=days_ahead)).replace(hour=0, minute=0, second=0, microsecond=0)
    return int((next_monday - now).total_seconds())

def next_monthly_reset():
    # _server daba 22.8d a Sep 25, que es 30d desde Aug 26? Aproximamos a 30d desde hoy
    # Para mensual usamos 30d desde ahora
    return 30*24*3600 - int(now.timestamp() % (30*24*3600))  # no preciso
    # Mejor: usar el reset del server si lo tenemos, sino 00:00 UTC diario
    # Para estable, devolvemos segundos hasta próxima medianoche UTC (como antes)
import math
next_midnight = (now + datetime.timedelta(days=1)).replace(hour=0, minute=0, second=0, microsecond=0)
reset_daily = int((next_midnight - now).total_seconds())
# Para 5h, reset = 5h - (now - oldest_in_5h)
oldest_5h = None
for r in records:
    try:
        dt = datetime.datetime.fromisoformat(r["timeCreated"].replace("Z", "+00:00"))
        if dt >= now - datetime.timedelta(hours=5):
            if oldest_5h is None or dt < oldest_5h:
                oldest_5h = dt
    except: pass
if oldest_5h:
    reset_5h = int((oldest_5h + datetime.timedelta(hours=5) - now).total_seconds())
    reset_5h = max(0, reset_5h)
else:
    reset_5h = 5*3600

# Si no hay reset específico, usar el diario y 5h calculado
try:
    weekly_reset = next_monday_reset()
except:
    weekly_reset = reset_daily
monthly_reset = reset_daily  # fallback

out = {
    "rolling": {"usage": cost5, "limit": LIMIT_5H, "pct": round(cost5/LIMIT_5H*100,1) if LIMIT_5H else 0, "resetSec": reset_5h, "count": cnt5},
    "weekly": {"usage": cost7, "limit": LIMIT_WEEKLY, "pct": round(cost7/LIMIT_WEEKLY*100,1) if LIMIT_WEEKLY else 0, "resetSec": weekly_reset, "count": cnt7},
    "monthly": {"usage": cost30, "limit": LIMIT_MONTHLY, "pct": round(cost30/LIMIT_MONTHLY*100,1) if LIMIT_MONTHLY else 0, "resetSec": monthly_reset, "count": cnt30},
    "recordsTotal": len(records)
}
# Si no hay registros, intenta también parsear el fallback de ?
if not records:
    out["error"] = "no records found in HTML (¿auth vencido o workspace sin usage?)"
    # No fallar, devolver 0
print(json.dumps(out))
