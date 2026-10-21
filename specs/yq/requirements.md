# Requirements: yq

## Introduction

`yq` queries YAML files with a jq filter and prints the results as JSON,
or as YAML with `-y`, like the Python [yq](https://github.com/kislyuk/yq)
(a jq wrapper for YAML). It reads the YAML found in configuration files
(mappings, sequences, flow collections, block scalars, several documents in
one file) and evaluates a substantial subset of the jq language: paths,
iteration, pipes, construction, operators, conditionals, variables, string
interpolation and the common builtins.

It is a host-scripted project of the loup-cmd series: the program is
`bin/yq.lpscr`, run with `loup run`, over modules in `lib/`.

## Requirements

### Requirement 1: Command line

**User Story:** As a script author, I want jq's command line so that what I
know from jq works.

#### Acceptance Criteria

1. THE program SHALL accept `yq [OPTION]... FILTER [FILE]...`, reading
   standard input when no FILE is given or a FILE is `-`.
2. THE program SHALL accept `-y`/`--yaml-output`, `-r`/`--raw-output`,
   `-j`/`--join-output`, `-c`/`--compact-output`, `-S`/`--sort-keys`,
   `-s`/`--slurp`, `-n`/`--null-input`, `-e`/`--exit-status`,
   `--indent N` (0 to 7), `--arg NAME VALUE`, `-h`/`--help` and
   `-V`/`--version`; short options SHALL combine (`-rc`); `--` SHALL end
   the options.
3. WHEN the command line is wrong (unknown option, missing value, no
   FILTER, a bad `--indent`), THE program SHALL print `yq: MESSAGE` and
   `Try 'yq --help' for more information.` on standard error and exit with
   status 2.

### Requirement 2: YAML input

**User Story:** As an operator, I want to query the YAML files my tools
use as they are.

#### Acceptance Criteria

1. THE reader SHALL use `data.yaml` for block mappings and sequences,
   scalars (strings, quoted strings, integers, floats, booleans, null) and
   comments.
2. THE reader SHALL also accept sequence items that start a mapping or a
   sequence on the dash line (`- name: a`, `- - x`), flow collections
   (`[a, b]`, `{k: v}`, nested, possibly over several lines), literal and
   folded block scalars (`|`, `>`, with `-` and `+` chomping) and quoted
   keys.
3. THE reader SHALL split a file into documents at `---` lines; every
   document SHALL be one input to the filter, in order.
4. WHEN a document cannot be read, THE program SHALL print
   `yq: FILE:LINE: MESSAGE` (the line in the original file) and exit with
   status 2; WHEN a FILE cannot be opened it SHALL print
   `yq: FILE: No such file or directory` (or `Is a directory`), go on with
   the other files and exit with status 2.

### Requirement 3: Filters

**User Story:** As a script author, I want to pick, reshape and compute
values with jq filters.

#### Acceptance Criteria

1. THE filter language SHALL support `.`, `..`, `.name`, `."name"`,
   `.[EXPR]` (index or key), `.[A:B]` slices, `.[]`, the postfix `?`,
   `|`, `,`, parentheses, literals (numbers, strings with escapes and
   `\(EXPR)` interpolation, `true`, `false`, `null`), `[EXPR]`, `{...}`
   object construction (with `name`, `"name"`, `$var` and `(EXPR)` keys,
   and `{name}` shorthand), `+ - * / %`, `== != < <= > >=`, `and`, `or`,
   `//`, unary `-`, `if ... then ... elif ... else ... end`,
   `EXPR as $name | BODY`, `$name`, and `@json @text @csv @tsv @sh`
   formats.
2. THE language SHALL provide the builtins `empty`, `error`, `not`,
   `length`, `keys`, `keys_unsorted`, `values`, `has(K)`, `type`, `add`,
   `any`, `all`, `any(F)`, `all(F)`, `map(F)`, `map_values(F)`,
   `select(F)`, `recurse`, `to_entries`, `from_entries`,
   `with_entries(F)`, `sort`, `sort_by(F)`, `group_by(F)`, `unique`,
   `unique_by(F)`, `min`, `max`, `min_by(F)`, `max_by(F)`, `reverse`,
   `flatten`, `flatten(N)`, `range(N)`, `range(A; B)`, `range(A; B; S)`,
   `first`, `last`, `first(F)`, `limit(N; F)`, `tostring`, `tonumber`,
   `tojson`, `ascii_downcase`, `ascii_upcase`, `ltrimstr(S)`, `rtrimstr(S)`,
   `startswith(S)`, `endswith(S)`, `split(S)`, `join(S)`, `contains(X)`,
   `input_filename`.
3. Values SHALL compare and sort in jq's order (null, false, true, numbers,
   strings, arrays, objects), `keys` and `sort` SHALL sort, and `==` SHALL
   compare deeply.
4. WHEN the filter does not parse, THE program SHALL print
   `yq: error: MESSAGE` and exit with status 3 before reading input.
5. WHEN evaluation fails (indexing a number, adding a string to a number,
   `error(...)`), THE program SHALL print `yq: error: MESSAGE`, go on with
   the next input, and exit with status 5.

### Requirement 4: Output

**User Story:** As a script author, I want results I can read or feed to
other tools.

#### Acceptance Criteria

1. THE program SHALL print each result as JSON indented by 2 spaces (or
   `--indent N`; 0 means compact), one line per result with `-c`, using
   `system.json`.
2. WITH `-r`, a string result SHALL be printed without quotes; WITH `-j`,
   also without a newline after it.
3. WITH `-y`, results SHALL be printed as YAML (block mappings and
   sequences, scalars quoted only when needed), separated by `---` lines.
4. WITH `-S`, object keys SHALL be sorted at every level.
5. WITH `-e`, the exit status SHALL be 1 when the last result is `false`
   or `null` and 4 when there was no result.

### Requirement 5: Inputs

**User Story:** As a script author, I want to combine documents or run a
filter without input.

#### Acceptance Criteria

1. WITH `-s`, all documents of all inputs SHALL form one array, the only
   input.
2. WITH `-n`, the filter SHALL run once on `null` and no input SHALL be
   read.
3. `--arg NAME VALUE` SHALL bind `$NAME` to the string VALUE.
