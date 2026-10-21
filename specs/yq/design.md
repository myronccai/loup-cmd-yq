# Design: yq

## Overview

`bin/yq.lpscr` is a `host.scripted` script and the only code that reads
files, prints and exits. It parses the command line, compiles the filter
(before reading anything, so a syntax error costs nothing else), then runs
the filter on each YAML document of each input and prints the results as
they come. Everything else is in `lib/`, as `host.scripted` modules (the
values are `Any`, the streams are generators) plus two `host.dual` modules
of constants and text.

```text
FILTER ─ tokenize ─► tokens ─ Parser ─► Node tree (lib/ast.lpscr)
FILE ─ readText ─► documents() ─ Preparer ─ data.yaml.parse ─ normalize ─► values
value ─ run(node, value, env) ─► stream of results ─ render (JSON | raw | YAML) ─► stdout
```

## Modules

| Module | Mode | Contents |
|---|---|---|
| `bin/yq.lpscr` | scripted | top level: options, compile, inputs generator, output, exit status |
| `lib/appinfo.loup` | dual | name, version, jq's exit statuses |
| `lib/usage.loup` | dual | `usage()`, `version_line()` |
| `lib/args.lpscr` | scripted | `Options`, `parse_args`, `parse_indent` |
| `lib/lexer.lpscr` | scripted | `TokKind`, `Token`, `FilterSyntaxError`, `tokenize`, `skip_interpolation` |
| `lib/ast.lpscr` | scripted | `enum Node` (recursive) |
| `lib/parser.lpscr` | scripted | `Parser` (recursive descent), `compile`, string decoding |
| `lib/eval.lpscr` | scripted | `Env`, `gen func run`, `descend`, `children`, `index_value`, `slice_value` |
| `lib/builtins.lpscr` | scripted | `BUILTINS`, `gen func call_builtin`, sorting, grouping, formats |
| `lib/values.lpscr` | scripted | `JqError`, `Failure`, `kind`, `truthy`, `compare`, `equal`, `canonical`, arithmetic |
| `lib/flow.lpscr` | scripted | `scalar_value`, `parse_flow` (`FlowReader`) |
| `lib/yamlin.lpscr` | scripted | `documents`, `Preparer`, `normalize`, `read_values` |
| `lib/output.lpscr` | scripted | `Style`, `render`, `to_yaml` |

### Filters

The lexer keeps a string's body as written; the parser decodes escapes and
parses each `\(...)` with a parser of its own. The parser is recursive
descent with jq's precedence (`|` < `,` < `//` < `or` < `and` <
comparisons < `+ -` < `* / %` < unary `-` < postfix < terms) and checks,
while parsing, that every builtin call exists with its arity (`BUILTINS`, a
set of `name/arity`) and every `$variable` is in scope (`--arg` names and
enclosing `as` bindings). The tree is a recursive `enum Node` with payloads
(`Pipe(left: Node, right: Node)`, `Call(name: string, args: list[Node])`).

### Evaluation

A jq filter maps one input to a stream of outputs, so `run(node, input,
env)` is a generator (`gen func ...: Iterable[Any]`) that matches the node
and yields outputs, recursing into the node's parts. Values are `Any`:
`kind()` tells them apart with type patterns (`match v { int(n) => ...,
string(s) => ... }`) and the safe casts `v as? list[Any]` and
`v as? dict[string, Any]`; `compare()` gives jq's total order by recursing
over arrays and objects, and decides `==`, `sort`, `min`, `unique` and
`group_by`. `canonical()` (JSON with sorted keys and whole floats as
integers) keys values in dictionaries.

Errors travel in the stream. A generator catches `JqError` in its own body,
yields a `Failure` and stops; its consumer calls `unwrap()` on every item,
which throws the error again inside the consumer's body. This keeps the
outputs before an error (`(1, error("x"), 2)?` gives 1) under both
interpreters: Stage0 cannot catch an exception that leaves a generator,
and the self-hosted `loup run` runs a generator to its end before the loop
over it starts.

Builtins live in `lib/builtins.lpscr`, which needs `run` from
`lib/eval.lpscr` while eval calls `call_builtin`: the cycle is broken with
`from .eval defer import (...)`. List and dict work goes through
`system.collections`: `reduce` (add), `any`/`all`, `rangeFrom`/`rangeStep`
(range), `reverse`, `flatten`, `distinctBy` (unique), `groupBy`
(group_by, keyed by canonical text), `sortBy` (keys), `toEntries` /
`fromEntries` (to_entries, from_entries), `mapValues` + `filterKeys`
(map_values), `mergeWith` (`+` and `*` on objects) and `map`.

### YAML input

`data.yaml` reads block mappings and sequences of scalars. Around it,
`documents()` splits a file at `---`, and `Preparer` rewrites each
document into the subset data.yaml reads: a sequence that starts in its
key's column moves two columns right, a sequence item that starts a
mapping or another sequence (`- name: a`) puts its content on a line of
its own, and what data.yaml cannot read (flow collections, `|`/`>` block
scalars, multi-line plain scalars, quoted keys and values, a `#` inside a
plain value, integers too long for 64 bits) is read here (`lib/flow.lpscr`)
and replaced by a placeholder word. `normalize()` rebuilds the parsed
value recursively, putting the placeholders' values back (keys included)
and leaving plain values that `system.json` can write. An unreadable
document comes out of `read_values()` as an `InputError` value, with the
line of the original file, and the documents around it still read.

### Output

`render()` writes JSON with `system.json.stringifyIndented` (or
`stringify` for `-c` and `--indent 0`), a raw string for `-r`/`-j`, or YAML
from `to_yaml()`, which recurses over the value: mappings as `key: value`,
sequences as `- item` (an item's first line shares the dash), multi-line
strings as `|` blocks, and strings quoted with JSON escapes when YAML would
not read them back unchanged. `-S` sorts keys first.

## Differences from the original

- A subset of jq: no assignment (`=`, `|=`, `+=`, ...), path expressions
  (`path(f)`, `getpath`, `setpath`, `del`; `paths` is there), `reduce`, `foreach`,
  `def`, `try`/`catch` (the postfix `?` is supported), `label`,
  destructuring (`. as [$a]`), regular expressions, `$ENV`, `input`/`inputs`
  or SQL-style builtins.
- YAML: no anchors, aliases, merge keys or tags; YAML 1.2 scalars, so `yes`
  and `on` are strings and `010` is 10; tabs do not indent.
- `-y` writes block YAML of its own (PyYAML's details, such as line
  wrapping, differ); there is no `-Y` round trip, `--width` or
  `--indentless`.
- Error messages start with `yq: error:` (jq's start with `jq: error (at
  FILE:N):`); YAML errors give the file and line.
- `from_entries` also accepts `k`/`v` and `name` keys (jq 1.6/1.7); `ltrimstr`
  and `rtrimstr` leave non-strings unchanged (jq 1.7).

## Error handling

- Usage errors: `yq: MESSAGE` and the `Try` hint, status 2.
- Filter syntax errors: `yq: error: MESSAGE` and `yq: 1 compile error`,
  status 3, before any input is read.
- Inputs: a missing file or a directory is reported (`exists`/`isDir` are
  checked first: the self-hosted `loup run` cannot catch `IoError`), an
  unreadable YAML document is reported with its line; the rest is still
  read and the status is 2.
- Filter errors: the results before the error are printed, then
  `yq: error: MESSAGE`; the next input is still processed; status 5.
- `-e`: 1 when the last result is false or null, 4 when there was none.

## Testing

- `tests/eval_test.lpscr`: paths, construction, operators, conditionals,
  variables, errors in the stream, `?` and `//`, every group of builtins.
- `tests/parser_test.lpscr`: tokens, escapes and interpolation, precedence,
  syntax errors.
- `tests/values_test.lpscr`: types, order, equality, canonical text,
  arithmetic and its errors.
- `tests/yamlin_test.lpscr`: documents, block structure, scalars, block
  scalars, flow collections, error lines.
- `tests/output_test.lpscr`, `tests/args_test.lpscr`.
- `tests/e2e.sh`: the script under `loup run` on
  `tests/fixtures/services.yaml`: output forms, filters, inputs, errors and
  exit statuses.
