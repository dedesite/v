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
// // Builder pattern with pipes
// res := vsh.cmd('echo', 'hello').pipe('grep', 'h').run()
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

// A single stage in a Cmd pipeline.
struct CmdStage {
	filename string
	args     []string
}

// Cmd is a builder for running commands, optionally chained via pipes.
//
// Use cmd() to create a Cmd, then chain .pipe() calls, and finally
// .run() to execute. OS-level pipes (parallel execution) are used
// for multi-stage pipelines.
//
// Example:
//
// ```v
// res := vsh.cmd('echo', 'hello').pipe('grep', 'h').run()
// println(res.output)
// ```
pub struct Cmd {
mut:
	stages []CmdStage
}

// cmd creates a Cmd with the given command as the first stage.
//
// The first argument is the executable; the rest are arguments.
//
// Example:
//
// ```v
// res := vsh.cmd('echo', 'hello').run()
// ```
pub fn cmd(args ...string) Cmd {
	if args.len == 0 {
		return Cmd{}
	}
	return Cmd{
		stages: [
			CmdStage{
				filename: args[0]
				args:     if args.len > 1 { args[1..] } else { []string{} }
			},
		]
	}
}

// pipe appends a new pipeline stage and returns the Cmd for chaining.
// It has the same signature as cmd().
//
// Example:
//
// ```v
// res := vsh.cmd('echo', 'hello').pipe('grep', 'h').run()
// ```
pub fn (c Cmd) pipe(args ...string) Cmd {
	mut result := c
	if args.len == 0 {
		return result
	}
	result.stages << CmdStage{
		filename: args[0]
		args:     if args.len > 1 { args[1..] } else { []string{} }
	}
	return result
}

// run executes the command pipeline and returns an ShOutput.
//
// - 0 stages: returns exit_code -1 with an error message
// - 1 stage: identical to sh()
// - N stages: OS-level parallel pipes between stages
//
// For multi-stage pipelines:
// - stdout of stage N is piped to stdin of stage N+1
// - Only the last stage's stderr is captured
// - The exit code is from the last stage
pub fn (c Cmd) run() ShOutput {
	if c.stages.len == 0 {
		return ShOutput{
			exit_code: -1
			output:    'vsh.cmd: no stages'
		}
	}
	if c.stages.len == 1 {
		mut single_args := [c.stages[0].filename]
		single_args << c.stages[0].args
		return run_internal(...single_args)
	}
	// Multi-stage: OS-level parallel pipes
	return run_pipe(c.stages)
}

// run_internal runs a single command and returns ShOutput.
// Shared by sh() and Cmd.run() for single-stage execution.
fn run_internal(args ...string) ShOutput {
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

// run_pipe executes multiple stages connected via OS-level pipes.
// Stages run in parallel. Only the last stage's output is captured.
//
// Key design: after spawning each stage, we immediately close any
// pipe fds that the NEXT stage should NOT inherit. This prevents
// the common deadlock where the pipe reader inherits the write end
// from the parent, keeping the pipe open after the writer exits.
fn run_pipe(stages []CmdStage) ShOutput {
	n := stages.len

	// Create N-1 OS pipes for N stages
	mut pipes := []os.Pipe{}
	for _ in 0 .. n - 1 {
		mut pipe := os.pipe() or {
			return ShOutput{
				exit_code: -1
				output:    'vsh.cmd: pipe creation failed: ${err}'
			}
		}
		pipes << pipe
	}

	// Spawn all stages, closing each pipe fd in the parent
	// immediately after the stage that needs it has forked
	mut processes := []&os.Process{}
	for i, stage in stages {
		mut p := os.new_process(stage.filename)
		p.set_args(stage.args)

		if i > 0 {
			// stdin comes from the previous pipe's read end
			p.set_stdin_fd(pipes[i - 1].read_fd)
		}
		if i < n - 1 {
			// stdout goes to the current pipe's write end
			p.set_stdout_fd(pipes[i].write_fd)
		} else {
			// Last stage: capture stdout
			p.set_redirect_stdio()
		}

		p.run()
		processes << p

		// After spawning stage i, close the write end of pipe[i]
		// in the parent. Subsequent children (i+1) must not inherit
		// the write end, otherwise they'd keep the pipe open and
		// prevent EOF for the reader.
		if i < n - 1 {
			os.fd_close(pipes[i].write_fd)
		}
	}

	// Close all remaining parent-side pipe read fds
	for mut pipe in pipes {
		os.fd_close(pipe.read_fd)
	}

	// Wait from last to first to avoid pipe backpressure deadlocks.
	// Slurp last stage output BEFORE close() since close() closes stdio_fds.
	for i := n - 1; i >= 0; i-- {
		mut p := processes[i]
		p.wait()
	}

	last := processes[n - 1]
	output := last.stdout_slurp()
	stderr := last.stderr_slurp()
	exit_code := last.code
	success := last.code == 0

	for mut p in processes {
		p.close()
	}

	return ShOutput{
		output:    output
		stderr:    stderr
		exit_code: exit_code
		success:   success
	}
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
	return run_internal(...args)
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
