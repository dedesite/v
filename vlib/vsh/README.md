## Description

`vsh` provides shell-like command execution for V scripts (`.vsh` files).

It uses `os.Process` directly with separate stdout/stderr pipes,
requires no system shell, and is cross-platform (Linux, macOS, Windows).

## Basic usage

Import the module and use `must()` for quick "output or crash" scripts,
`sh()` when you need the exit code and stderr, or `cmd().pipe().run()`
for multi-stage pipelines:

```v
import vsh

// must() — run and get stdout, panic on failure
files := vsh.must('ls -la')
println(files)

// sh() — full control over stdout, stderr, and exit code
res := vsh.sh('echo', 'hello vsh')
println('stdout: ${res.output}')
if !res.success {
	eprintln('exit code: ${res.exit_code}')
	eprintln('stderr: ${res.stderr}')
}

// cmd().pipe().run() — multi-stage pipeline (OS-level pipes)
piped := vsh.cmd('echo', 'hello world').pipe('grep', 'hello').run()
println(piped.output)

// Check if a command exists
if vsh.sh('which', 'docker').success {
	println('docker is available')
}
```

## API

### `vsh.sh(args ...string) ShOutput`

Runs a command with the given arguments. The first argument is the
executable; the rest are passed as arguments. Returns an `ShOutput`
with separate stdout, stderr, and exit code.

### `vsh.must(cmd string) string`

Splits `cmd` by whitespace and runs it. Returns stdout on success.
Panics with stderr on failure.

### `vsh.cmd(args ...string) Cmd`

Creates a `Cmd` builder with the given command as the first stage.
The first argument is the executable; the rest are arguments. Chain
`.pipe()` and finish with `.run()`.

### `vsh.Cmd`

A builder for running commands, optionally chained via pipes. Create
with `cmd()`, chain `.pipe()` calls, and finish with `.run()`.

When the pipeline has N stages (N > 1), stages run in parallel with
OS-level pipes connecting stdout of stage i to stdin of stage i+1.
Only the last stage's stdout and stderr are captured. The exit code
is from the last stage.

### `(c Cmd).pipe(args ...string) Cmd`

Appends a new pipeline stage and returns the `Cmd` for chaining.
Has the same signature as `cmd()`.

### `(c Cmd).run() ShOutput`

Executes the command pipeline and returns an `ShOutput`.

- **0 stages**: returns `exit_code: -1` with an error message
- **1 stage**: identical to `sh()`
- **N stages**: OS-level parallel pipes between stages

### `vsh.ShOutput`

| Field      | Type     | Description                          |
|------------|----------|--------------------------------------|
| `output`   | `string` | Process standard output (stdout)     |
| `stderr`   | `string` | Process standard error (stderr)      |
| `exit_code`| `int`    | Exit code (0 on success, -1 on spawn failure) |
| `success`  | `bool`   | `true` when exit_code == 0           |

## Semantics

| Condition           | `sh()` / `cmd().run()` (1 stage)     | `cmd().pipe().run()` (N stages) |
|---------------------|--------------------------------------|----------------------------------|
| Command OK (exit 0) | `ShOutput{success: true, ...}`       | `ShOutput{success: true, ...}`   |
| Command fails       | `ShOutput{success: false, ...}`      | `ShOutput{success: false, ...}`  |
| Spawn fails         | `ShOutput{exit_code: -1}`            | `ShOutput{exit_code: -1}`        |
| Stderr              | Captured from the command            | Captured from last stage only    |
| Exit code           | From the command                     | From the last stage              |
| Execution           | Sequential (single process)          | Parallel (OS-level pipes)        |