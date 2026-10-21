# loup-cmd-yq

[yq](https://github.com/kislyuk/yq) written as a
[Loup](https://code-craft.ai/references/loup) script: it reads YAML files
and runs a [jq](https://jqlang.org) filter on every document, printing the
results as JSON, raw text or YAML. The filter language is a substantial
jq subset (paths, pipes, construction, operators, conditionals, variables,
string interpolation, formats and about seventy builtins), evaluated with
generators.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is a `host.scripted` command: an `.lpscr` entry script in `bin/`
over `.lpscr` modules in `lib/`, run with `loup run`.

## Requirements

- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later (`loup` and `loup-bootstrap` on `PATH`); see [Installing Loup Lite](#installing-loup-lite).
- `make` and `bash` for the checks and tests. No C compiler: nothing is built.

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. Commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Usage

```sh
make run ARGS="-c .services[0] tests/fixtures/services.yaml"   # loup run bin/yq.lpscr -- ARGS
make ci                                                        # check, unit tests, end-to-end tests
```

The script is executable (`#!/usr/bin/env -S loup run`). Short options
(`-r`, `-c`, `-y`, ...) pass straight through `loup run`; long ones
(`--arg`, `--indent`, `--yaml-output`) must follow a `--`, which `make run`
adds for you. With [`tests/fixtures/services.yaml`](tests/fixtures/services.yaml),
two YAML documents (a shop with three services, then an empty staging
setup):

```text
$ ./bin/yq.lpscr '.services[].name' services.yaml
"web"
"api"
"db"
$ ./bin/yq.lpscr -r '.services[] | "\(.name)\t\(.replicas)\t\(.image)"' services.yaml
web	2	nginx:1.27
api	3	shop/api:2.4.1
db	1	postgres:16
$ ./bin/yq.lpscr -c '.services | map(select(.replicas > 1) | {name, ports})' services.yaml
[{"name":"web","ports":[80,443]},{"name":"api","ports":[8080]}]
[]
$ ./bin/yq.lpscr -y '.services[1] | values | {name, env, command}' services.yaml
name: api
env:
  LOG_LEVEL: debug
  FEATURE_X: true
command: |
  ./api serve
  --port 8080
$ ./bin/yq.lpscr -s -c 'map(.name)' services.yaml
["shop","staging"]
$ ./bin/yq.lpscr '[.. | numbers] | add' services.yaml
8913.5
null
$ ./bin/yq.lpscr -- --arg svc api '.services[]? | select(.name == $svc) | .image' services.yaml
"shop/api:2.4.1"
$ ./bin/yq.lpscr '.name + 1' services.yaml; echo "status $?"
yq: error: string ("shop") and number (1) cannot be added
yq: error: string ("staging") and number (1) cannot be added
status 5
$ ./bin/yq.lpscr '.services[' services.yaml; echo "status $?"
yq: error: syntax error: unexpected end of filter
yq: 1 compile error
status 3
```

### Options

| Option | Meaning |
|---|---|
| `-y`, `--yaml-output` | write results as YAML, separated by `---` lines |
| `-r`, `--raw-output` | write strings without quotes |
| `-j`, `--join-output` | like `-r`, without a newline after each result |
| `-c`, `--compact-output` | one line of JSON per result |
| `--indent N` | indent JSON by N spaces, 0 to 7 (default 2; 0 is compact) |
| `-S`, `--sort-keys` | sort the keys of every object |
| `-s`, `--slurp` | read every document of every file into one array |
| `-n`, `--null-input` | run the filter once on `null`, reading nothing |
| `-e`, `--exit-status` | status 1 if the last result is `false` or `null`, 4 if there was none |
| `--arg NAME VALUE` | set `$NAME` to the string VALUE |
| `-h`, `--help` / `-V`, `--version` | help text / `yq (loup-cmd-yq) 0.1.0` |

Short options combine (`-rc`); with no FILE, or a FILE of `-`, yq reads
standard input.

### Filters

| Kind | Supported |
|---|---|
| Paths | `.`, `..`, `.name`, `."name"`, `.[EXPR]`, `.[A:B]`, `.[]`, postfix `?` |
| Combining | `\|`, `,`, `( )`, `[ ]`, `{a, "b": X, (EXPR): Y, $var}` |
| Operators | `+ - * / %`, `== != < <= > >=`, `and`, `or`, `//`, unary `-` |
| Control | `if A then B elif C then D else E end`, `EXPR as $name \| BODY` |
| Strings | escapes, `"\(EXPR)"` interpolation, `@json @text @csv @tsv @sh`, `@sh "rm \(.)"` |
| Builtins | `empty error not length keys keys_unsorted values has type add any all map map_values select recurse paths to_entries from_entries with_entries sort sort_by group_by unique unique_by min max min_by max_by reverse flatten range first last limit tostring tonumber tojson ascii_downcase ascii_upcase ltrimstr rtrimstr startswith endswith split join contains input_filename numbers strings booleans nulls arrays objects iterables scalars` |

YAML input: block mappings and sequences (also a sequence in its key's
column and `- key: value` items), flow collections (`[a, b]`, `{k: v}`, over
several lines), `|` and `>` block scalars with `-`/`+` chomping,
multi-line plain scalars, single- and double-quoted keys and values,
comments, and several documents per file.

Exit status: `0` success, `1` last result false or null (`-e`), `2` usage
error or unreadable input, `3` filter syntax error, `4` no result (`-e`),
`5` error while running the filter.

## Differences from the original

- A jq subset: no assignment (`=`, `|=`, `+=`, ...), path expressions
  (`path(f)`, `getpath`, `setpath`, `del`), `reduce`, `foreach`, `def`,
  `try ... catch` (the postfix `?` and `//` are there), `label`,
  destructuring (`. as [$a]`), regular expressions (`test`, `match`, `sub`),
  `$ENV`/`env`, `input`/`inputs`, `--argjson`, `--raw-input`, `--tab`.
- YAML: no anchors, aliases, merge keys (`<<`) or tags; scalars follow YAML
  1.2 (`yes` and `on` are strings, `010` is 10); integers longer than 18
  digits become floats; tabs do not indent.
- `-y` writes its own block YAML (it differs from PyYAML's in details such
  as line wrapping); there is no `-Y`, `--width` or `--indentless`.
- Errors read `yq: error: MESSAGE` without jq's `(at FILE:N)`; YAML errors
  name the file and line.
- `from_entries` also takes `k`, `v` and `name` keys, and `ltrimstr` /
  `rtrimstr` leave non-strings alone, as in jq 1.6 and 1.7.
- Under the self-hosted `loup run` a generator runs to its end before the
  loop over it starts, so `limit` and `first(f)` do not stop the work early
  (the results are right, only slower), and an endless stream would not end.

## What this example shows

- **Generators.** The evaluator is a `gen func run(node, input, env):
  Iterable[Any]` that yields each output of a filter: a pipe runs its right
  side on every output of its left, `..` is a recursive generator, object
  construction and string interpolation yield one result per combination,
  and the inputs themselves are a generator over files and documents.
- **Errors carried as values.** A generator never lets an exception leave
  its body (Stage0 cannot catch one that does, and the self-hosted
  interpreter would lose the outputs before it): it yields a `Failure`, and
  each consumer throws it again with `unwrap()`.
- **`Any`, safe casts and type matching, recursively.** YAML values are
  `Any`; `match v { int(n) => ..., string(s) => ... }` and
  `v as? dict[string, Any]` tell them apart, and jq's order, deep
  equality, canonical keys, `-S`, `normalize` and the YAML writer all
  recurse over them.
- **A small parser.** A lexer and a recursive-descent parser for the jq
  subset into a recursive `enum Node`, with string interpolation parsed by
  nested parsers and scope and arity checks at compile time.
- **`data.yaml`** with the YAML it lacks handled around it, **`system.json`**
  (`stringifyIndented`, `stringify`) for output, and **`system.collections`**
  (`reduce`, `any`, `all`, `rangeFrom`, `rangeStep`, `reverse`, `flatten`,
  `distinctBy`, `groupBy`, `sortBy`, `toEntries`, `fromEntries`,
  `mapValues`, `filterKeys`, `mergeWith`, `map`) for the builtins.
- Also: a deferred import between the evaluator and the builtins, lambdas
  passed to the collection helpers and a sort comparator, `global` state in
  the entry script, `safe func`, sets for the builtin table, and a class
  marker (`Missing`) tested with `is`.

## Layout

```text
bin/yq.lpscr                # the command (host.scripted entry script)
lib/appinfo.loup            # name, version, exit statuses
lib/usage.loup              # --help and --version text
lib/args.lpscr              # command line
lib/lexer.lpscr             # filter tokens
lib/ast.lpscr               # enum Node, the filter tree
lib/parser.lpscr            # recursive-descent parser
lib/eval.lpscr              # the evaluator (generators), paths and indexing
lib/builtins.lpscr          # builtins and formats
lib/values.lpscr            # jq's types, order, equality, arithmetic
lib/flow.lpscr              # YAML flow collections and plain scalars
lib/yamlin.lpscr            # YAML documents around data.yaml
lib/output.lpscr            # JSON, raw and YAML output
tests/*_test.lpscr          # unit tests (make test)
tests/e2e.sh                # end-to-end tests with loup run (make e2e)
tests/fixtures/services.yaml  # sample input: two documents
specs/yq/                   # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every check and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
