## Description

`vsh` provides shell-like command execution for V scripts (`.vsh` files).

It uses `os.Process` directly with separate stdout/stderr pipes,
requires no system shell, and is cross-platform (Linux, macOS, Windows).

## Basic usage

Import the module and use `must()` for quick "output or crash" scripts,
or `sh()` when you need the exit code and stderr:

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

### `vsh.ShOutput`

| Field      | Type     | Description                          |
|------------|----------|--------------------------------------|
| `output`   | `string` | Process standard output (stdout)     |
| `stderr`   | `string` | Process standard error (stderr)      |
| `exit_code`| `int`    | Exit code (0 on success, -1 on spawn failure) |
| `success`  | `bool`   | `true` when exit_code == 0           |

## Semantics

| Condition           | `sh()`                          | `must()`               |
|---------------------|---------------------------------|------------------------|
| Command OK (exit 0) | `ShOutput{success: true, ...}`  | Returns `output`       |
| Command fails       | `ShOutput{success: false, ...}` | `panic(stderr)`        |
| Spawn fails         | `ShOutput{exit_code: -1}`       | `panic(stderr)`        |