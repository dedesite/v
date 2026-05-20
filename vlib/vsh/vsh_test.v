// Copyright (c) 2019-2025 The V Language Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license.
// License text: https://github.com/vlang/v/blob/master/LICENSE

module vsh

import os

const vexe = os.getenv('VEXE')
const vroot = os.dir(vexe)
const testdata = os.join_path(os.vtmp_dir(), 'vsh_testdata')
const echo_exe = os.join_path(testdata, 'echo_helper')
const io_exe = os.join_path(testdata, 'io_helper')

const echo_source = "
module main

import os

fn main() {
	mut start := 1
	mut newline := true
	if os.args.len > 1 && os.args[1] == '-n' {
		newline = false
		start = 2
	}
	parts := os.args[start..].clone()
	if parts.len > 0 {
		print(parts.join(' '))
	}
	if newline {
		println('')
	}
}
"

const io_source = "
module main

import os

fn main() {
	mut exit_code := 0
	mut stdout_lines := []string{}
	mut stderr_lines := []string{}

	for i := 1; i < os.args.len; i++ {
		match os.args[i] {
			'--exit' {
				if i + 1 < os.args.len {
					i++
					exit_code = os.args[i].int()
				}
			}
			'--stderr' {
				if i + 1 < os.args.len {
					i++
					stderr_lines << os.args[i]
				}
			}
			'--stdout' {
				if i + 1 < os.args.len {
					i++
					stdout_lines << os.args[i]
				}
			}
			else {}
		}
	}

	for line in stdout_lines {
		println(line)
	}
	for line in stderr_lines {
		eprintln(line)
	}
	exit(exit_code)
}
"

fn testsuite_begin() {
	os.rmdir_all(testdata) or {}
	os.mkdir_all(testdata)!

	echo_src := os.join_path(testdata, 'echo_helper.v')
	os.write_file(echo_src, echo_source)!
	assert 0 == os.system('${os.quoted_path(vexe)} -o ${os.quoted_path(echo_exe)} ${os.quoted_path(echo_src)}')
	assert os.exists(echo_exe)

	io_src := os.join_path(testdata, 'io_helper.v')
	os.write_file(io_src, io_source)!
	assert 0 == os.system('${os.quoted_path(vexe)} -o ${os.quoted_path(io_exe)} ${os.quoted_path(io_src)}')
	assert os.exists(io_exe)
}

fn testsuite_end() {
	os.rmdir_all(testdata) or {}
}

fn test_sh_simple() {
	res := sh(echo_exe, 'hello', 'world')
	assert res.success, 'expected success'
	assert res.exit_code == 0, 'expected exit_code 0, got ${res.exit_code}'
	assert res.output == 'hello world\n', 'expected "hello world\\n", got "${res.output}"'
}

fn test_sh_with_args() {
	res := sh(echo_exe, '-n', 'hello vsh')
	assert res.success
	assert res.exit_code == 0
	assert res.output == 'hello vsh', 'expected "hello vsh", got "${res.output}"'
}

fn test_sh_failure() {
	res := sh(io_exe, '--exit', '42')
	assert !res.success, 'expected failure'
	assert res.exit_code == 42, 'expected exit_code 42, got ${res.exit_code}'
}

fn test_sh_empty_args() {
	res := sh()
	assert !res.success, 'expected failure for empty args'
	assert res.exit_code == -1, 'expected exit_code -1, got ${res.exit_code}'
	assert res.output == 'vsh.sh: no command specified'
}

fn test_must_success() {
	result := must('${echo_exe} hello from must')
	assert result == 'hello from must\n', 'expected "hello from must\\n", got "${result}"'
}

fn test_must_with_args_via_fields() {
	result := must('${echo_exe} -n   hello')
	assert result == 'hello', 'expected "hello", got "${result}"'
}

fn test_sh_separate_stdouterr() {
	res := sh(io_exe, '--stdout', 'out', '--stderr', 'err')
	assert res.success
	assert res.output.contains('out'), 'stdout should contain "out"'
	assert !res.output.contains('err'), 'stdout should not contain "err"'
	assert res.stderr.contains('err'), 'stderr should contain "err"'
}

fn test_sh_stderr_on_failure() {
	res := sh(io_exe, '--stderr', 'fail', '--exit', '1')
	assert !res.success
	assert res.exit_code == 1
	assert res.stderr.contains('fail'), 'stderr should contain "fail", got "${res.stderr}"'
}

fn test_must_panics_on_failure_via_sh() {
	res := sh(io_exe, '--exit', '2')
	assert !res.success
	assert res.exit_code != 0
}

fn test_sh_command_not_found() {
	res := sh('nonexistent_command_xyz123')
	assert !res.success
	assert res.stderr.len > 0, 'expected error in stderr, got empty'
}
