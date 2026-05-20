// Copyright (c) 2019-2025 The V Language Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.
// License text: https://github.com/vlang/v/blob/master/LICENSE
//
// vsh provides shell-like command execution for .vsh scripts.
//
// It uses os.Process with separate stdout/stderr pipes,
// requires no system shell, and is cross-platform (Linux, macOS, Windows).
//
// # Quick start
//
// ```v
// import vsh
//
// // Simple: run and get stdout, panic on failure
// files := vsh.must('ls -la')
//
// // Full control: inspect stderr and exit code
// res := vsh.sh('echo', 'hello vsh')
// println(res.output)
//
// // Check success without panicking
// if vsh.sh('which', 'docker').success {
//     println('docker is available')
// }
// ```
module vsh

import os

// ShOutput represents the result of executing a command.
//
// Fields:
// - output — the process's standard output (stdout)
// - stderr — the process's standard error (stderr)
// - exit_code — the process exit code (0 on success, -1 on system error)
// - success — true when exit_code == 0
//
// Note: when the process could not be spawned (command not found,
// permission denied), exit_code is -1 and .output or .stderr
// contains a system-level error message.
pub struct ShOutput {
pub:
	output    string
	stderr    string
	exit_code int
	success   bool
}

// sh runs a command with the given arguments and returns an ShOutput.
//
// The first argument is the executable path; the rest are passed
// as arguments. The command is executed via os.Process directly
// (no system shell), with separate stdout and stderr pipes.
//
// Returns a plain ShOutput struct (not an option/result). When the
// process could not be spawned (e.g. command not found), exit_code
// is set to -1 and the error message is placed in .output.
//
// Example:
//
// ```v
// res := vsh.sh('echo', 'hello')
// if !res.success {
//     eprintln('failed: ${res.stderr}')
// }
// ```
pub fn sh(args ...string) ShOutput {
	if args.len == 0 {
		return ShOutput{
			exit_code: -1
			output:    'vsh.sh: no command specified'
		}
	}

	filename := args[0]
	cmd_args := if args.len > 1 { args[1..] } else { []string{} }

	mut p := os.new_process(filename)
	p.set_args(cmd_args)
	p.set_redirect_stdio()
	p.wait()

	stdout := p.stdout_slurp()
	stderr := p.stderr_slurp()
	p.close()

	return ShOutput{
		output:    stdout
		stderr:    stderr
		exit_code: p.code
		success:   p.code == 0
	}
}

// must splits cmd by whitespace (via fields()), executes it with sh(),
// and returns stdout as a string.
//
// If the command fails (non-zero exit code), must() panics with the
// stderr output. This is useful in quick scripts where you want to
// stop on failure.
//
// Example:
//
// ```v
// files := vsh.must('ls -la /home')
// ```
pub fn must(cmd string) string {
	parts := cmd.fields()
	if parts.len == 0 {
		panic('vsh.must: empty command')
	}
	result := sh(...parts)
	if !result.success {
		panic(result.stderr)
	}
	return result.output
}
