#!/usr/bin/env bash
# End-to-end tests: run yq, xq and tomlq with `loup run` and compare their
# standard output, standard error and exit status with the expected ones,
# on tests/fixtures/services.yaml, pom.xml and pyproject.toml and on small
# inputs written here.
#
# usage: tests/e2e.sh [LOUP]     (run from the repository root)

set -u
LOUP=${1:-loup}
SCRIPT=bin/yq.lpscr
YAML=tests/fixtures/services.yaml
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
pass=0
fail=0

# run ARGS...: the script $SCRIPT with ARGS after `--` (so long options reach it),
# standard input from the file named by $IN (default /dev/null), output to
# $TMP/out and $TMP/err. Returns its exit status.
run() {
    "$LOUP" run "$SCRIPT" -- "$@" < "${IN:-/dev/null}" > "$TMP/out" 2> "$TMP/err"
}

report() {
    local name=$1 status=$2 want_status=$3 want_file=$4 got_file=$5
    if [ "$status" -eq "$want_status" ] && cmp -s "$want_file" "$got_file"; then
        pass=$((pass + 1))
    else
        fail=$((fail + 1))
        echo "FAIL: $name (exit $status, expected $want_status)"
        diff "$want_file" "$got_file" | sed 's/^/    /' | head -20
        sed 's/^/    stderr: /' "$TMP/err" | head -5
    fi
}

# check NAME STATUS EXPECTED_STDOUT ARGS...
check() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/out"
}

# check_err NAME STATUS EXPECTED_STDERR ARGS...
check_err() {
    local name=$1 want_status=$2
    printf '%s' "$3" > "$TMP/want"
    shift 3
    run "$@"
    report "$name" $? "$want_status" "$TMP/want" "$TMP/err"
}

# --- paths and output ---------------------------------------------------

check "field, both documents" 0 $'"shop"\n"staging"\n' .name "$YAML"
check "pretty JSON" 0 '{
  "name": "web",
  "image": "nginx:1.27",
  "ports": [
    80,
    443
  ],
  "replicas": 2,
  "env": {
    "LOG_LEVEL": "info",
    "CACHE_TTL": 300
  }
}
' '.services[0] | select(.)' "$YAML"
check "iterate and pipe" 0 $'"web"\n"api"\n"db"\n' '.services[]? | .name' "$YAML"
check "compact" 0 $'{"cpu":1.5,"memory":"512Mi"}\n' -c '.limits | values' "$YAML"
check "indent 4, sorted keys" 0 '{
    "LOG_LEVEL": "info",
    "CACHE_TTL": 300
}
' --indent 4 '.services[0].env | values' "$YAML"
check "sorted keys" 0 $'{"CACHE_TTL":300,"LOG_LEVEL":"info"}\n' -cS '.services[0].env | values' "$YAML"
check "raw strings" 0 $'web\tnginx:1.27\napi\tshop/api:2.4.1\ndb\tpostgres:16\n' -r '.services[]? | "\(.name)\t\(.image)"' "$YAML"
check "join output" 0 'shopstaging' -j .name "$YAML"
check "block scalar" 0 $'./api serve\n--port 8080\n\n' -r '.services[1].command | values' "$YAML"
check "folded scalar" 0 $'"Primary database. Backed up nightly.\\n"\n' '.services[2].notes | values' "$YAML"
check "flow collections" 0 $'[80,443]\n{"LOG_LEVEL":"debug","FEATURE_X":true}\n' -c '.services[0].ports, .services[1].env | values' "$YAML"
check "quotes and comments" 0 $'"it\'s quoted"\n"http://example.com/#top"\n' '."quoted key", .url | values' "$YAML"
check "YAML output" 0 'name: shop
services:
  - name: web
    replicas: 2
  - name: api
    replicas: 3
  - name: db
    replicas: 1
---
name: staging
services: []
' -y '{name, services: [.services[] | {name, replicas}]}' "$YAML"
check "YAML block and quoting" 0 'command: |
  ./api serve
  --port 8080
version: 2.4.1
' --yaml-output '.services[1] | values | {command, version: (.image | split(":")[1])}' "$YAML"

# --- filters --------------------------------------------------------------

check "select and map" 0 $'["web","api"]\n[]\n' -c '[.services[] | select(.replicas > 1) | .name]' "$YAML"
check "add" 0 $'6\nnull\n' '.services | map(.replicas) | add' "$YAML"
check "sort_by and group_by" 0 $'["db","web","api"]\n[[1],[2],[3]]\n' -c '.services | values | select(length > 0) | (sort_by(.replicas) | map(.name)), (group_by(.replicas) | map(map(.replicas)))' "$YAML"
check "keys" 0 $'["debug","limits","name","owner","quoted key","services","url","version"]\n' -c 'select(.version) | keys' "$YAML"
check "alternative" 0 $'"nobody"\n"nobody"\n' '.owner // "nobody"' "$YAML"
check "if and variables" 0 $'"shop: 3 services"\n"staging: 0 services"\n' '(.services | length) as $n | "\(.name): \($n) services"' "$YAML"
check "recursive descent" 0 $'[3,80,443,2,300,8080,3,1,1.5]\n[]\n' -c '[.. | numbers]' "$YAML"
check "csv" 0 $'"web",2\n"api",3\n"db",1\n' -r '.services[]? | [.name, .replicas] | @csv' "$YAML"
check "to_entries" 0 $'cpu=1.5\nmemory=512Mi\n' -r '.limits | values | to_entries[] | "\(.key)=\(.value)"' "$YAML"

# --- inputs -------------------------------------------------------------------

check "slurp" 0 $'["shop","staging"]\n' -c -s 'map(.name)' "$YAML"
check "null input and --arg" 0 $'"good morning, world"\n' -n --arg who world '"good morning, \($who)"'
IN=$YAML check "standard input" 0 $'2\n' 'select(.version) | .services | map(select(.ports | length > 0)) | length'
printf 'items:\n- name: a\n  tags: [x, y]\n- name: b\n  tags: []\n' > "$TMP/list.yaml"
check "unindented sequence" 0 $'"a"\n' -c '.items[] | select(.tags | length > 0) | .name' "$TMP/list.yaml"
printf -- '- 1\n- 2\n' > "$TMP/seq.yaml"
check "two files" 0 $'"shop"\n"staging"\n3\n' '.name? // add' "$YAML" "$TMP/seq.yaml"
check "input_filename" 0 $'"tests/fixtures/services.yaml"\n' 'select(.version) | input_filename' "$YAML"

# --- errors and exit statuses ---------------------------------------------------

check "results before an error" 5 $'"web"\nnull\n' '.services[0].name, error("stop")' "$YAML"
check_err "error message" 5 $'yq: error: stop\nyq: error: stop\n' '.services[0].name, error("stop")' "$YAML"
check_err "type error" 5 $'yq: error: string ("shop") and number (1) cannot be added\nyq: error: string ("staging") and number (1) cannot be added\n' '.name + 1' "$YAML"
check "optional" 0 $'[]\n' -n -c '[1 | .[]?]'
check_err "syntax error" 3 $'yq: error: syntax error: unexpected end of filter\nyq: 1 compile error\n' '.services[' "$YAML"
check_err "unknown function" 3 $'yq: error: nosuch/0 is not defined\nyq: 1 compile error\n' 'nosuch' "$YAML"
check_err "undefined variable" 3 $'yq: error: $who is not defined\nyq: 1 compile error\n' '$who' "$YAML"
check_err "missing file" 2 $'yq: nope.yaml: No such file or directory\n' . nope.yaml
check "missing file, others read" 2 $'"shop"\n"staging"\n' .name nope.yaml "$YAML"
check_err "directory" 2 $'yq: tests: Is a directory\n' . tests
printf 'a: 1\n---\nb: [1, 2\nc: 3\n---\nd:\n  e: 1\n f: 2\n' > "$TMP/bad.yaml"
check_err "YAML errors" 2 "yq: $TMP/bad.yaml:3: unterminated flow collection
yq: $TMP/bad.yaml:8: unexpected indent
" -c . "$TMP/bad.yaml"
check "good documents still read" 2 $'{"a":1}\n' -c . "$TMP/bad.yaml"
check "exit status: true" 0 $'true\n' -e -n 'true'
check "exit status: false" 1 $'false\n' -e -n 'false'
check "exit status: no output" 4 '' -e -n 'empty'

HINT="Try 'yq --help' for more information."
check_err "no filter" 2 "yq: no filter given
$HINT
"
check_err "unknown option" 2 "yq: invalid option -- 'x'
$HINT
" -x .
check_err "bad indent" 2 "yq: --indent takes a number from 0 to 7, not '9'
$HINT
" --indent 9 .
check "version" 0 $'yq (loup-cmd-yq) 0.1.0\n' --version
run --help
status=$?
head -1 "$TMP/out" > "$TMP/got"
printf 'usage: yq [OPTION]... FILTER [FILE]...\n' > "$TMP/want"
report "help" $status 0 "$TMP/want" "$TMP/got"
check_err "no XML options in yq" 2 "yq: unrecognized option '--xml-force-list'
$HINT
" --xml-force-list item . "$YAML"

# --- xq: XML input -------------------------------------------------------------

SCRIPT=bin/xq.lpscr
POM=tests/fixtures/pom.xml
check "xq: elements, repeated" 0 $'org.springframework.boot:spring-boot-starter-web:3.3.4\ncom.fasterxml.jackson.core:jackson-databind:${jackson.version}\norg.junit.jupiter:junit-jupiter:5.11.2\n' -r '.project.dependencies.dependency[] | "\(.groupId):\(.artifactId):\(.version)"' "$POM"
check "xq: select" 0 $'["spring-boot-starter-web","jackson-databind"]\n' -c '[.project.dependencies.dependency[] | select(.scope != "test") | .artifactId]' "$POM"
check "xq: attributes, entities, CDATA" 0 '{
  "name": "Shop API & Admin",
  "description": "Orders, carts & <b>stock</b>.",
  "java": "21",
  "xmlns": "http://maven.apache.org/POM/4.0.0"
}
' '.project | {name, description, java: .properties["java.version"], xmlns: ."@xmlns"}' "$POM"
check "xq: one element is an object" 0 $'"object"\n' '.project.build.plugins.plugin | type' "$POM"
check "xq: --xml-force-list" 0 $'"array"\n' --xml-force-list plugin '.project.build.plugins.plugin | type' "$POM"
check "xq: YAML output" 0 'plugins:
  plugin:
    groupId: org.apache.maven.plugins
    artifactId: maven-compiler-plugin
    configuration:
      "@release": "21"
' -y '.project.build' "$POM"
printf '<feed>\n  <entry id="1"/>\n  <entry id="2">two</entry>\n</feed>\n' > "$TMP/feed.xml"
IN=$TMP/feed.xml check "xq: standard input, slurp" 0 $'[{"feed":{"entry":[{"@id":"1"},{"@id":"2","#text":"two"}]}}]\n' -s -c .
printf '<a>\n  <b>text</c>\n</a>\n' > "$TMP/bad.xml"
check_err "xq: not well-formed" 2 "xq: $TMP/bad.xml:2: mismatched closing tag for <b>
" . "$TMP/bad.xml"
printf '<a/>\n<b/>\n' > "$TMP/two.xml"
check_err "xq: two roots" 2 "xq: $TMP/two.xml:2: junk after document element
" . "$TMP/two.xml"
check "xq: other files still read" 2 $'"2.4.1"\n' '.project.version' "$TMP/bad.xml" "$POM"
check "xq: version" 0 $'xq (loup-cmd-yq) 0.1.0\n' --version
check_err "xq: usage error" 2 "xq: option '--xml-force-list' requires an argument
Try 'xq --help' for more information.
" . --xml-force-list

# --- tomlq: TOML input -----------------------------------------------------------

SCRIPT=bin/tomlq.lpscr
TOML=tests/fixtures/pyproject.toml
check "tomlq: array" 0 $'httpx>=0.27\npydantic>=2.6,<3\nrich\n' -r '.project.dependencies[]' "$TOML"
check "tomlq: interpolation" 0 $'shop-client 1.8.0\n' -r '.project | "\(.name) \(.version)"' "$TOML"
check "tomlq: arrays of tables" 0 $'["rich.*","httpx.*"]\n' -c '[.tool.mypy.overrides[] | .module]' "$TOML"
check "tomlq: YAML output" 0 'ruff:
  line-length: 100
  lint:
    select:
      - E
      - F
      - I
mypy:
  overrides:
    - module: rich.*
      ignore_missing_imports: true
    - module: httpx.*
      follow_imports: skip
' -y '.tool' "$TOML"
printf 'when = 1979-05-27T07:32:00Z\nport = 0x1F90\n' > "$TMP/types.toml"
check "tomlq: dates and numbers" 0 $'{"when":"1979-05-27T07:32:00Z","port":8080}\n' -c . "$TMP/types.toml"
printf '[server]\nport = 8080\nport = 8081\n' > "$TMP/bad.toml"
check_err "tomlq: duplicate key" 2 "tomlq: $TMP/bad.toml:3: duplicate key 'port'
" . "$TMP/bad.toml"
check "tomlq: version" 0 $'tomlq (loup-cmd-yq) 0.1.0\n' --version
run --help
status=$?
head -1 "$TMP/out" > "$TMP/got"
printf 'usage: tomlq [OPTION]... FILTER [FILE]...\n' > "$TMP/want"
report "tomlq: help" $status 0 "$TMP/want" "$TMP/got"

echo "e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
