#!/usr/bin/env -S v run

// vsh_basics.vsh — demonstrates the vsh module for shell-like command execution.
//
// Run with: v run examples/vsh_basics.vsh
import vsh

fn main() {
	// --- sh() — full control over stdout, stderr, and exit code ---

	// Run a simple command and inspect the result
	res := vsh.sh('echo', 'hello vsh')
	println('1. sh() result:')
	println('   stdout  : ${res.output}')
	println('   exit_code: ${res.exit_code}')
	println('   success : ${res.success}')
	println('')

	// Run a command that produces stderr
	res2 := vsh.sh('sh', '-c', 'echo error-msg >&2; exit 1')
	println('2. Failing command:')
	println('   success : ${res2.success}')
	println('   exit_code: ${res2.exit_code}')
	println('   stderr  : ${res2.stderr}')
	println('')

	// Check if a command exists
	if vsh.sh('which', 'echo').success {
		println('3. echo is available on this system')
	}
	println('')

	// --- must() — quick "output or crash" ---

	files := vsh.must('ls -la')
	println('4. must("ls -la") output:')
	print(files)

	// must() panics on failure — uncomment to see:
	// vsh.must('nonexistent-command')
}
