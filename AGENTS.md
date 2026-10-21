# AGENTS.md

This repository is `yq`, a recreation of the Python yq (query YAML with jq
filters, print JSON or YAML) written in the Loup programming language, part
of the loup-cmd series of example applications. It is a `host.scripted`
project: the program is the `.lpscr` script `bin/yq.lpscr`, which
`loup run` executes from source, over modules in `lib/`. Nothing is
compiled.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` before writing or changing any Loup code
in this repository. It links to detailed references under
`skills/loup-programmer/references/` for syntax, types and ownership, execution
modes and projects, errors and diagnostics, the standard library, and common
mistakes. Load those only as needed.

## Code layout

```text
.
├── package.lppkg                # manifest: name, version, toolchain, [build] entry (bin/yq.lpscr), [test] pattern
├── Makefile                     # run, check, test, e2e, ci, clean
├── bin/
│   └── yq.lpscr                 # the command: options, compile, inputs, output, exit status
├── lib/                         # modules; host.scripted unless noted
│   ├── appinfo.loup             # host.dual: APP_NAME, APP_VERSION, exit statuses
│   ├── usage.loup               # host.dual: usage(), version_line()
│   ├── args.lpscr               # class Options, parse_args()
│   ├── lexer.lpscr              # TokKind, Token, FilterSyntaxError, tokenize()
│   ├── ast.lpscr                # enum Node (recursive)
│   ├── parser.lpscr             # class Parser, compile()
│   ├── eval.lpscr               # class Env, gen func run(), index_value(), slice_value()
│   ├── builtins.lpscr           # BUILTINS, gen func call_builtin(), sorting, grouping, formats
│   ├── values.lpscr             # JqError, Failure, kind(), compare(), equal(), arithmetic
│   ├── flow.lpscr               # scalar_value(), parse_flow()
│   ├── yamlin.lpscr             # documents(), class Preparer, normalize(), read_values()
│   └── output.lpscr             # struct Style, render(), to_yaml()
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*(): void
│   ├── e2e.sh                   # end-to-end tests: runs the script with loup run
│   └── fixtures/services.yaml   # sample input: two YAML documents
├── specs/yq/                    # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
└── .github/workflows/ci.yml     # installs Loup and runs `make ci`
```

## Check, run and test

Prerequisites: Loup 1.26.0 (`loup` and `loup-bootstrap` on `PATH`), `make`
and `bash`.

Loup Lite comes from <https://github.com/code-craft-ai-company/loup-releases>;
[README.md](README.md#installing-loup-lite) has the install commands.

| Task | Command | Notes |
|------|---------|-------|
| Run from source | `make run ARGS="-c .services[0] tests/fixtures/services.yaml"` | `loup run bin/yq.lpscr -- ARGS` |
| Run directly | `./bin/yq.lpscr -r '.a' FILE` | long options only after `--` |
| Type-check | `make check` | `loup-bootstrap check FILE` for `bin/yq.lpscr` and the modules it imports |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn |
| One test file | `make test TESTS=tests/eval_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter strings"` | tests whose name contains `strings` |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: output and exit status of `loup run` |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` |
| Clean | `make clean` | removes `build/` and `.temp/` |

Run `make ci` before reporting a change as done. Unit tests run under Stage0
(`loup-bootstrap`); the script runs under the self-hosted `loup run`, which
behaves differently in places (below), so only `make e2e` shows what users get.

Toolchain facts this project depends on (Loup 1.26.0, Linux x86-64):

- Generators differ by interpreter: Stage0 runs them lazily, the
  self-hosted `loup run` runs a generator to its end before the loop over
  it starts. An exception that leaves a generator is lost under the
  self-hosted run (with every output before it) and cannot be caught under
  Stage0. So every generator here catches `JqError` itself and yields a
  `Failure`; consumers call `unwrap()`.
- A `gen func` cannot contain a bare `return`: use if/else.
- An enum payload of type `Any` does not take a string or number literal
  under Stage0 (`Node.Literal(value = 1)`); pass it through a function
  parameter of type `Any` (`lit(1)`), or `box` it. Values that went through
  `box` cannot be written by `system.json` under Stage0.
- `throw this.method()` (throwing a value a method returned) is rejected by
  Stage0: construct the exception at the `throw`.
- `global x;` must come first in a function body.
- Importing `data.yaml` makes `system.json.parse` call the YAML parser:
  this project only writes JSON (`stringify`, `stringifyIndented`).
- `from`, `where`, `takes` and `not` are reserved words.
- `loup-bootstrap test` with all files at once fails random tests with an
  empty `RuntimeError` on a busy machine; the Makefile runs one file at a
  time with `--no-parallel`.

## Making a change

1. Update the spec in `specs/yq/` (see [specs/README.md](specs/README.md)).
2. Change the code: behaviour in `lib/`, top-level flow in `bin/`.
3. Add or update unit tests in `tests/` and cases in `tests/e2e.sh`. When a
   filter's behaviour is in question, compare with `jq` on the same data as
   JSON.
4. Run `make ci`.
5. Tick the finished tasks in `specs/yq/tasks.md`.

Keep behaviour in functions and generators that return values, so unit
tests can check them; only `bin/yq.lpscr` prints, reads files and calls
`exit`.

## Conventions

- `bin/yq.lpscr` is `@mode(host.scripted)` with a `#!/usr/bin/env -S loup run`
  line and the executable bit.
- `lib/*.lpscr` are `@mode(host.scripted)`: they use `Any`, generators and
  sets, which only the interpreters run. `lib/appinfo.loup` and
  `lib/usage.loup` are `host.dual` and hold nothing a native build lacks.
- Imports are relative: `from ..lib.eval import (...)` in `bin/` and
  `tests/`, `from .values import (...)` inside `lib/`.
- A builtin is added in three places: `BUILTINS` (name/arity), its code in
  `call_builtin` or `value_of`, and the tables in README.md.
- Error messages follow jq's wording after `yq: error: `.
- Keep `APP_VERSION` in `lib/appinfo.loup` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
