#!/bin/sh
# API test suite for com.palm.universalsearch (luna-universalsearchmgr).
#
# Runs ON the LuneOS device (BusyBox sh compatible). Copy it over and run:
#   scp -P 5522 tests/run-api-tests.sh root@localhost:/tmp/
#   ssh -tt -p 5522 root@localhost 'sh /tmp/run-api-tests.sh [fixture-xml-url]'
#
# The optional argument is an http:// URL serving tests/fixtures/opensearch-test.xml
# (e.g. http://10.0.2.2:8931/opensearch-test.xml with a webserver on the VM host);
# when given, the OpenSearch download/parse pipeline is tested end-to-end via
# com.palm.downloadmanager. Without it that section is skipped.
#
# The suite snapshots enabled-states and the default search engine at start and
# restores them at the end, so it is safe to run on a live (test) system.
# Exit code = number of failed assertions.

U=luna://com.palm.universalsearch
FIXTURE_URL="$1"
# BusyBox may lack the timeout applet
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout 10"; else TIMEOUT=""; fi
PASS=0; FAIL=0; SKIP=0
RESP=""

call() { # call <method> <json>
	RESP=$($TIMEOUT luna-send -n 1 -f "$U/$1" "$2" 2>&1)
}

report() { # report <pass|fail|skip> <name>
	case "$1" in
	pass) PASS=$((PASS+1)); echo "PASS: $2";;
	skip) SKIP=$((SKIP+1)); echo "SKIP: $2";;
	*)    FAIL=$((FAIL+1)); echo "FAIL: $2"; echo "      response: $RESP";;
	esac
}

ok_true()  { echo "$RESP" | grep -q '"returnValue": true'  && report pass "$1" || report fail "$1"; }
ok_false() { echo "$RESP" | grep -q '"returnValue": false' && report pass "$1" || report fail "$1"; }
has()      { echo "$RESP" | grep -q "$2" && report pass "$1" || report fail "$1"; }
has_not()  { echo "$RESP" | grep -q "$2" && report fail "$1" || report pass "$1"; }

section_count() { # section_count <search|action|dbsearch> -- item count in that list
	call getUniversalSearchList '{}'
	echo "$RESP" | awk -v want="$1" '
	/"UniversalSearchList":/ {cat="search"}
	/"ActionList":/          {cat="action"}
	/"DBSearchItemList":/    {cat="dbsearch"}
	/"id": "/ {if (cat==want) n++}
	END {print n+0}'
}

SVC_PID=$(pidof LunaUniversalSearchMgr)
RSS_BEFORE=$(awk '/VmRSS/{print $2}' /proc/$SVC_PID/status)
echo "=== universalsearch API test suite; service pid=$SVC_PID rss=${RSS_BEFORE}kB ==="

# ---------------------------------------------------------------- snapshot
call getUniversalSearchList '{}'
echo "$RESP" > /tmp/us-snapshot.json
call getSearchPreference '{"key":"defaultSearchEngine"}'
ORIG_ENGINE=$(echo "$RESP" | sed -n 's/.*"defaultSearchEngine": "\([^"]*\)".*/\1/p')
echo "snapshot taken; default engine: $ORIG_ENGINE"

# ---------------------------------------------------------------- getVersion
call getVersion '{}'
ok_true "getVersion returns"
has "getVersion has version string" '"version": "1.0"'

# ---------------------------------------------------------------- lists
call getUniversalSearchList '{}'
ok_true "getUniversalSearchList returns"
has "list has UniversalSearchList array" '"UniversalSearchList":'
has "list has ActionList array" '"ActionList":'
has "list has DBSearchItemList array" '"DBSearchItemList":'
has "list has defaultSearchEngine" '"defaultSearchEngine":'
call getUniversalSearchList '{"subscribe":true}'
has "getUniversalSearchList one-shot subscribe" '"subscribed": true'

# ---------------------------------------------------------------- preferences
call getSearchPreference '{"key":"defaultSearchEngine"}'
ok_true "getSearchPreference existing key"
call getSearchPreference '{}'
ok_false "getSearchPreference missing key param fails"
call setSearchPreference '{"key":"us-test-pref","value":"v1"}'
ok_true "setSearchPreference create"
call setSearchPreference '{"key":"us-test-pref","value":"v2"}'
ok_true "setSearchPreference overwrite"
call getSearchPreference '{"key":"us-test-pref"}'
has "setSearchPreference overwrite visible" '"us-test-pref": "v2"'
call setSearchPreference '{"key":"us-test-pref"}'
ok_false "setSearchPreference missing value fails"
call getAllSearchPreference '{}'
ok_true "getAllSearchPreference returns"
has "getAllSearchPreference includes test key" '"us-test-pref": "v2"'
has_not "getAllSearchPreference hides databaseversion" '"databaseversion"'

# ---------------------------------------------------------------- search category CRUD
call addSearchItem '{"category":"search","id":"us-test-web","displayName":"US Test Web","url":"http://example.com/?q=#{searchTerms}","type":"web","enabled":true}'
ok_true "addSearchItem search valid"
call getUniversalSearchList '{}'
has "added search item listed" '"id": "us-test-web"'
call addSearchItem '{"category":"search","id":"us-test-web","displayName":"US Test Web","url":"http://example.com/","type":"web"}'
ok_false "addSearchItem duplicate same version rejected"
call addSearchItem '{"category":"search","id":"us-test-web","version":2,"displayName":"US Test Web v2","url":"http://example.com/v2","type":"web","enabled":true}'
ok_true "addSearchItem duplicate higher version replaces"
call getUniversalSearchList '{}'
has "version upgrade replaced item" '"US Test Web v2"'
call addSearchItem '{"category":"search","id":"us-test-nourl","displayName":"No URL","type":"web"}'
ok_false "addSearchItem missing url fails"
call addSearchItem '{"category":"search","id":"us-test-noname","url":"http://example.com/x","type":"web"}'
ok_false "addSearchItem missing displayName+icon fails"
call addSearchItem '{"category":"search","id":"us-test-app","displayName":"App NoParam","url":"com.example.app","type":"app"}'
ok_false "addSearchItem app without launchParam fails"
call updateSearchItem '{"category":"search","id":"us-test-web","enabled":false}'
ok_true "updateSearchItem disable"
call updateSearchItem '{"category":"search","id":"us-test-web"}'
ok_false "updateSearchItem missing enabled fails"
call updateSearchItem '{"id":"us-test-web","enabled":true}'
ok_false "updateSearchItem missing category fails"
call updateSearchItem '{"category":"bogus","id":"us-test-web","enabled":true}'
ok_false "updateSearchItem bad category fails"
call updateSearchItem '{"category":"search","id":"does-not-exist","enabled":true}'
ok_true "updateSearchItem nonexistent id is a no-op (documented)"
call updateSearchItem '{"category":"search","id":"us-test-web","enabled":true,"setDefault":true}'
ok_true "updateSearchItem setDefault"
call getSearchPreference '{"key":"defaultSearchEngine"}'
has "setDefault took effect" '"defaultSearchEngine": "us-test-web"'
call reorderSearchItem '{"category":"search","id":"us-test-web","toIndex":1}'
ok_true "reorderSearchItem valid"
call reorderSearchItem '{"category":"search","id":"does-not-exist","toIndex":1}'
ok_false "reorderSearchItem nonexistent id fails (out of range)"
call reorderSearchItem '{"category":"search","id":"us-test-web"}'
ok_false "reorderSearchItem missing toIndex fails"
call removeSearchItem '{"category":"search"}'
ok_false "removeSearchItem missing id fails"
call removeSearchItem '{"category":"search","id":"us-test-web"}'
ok_true "removeSearchItem search"
call getUniversalSearchList '{}'
has_not "removed search item gone" '"id": "us-test-web"'

# auto-generated id when none supplied
call addSearchItem '{"category":"search","displayName":"US AutoId","url":"http://auto.example.com/","type":"web"}'
ok_true "addSearchItem without id (auto User-N id)"
call getUniversalSearchList '{}'
AUTOID=$(echo "$RESP" | sed -n 's/.*"id": "\(User-[0-9]*\)".*/\1/p' | head -n 1)
if [ -n "$AUTOID" ]; then
	report pass "auto id generated ($AUTOID)"
	call removeSearchItem "{\"category\":\"search\",\"id\":\"$AUTOID\"}"
	ok_true "auto-id item removed"
else
	report fail "auto id generated"
fi

# ---------------------------------------------------------------- action category CRUD
NACT=$(section_count action)
call addSearchItem '{"category":"action","id":"us-test-action","displayName":"US Test Action","url":"com.example.testapp","launchParam":"text","enabled":true}'
ok_true "addSearchItem action valid"
call addSearchItem '{"category":"action","id":"us-test-action2","displayName":"No Param","url":"com.example.testapp2"}'
ok_false "addSearchItem action missing launchParam fails"
call updateSearchItem '{"category":"action","id":"us-test-action","enabled":false}'
ok_true "updateSearchItem action disable"
call reorderSearchItem "{\"category\":\"action\",\"id\":\"us-test-action\",\"fromIndex\":$NACT,\"toIndex\":0}"
ok_true "reorderActionProvider (computed fromIndex $NACT)"
call reorderSearchItem '{"category":"action","id":"us-test-action","fromIndex":999,"toIndex":0}'
ok_false "reorderActionProvider out-of-range fromIndex fails"
call removeSearchItem '{"category":"action","id":"us-test-action"}'
ok_true "removeSearchItem action"

# ---------------------------------------------------------------- dbsearch category CRUD + kind validation
NDB=$(section_count dbsearch)
call addSearchItem '{"category":"dbsearch","id":"com.example.dbtest","displayName":"US DB Test","displayFields":["title"],"dbQuery":{"from":"com.example.data:1","limit":10},"launchParam":"url","launchParamDbField":"url","batchQuery":false,"enabled":true}'
ok_true "addSearchItem dbsearch valid (own kind)"
call addSearchItem '{"category":"dbsearch","id":"com.example.dbevil","displayName":"Evil","displayFields":["x"],"dbQuery":{"from":"com.palm.contacts:1"}}'
ok_false "addSearchItem dbsearch non-privileged app querying com.palm kind is rejected"
call addSearchItem '{"category":"dbsearch","id":"com.palm.dbpriv","displayName":"Priv","displayFields":["x"],"dbQuery":{"from":"com.palm.contacts:1"},"enabled":true}'
ok_true "addSearchItem dbsearch privileged app may query com.palm kind"
call updateSearchItem '{"category":"dbsearch","id":"com.example.dbtest","enabled":false}'
ok_true "updateSearchItem dbsearch disable"
call reorderSearchItem "{\"category\":\"dbsearch\",\"id\":\"com.example.dbtest\",\"fromIndex\":$NDB,\"toIndex\":0}"
ok_true "reorderDBSearchItem (computed fromIndex $NDB)"
call removeSearchItem '{"category":"dbsearch","id":"com.example.dbtest"}'
ok_true "removeSearchItem dbsearch"
call removeSearchItem '{"category":"dbsearch","id":"com.palm.dbpriv"}'
ok_true "removeSearchItem dbsearch privileged"

# ---------------------------------------------------------------- updateAllSearchItems
for cat in search action dbsearch; do
	call updateAllSearchItems "{\"category\":\"$cat\",\"enabled\":false}"
	ok_true "updateAllSearchItems $cat disable"
	call updateAllSearchItems "{\"category\":\"$cat\",\"enabled\":true}"
	ok_true "updateAllSearchItems $cat enable"
done
call updateAllSearchItems '{"category":"bogus","enabled":true}'
ok_false "updateAllSearchItems bad category fails"
call getUniversalSearchList '{}'
echo "$RESP" | grep -q '"enabled": false' && report fail "updateAllSearchItems enable-all took effect" || report pass "updateAllSearchItems enable-all took effect"

# ---------------------------------------------------------------- malformed payloads
call updateSearchItem '{"category":'
echo "$RESP" | grep -q '"returnValue": true' && report fail "malformed JSON rejected" || report pass "malformed JSON rejected"
call addSearchItem '{}'
ok_false "addSearchItem empty object fails"

# ---------------------------------------------------------------- optional search (error paths)
call addOptionalSearchDesc '{}'
ok_false "addOptionalSearchDesc missing xmlUrl fails"
call addOptionalSearchDesc '{"xmlUrl":"notaurl"}'
ok_false "addOptionalSearchDesc unparsable URL fails"
call addOptionalSearchDesc '{"xmlUrl":"ftp://example.com/x.xml"}'
ok_false "addOptionalSearchDesc non-http scheme fails"
call removeOptionalSearchItem '{"id":"bogus"}'
ok_false "removeOptionalSearchItem unknown id fails"
call getOptionalSearchList '{}'
ok_true "getOptionalSearchList returns"

# ---------------------------------------------------------------- optional search pipeline (download + parse)
if [ -n "$FIXTURE_URL" ]; then
	if luna-send -n 1 -f luna://com.palm.downloadmanager/listPending '{}' 2>&1 | grep -q returnValue; then
		call addOptionalSearchDesc "{\"xmlUrl\":\"$FIXTURE_URL\"}"
		ok_true "addOptionalSearchDesc fixture URL accepted"
		FOUND=""
		i=0
		while [ $i -lt 20 ]; do
			call getOptionalSearchList '{}'
			if echo "$RESP" | grep -q ClaudeSearch; then FOUND=1; break; fi
			sleep 1; i=$((i+1))
		done
		if [ -n "$FOUND" ]; then
			report pass "opensearch XML downloaded and parsed (${i}s)"
			has "parseXml assembled Param query string" 'q={searchTerms}&src=luneos-test'
			has "parseXml captured suggestion url" 'sugg?q={searchTerms}'
			has "parseImage wrote icon file" '\.ico'
			OSID=$(echo "$RESP" | sed -n 's/.*"id": "\([^"]*searchplugins[^"]*\)".*/\1/p' | head -n 1)
			# migrate optional item into the main list, then back out
			call updateAllSearchItems '{"category":"search","enabled":true}'
			ok_true "updateAllSearchItems migrates optional items"
			call getUniversalSearchList '{}'
			has "migrated opensearch item in main list" 'ClaudeSearch'
			call getOptionalSearchList '{}'
			has_not "migrated item left optional list" 'ClaudeSearch'
			call removeSearchItem "{\"category\":\"search\",\"id\":\"$OSID\"}"
			ok_true "migrated item removed from main list"
			call getOptionalSearchList '{}'
			has "un-migrated item back in optional list" 'ClaudeSearch'
			call removeOptionalSearchItem "{\"id\":\"$OSID\"}"
			ok_true "removeOptionalSearchItem fixture"
			call getOptionalSearchList '{}'
			has_not "fixture gone from optional list" 'ClaudeSearch'
		else
			report fail "opensearch XML downloaded and parsed (timeout)"
		fi
		call clearOptionalSearchList '{}'
		ok_true "clearOptionalSearchList"
	else
		report skip "opensearch pipeline (com.palm.downloadmanager not available)"
	fi
else
	report skip "opensearch pipeline (no fixture URL given)"
fi

# ---------------------------------------------------------------- subscription push
luna-send -i -f "$U/getUniversalSearchList" '{"subscribe":true}' > /tmp/us-sub.out 2>&1 &
SUBPID=$!
sleep 2
call addSearchItem '{"category":"search","id":"us-sub-test","displayName":"Sub Test","url":"http://example.com/s","type":"web"}'
sleep 2
kill $SUBPID 2>/dev/null; wait $SUBPID 2>/dev/null
N=$(grep -c '"returnValue"' /tmp/us-sub.out)
[ "$N" -ge 2 ] && report pass "subscription push on list change ($N responses)" || { RESP=$(cat /tmp/us-sub.out); report fail "subscription push on list change"; }
grep -q '"event"' /tmp/us-sub.out && report pass "push carries event field" || { RESP=$(cat /tmp/us-sub.out); report fail "push carries event field"; }
luna-send -i -f "$U/getAllSearchPreference" '{"subscribe":true}' > /tmp/us-sub2.out 2>&1 &
SUBPID=$!
sleep 2
call setSearchPreference '{"key":"us-test-pref","value":"v3"}'
sleep 2
kill $SUBPID 2>/dev/null; wait $SUBPID 2>/dev/null
N=$(grep -c '"returnValue"' /tmp/us-sub2.out)
[ "$N" -ge 2 ] && report pass "subscription push on pref change ($N responses)" || { RESP=$(cat /tmp/us-sub2.out); report fail "subscription push on pref change"; }
call removeSearchItem '{"category":"search","id":"us-sub-test"}'
ok_true "subscription test item removed"

# ---------------------------------------------------------------- stress
echo "--- stress: 25 CRUD iterations across categories..."
i=0; STRESS_OK=1
while [ $i -lt 25 ]; do
	call addSearchItem '{"category":"search","id":"us-stress","displayName":"S","url":"http://s.example.com/","type":"web","enabled":true}'
	echo "$RESP" | grep -q '"returnValue": true' || STRESS_OK=0
	call updateSearchItem '{"category":"search","id":"us-stress","enabled":false}'
	call reorderSearchItem '{"category":"search","id":"us-stress","toIndex":1}'
	call removeSearchItem '{"category":"search","id":"us-stress"}'
	echo "$RESP" | grep -q '"returnValue": true' || STRESS_OK=0
	call addSearchItem '{"category":"action","id":"us-stress-a","displayName":"A","url":"com.s.a","launchParam":"text"}'
	call removeSearchItem '{"category":"action","id":"us-stress-a"}'
	call setSearchPreference "{\"key\":\"us-stress-pref\",\"value\":\"$i\"}"
	call getAllSearchPreference '{}'
	i=$((i+1))
done
[ "$STRESS_OK" = 1 ] && report pass "stress loop: all add/remove cycles returned true" || report fail "stress loop: all add/remove cycles returned true"

# ---------------------------------------------------------------- stability
NEWPID=$(pidof LunaUniversalSearchMgr)
[ "$NEWPID" = "$SVC_PID" ] && report pass "service pid unchanged (no crash/restart)" || { RESP="pid $SVC_PID -> $NEWPID"; report fail "service pid unchanged (no crash/restart)"; }
systemctl is-active -q luna-universalsearchmgr && report pass "systemd unit active" || report fail "systemd unit active"
RSS_AFTER=$(awk '/VmRSS/{print $2}' /proc/$NEWPID/status)
echo "info: VmRSS ${RSS_BEFORE}kB -> ${RSS_AFTER}kB (delta $((RSS_AFTER-RSS_BEFORE))kB over ~250 calls)"

# ---------------------------------------------------------------- restore snapshot
echo "--- restoring enabled-states and default engine..."
awk '
/"UniversalSearchList":/ {cat="search"}
/"ActionList":/          {cat="action"}
/"DBSearchItemList":/    {cat="dbsearch"}
/"id": "/      {id=$0; sub(/.*"id": "/,"",id); sub(/".*/,"",id)}
/"enabled": /  {en=($0 ~ /true/) ? "true" : "false"; if (cat != "" && id != "") print cat, id, en}
' /tmp/us-snapshot.json | while read cat id en; do
	luna-send -n 1 -f "$U/updateSearchItem" "{\"category\":\"$cat\",\"id\":\"$id\",\"enabled\":$en}" >/dev/null 2>&1
done
if [ -n "$ORIG_ENGINE" ]; then
	call setSearchPreference "{\"key\":\"defaultSearchEngine\",\"value\":\"$ORIG_ENGINE\"}"
	ok_true "default search engine restored ($ORIG_ENGINE)"
fi
rm -f /tmp/us-sub.out /tmp/us-sub2.out /tmp/us-snapshot.json

echo
echo "=== RESULT: $PASS passed, $FAIL failed, $SKIP skipped ==="
exit $FAIL
