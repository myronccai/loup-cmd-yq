# AGENTS.md

This repository is `yq`, a recreation of the Python yq (query YAML with jq
filters, print JSON or YAML) and its siblings `xq` (XML) and `tomlq` (TOML),
written in the Loup programming language, part of the loup-cmd series of
example applications. It is a `host.scripted` project: the programs are
the `.lpscr` scripts `bin/yq.lpscr`, `bin/xq.lpscr` and `bin/tomlq.lpscr`,
which `loup run` executes from source, over modules in `lib/`. Nothing is
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
│   ├── yq.lpscr                 # yq: main(InputFormat.Yaml, args(), read_yaml)
│   ├── xq.lpscr                 # xq: XML input
│   └── tomlq.lpscr              # tomlq: TOML input
├── lib/                         # modules; host.scripted unless noted
│   ├── command.lpscr            # main(): options, compile, inputs, output, exit status
│   ├── appinfo.loup             # host.dual: APP_NAME, APP_VERSION, InputFormat, exit statuses
│   ├── usage.loup               # host.dual: usage(format), version_line(format)
│   ├── args.lpscr               # class Options, parse_args(argv, format)
│   ├── lexer.lpscr              # TokKind, Token, FilterSyntaxError, tokenize()
│   ├── ast.lpscr                # enum Node (recursive)
│   ├── parser.lpscr             # class Parser, compile()
│   ├── eval.lpscr               # class Env, gen func run(), index_value(), slice_value()
│   ├── builtins.lpscr           # BUILTINS, gen func call_builtin(), sorting, grouping, formats
│   ├── values.lpscr             # JqError, Failure, InputError, kind(), json_text(), compare(), arithmetic
│   ├── flow.lpscr               # scalar_value(), parse_flow()
│   ├── yamlin.lpscr             # documents(), class Preparer, normalize(), read_yaml()
│   ├── xmlin.lpscr              # class XmlPreparer, element_value(), read_xml()
│   ├── tomlin.lpscr             # read_toml()
│   └── output.lpscr             # struct Style, render(), to_yaml()
├── tests/
│   ├── *_test.lpscr             # unit tests: func test_*(): void
│   ├── e2e.sh                   # end-to-end tests: runs the script with loup run
│   └── fixtures/                # services.yaml (two documents), pom.xml, pyproject.toml
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
| Run xq or tomlq | `make run APP=xq ARGS=".project.version tests/fixtures/pom.xml"` | `APP=tomlq` likewise |
| Run directly | `./bin/yq.lpscr -r '.a' FILE` | long options only after `--` |
| Type-check | `make check` | `loup-bootstrap check FILE` for each script in `bin/` and the modules it imports |
| Unit tests | `make test` | each `tests/*_test.lpscr` in turn |
| One test file | `make test TESTS=tests/eval_test.lpscr` | |
| Matching tests | `make test TEST_ARGS="--filter strings"` | tests whose name contains `strings` |
| End-to-end tests | `make e2e` | `tests/e2e.sh`: output and exit status of `loup run` |
| Everything CI runs | `make ci` | check, test, e2e, then `--version` of each script |
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
  this project only writes JSON.
- A program can load only one of `data.yaml`, `data.xml` and `data.toml`
  (each has a private `_Cursor` class: E0001), hence three programs. Keep
  each one's import in its reader module, and import a reader only from
  its script and its tests.
- With `data.xml` loaded (xq), every call to `system.json`'s `stringify`,
  aliased or qualified, runs data.xml's `stringify(Element)`. Write compact
  JSON with `json_text()` from `lib/values.lpscr`, never `stringify`.
- A module-level `var` or `let` of an imported module that is initialized
  from an imported constant reads as empty inside the module's functions
  (`var status = EXIT_OK;`): `lib/command.lpscr` sets its state in
  `main()`.
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
tests can check them; only `lib/command.lpscr` prints and reads files, and
only the scripts in `bin/` call `exit`.

## Conventions

- The scripts in `bin/` are `@mode(host.scripted)` with a
  `#!/usr/bin/env -S loup run` line and the executable bit; each is one
  call to `main()` in `lib/command.lpscr`.
- `lib/*.lpscr` are `@mode(host.scripted)`: they use `Any`, generators and
  sets, which only the interpreters run. `lib/appinfo.loup` and
  `lib/usage.loup` are `host.dual` and hold nothing a native build lacks.
- Imports are relative: `from ..lib.eval import (...)` in `bin/` and
  `tests/`, `from .values import (...)` inside `lib/`.
- A builtin is added in three places: `BUILTINS` (name/arity), its code in
  `call_builtin` or `value_of`, and the tables in README.md.
- Error messages follow jq's wording after `yq: error: ` (`xq: error: `,
  `tomlq: error: `).
- An input format's reader has the type `fn(string, string, Options):
  list[Any]`: the file's text and shown name in, its values (or an
  `InputError` value) out.
- Keep `APP_VERSION` in `lib/appinfo.loup` equal to `version` in
  `package.lppkg`.
- The skill documents toolchain 1.25.1; this project targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
