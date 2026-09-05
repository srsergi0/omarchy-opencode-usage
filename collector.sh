#!/usr/bin/env bash
set -uo pipefail
AUTH_JSON="${OPENCODE_AUTH_JSON:-$HOME/.local/share/opencode/auth.json}"
URL=https://opencode.ai/zen/go/v1/usage
DB="$HOME/.local/share/opencode/opencode.db"

key=$(jq -r '.["opencode-go"].key // empty' "$AUTH_JSON" 2>/dev/null || true)

collect() {
  local k=$1 out code
  [[ -n $k ]] || { echo '{"status":"No API key"}'; return; }
  out=$(curl -sS -m 10 -w $'\n%{http_code}' -H "Authorization: Bearer $k" "$URL" 2>/dev/null) || { echo '{"status":"network error"}'; return; }
  code=${out##*$'\n'}; out=${out%$'\n'*}
  [[ $code == 200 ]] || { jq -cn --arg s "HTTP $code" '{status:$s}'; return; }
  jq -e '.usage.rolling and .usage.weekly and .usage.monthly' >/dev/null 2>&1 <<<"$out" || { echo '{"status":"bad response"}'; return; }
  # Normalizar con limitDollars fallback si API no los trae
  jq -c '{status:"ok",
    rolling: (.usage.rolling + {limitDollars: (.usage.rolling.limitDollars // 12)}),
    weekly:  (.usage.weekly  + {limitDollars: (.usage.weekly.limitDollars  // 30)}),
    monthly: (.usage.monthly + {limitDollars: (.usage.monthly.limitDollars // 60)})
  }' <<<"$out"
}

windows=$(collect "$key")
status=$(jq -r '.status // empty' <<<"$windows")
error=''
[[ $status == ok ]] || error="$status"

cutoff=$(( $(date +%s)*1000-604800000 ))
recent='[]'
heatmap='[]'
projects='[]'
if [[ -r $DB ]]; then
  q="SELECT date(time_created/1000,'unixepoch','localtime'),SUM(COALESCE(json_extract(data,'\$.tokens.total'),0)),ROUND(SUM(COALESCE(json_extract(data,'\$.cost'),0)),4) FROM message WHERE time_created > $cutoff AND json_extract(data,'\$.providerID')='opencode-go' GROUP BY 1 ORDER BY 1;"
  rows=$(sqlite3 -readonly "file:$DB?mode=ro" "$q" 2>/dev/null || true)
  while IFS='|' read -r d t c; do [[ -n $d ]] && recent=$(jq -c --arg d "$d" --arg t "${t:-0}" --arg c "${c:-0}" '.+[{date:$d,tokens:($t|tonumber),cost:($c|tonumber)}]' <<<"$recent"); done <<<"$rows"
  qh="SELECT date(time_created/1000,'unixepoch','localtime'),strftime('%H',time_created/1000,'unixepoch','localtime'),SUM(COALESCE(json_extract(data,'\$.tokens.total'),0)),ROUND(SUM(COALESCE(json_extract(data,'\$.cost'),0)),4),COUNT(*) FROM message WHERE time_created > $cutoff AND json_extract(data,'\$.providerID')='opencode-go' GROUP BY 1,2 ORDER BY 1,2;"
  rows=$(sqlite3 -readonly "file:$DB?mode=ro" "$qh" 2>/dev/null || true)
  while IFS='|' read -r d h t c n; do [[ -n $d ]] && heatmap=$(jq -c --arg d "$d" --arg h "$h" --arg t "${t:-0}" --arg c "${c:-0}" --arg n "${n:-0}" '.+[{date:$d,hour:($h|tonumber),tokens:($t|tonumber),cost:($c|tonumber),count:($n|tonumber)}]' <<<"$heatmap"); done <<<"$rows"
  qp="SELECT COALESCE(p.worktree, p.id), COALESCE(p.name,''), COUNT(s.id), ROUND(COALESCE(SUM(s.cost),0),4), COALESCE(SUM(s.tokens_input + s.tokens_output + s.tokens_reasoning + s.tokens_cache_read + s.tokens_cache_write),0) FROM session s JOIN project p ON p.id=s.project_id WHERE s.time_created > $cutoff GROUP BY p.id ORDER BY SUM(s.cost) DESC;"
  rows=$(sqlite3 -readonly "file:$DB?mode=ro" "$qp" 2>/dev/null || true)
  while IFS='|' read -r wt nm cnt cost toks; do [[ -n $wt ]] && projects=$(jq -c --arg wt "$wt" --arg nm "$nm" --arg cnt "${cnt:-0}" --arg cost "${cost:-0}" --arg toks "${toks:-0}" '.+[{worktree:$wt,name:$nm,sessions:($cnt|tonumber),cost:($cost|tonumber),tokens:($toks|tonumber)}]' <<<"$projects"); done <<<"$rows"
fi

jq -cn --arg label "Go" --argjson w "$windows" --argjson recent "$recent" --argjson heatmap "$heatmap" --argjson projects "$projects" --arg status "$status" --arg error "$error" '{label:$label,status:$status,rolling:$w.rolling,weekly:$w.weekly,monthly:$w.monthly,recentDays:$recent,heatmap:$heatmap,projects:$projects,updatedAt:(now|todateiso8601),error:$error}'
