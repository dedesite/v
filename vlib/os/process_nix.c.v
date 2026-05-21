module os

fn C.setpgid(pid i32, pgid i32) i32

fn env_value_from_entries(env []string, name string) ?string {
	prefix := '${name}='
	for entry in env {
		if entry.starts_with(prefix) {
			return entry[prefix.len..]
		}
	}
	return none
}

fn (p &Process) unix_resolve_filename() !string {
	if is_abs_path(p.filename) {
		return p.filename
	}
	if p.filename.contains(path_separator) {
		if p.work_folder != '' {
			return abs_path(p.filename)
		}
		return p.filename
	}
	path := env_value_from_entries(p.env, 'PATH') or { return error_failed_to_find_executable() }
	return find_abs_path_of_executable_in_path_env(p.filename, path)
}

fn (mut p Process) unix_spawn_process() int {
	mut pipeset := [-1, -1, -1, -1, -1, -1]!
	if p.use_stdio_ctl {
		// stdin pipe: only create if no custom fd
		if p.stdin_custom_fd == -1 {
			if C.pipe(&pipeset[0]) == -1 { // pipe read end 0 <- 1 pipe write end
				p.err = posix_get_error_msg(C.errno)
				return -1
			}
		}
		// stdout pipe: only create if no custom fd
		if p.stdout_custom_fd == -1 {
			if C.pipe(&pipeset[2]) == -1 { // pipe read end 2 <- 3 pipe write end
				p.err = posix_get_error_msg(C.errno)
				return -1
			}
		}
		// stderr pipe: only create if no custom fd
		if p.stderr_custom_fd == -1 {
			if C.pipe(&pipeset[4]) == -1 { // pipe read end 4 <- 5 pipe write end
				p.err = posix_get_error_msg(C.errno)
				return -1
			}
		}
	}
	pid := fork()
	if pid != 0 {
		// This is the parent process after the fork.
		// Note: pid contains the process ID of the child process
		if p.use_stdio_ctl {
			// Stdin: if no custom fd, use pipe write end; otherwise -1 (caller manages)
			if p.stdin_custom_fd != -1 {
				p.stdio_fd[0] = -1
			} else {
				p.stdio_fd[0] = pipeset[1] // store the write end of child's in
				fd_close(pipeset[0]) // close the read end (parent doesn't read stdin)
			}
			// Stdout: if no custom fd, use pipe read end; otherwise -1 (caller manages)
			if p.stdout_custom_fd != -1 {
				p.stdio_fd[1] = -1
			} else {
				p.stdio_fd[1] = pipeset[2] // store the read end of child's out
				fd_close(pipeset[3]) // close the write end (parent doesn't write stdout)
			}
			// Stderr: if no custom fd, use pipe read end; otherwise -1 (caller manages)
			if p.stderr_custom_fd != -1 {
				p.stdio_fd[2] = -1
			} else {
				p.stdio_fd[2] = pipeset[4] // store the read end of child's err
				fd_close(pipeset[5]) // close the write end (parent doesn't write stderr)
			}
		}
		return pid
	}
	//
	// Here, we are in the child process.
	// It still shares file descriptors with the parent process,
	// but it is otherwise independent and can do stuff *without*
	// affecting the parent process.
	//
	if p.use_pgroup {
		C.setpgid(0, 0)
	}
	if p.use_stdio_ctl {
		// Stdin: use custom fd or pipe
		if p.stdin_custom_fd != -1 {
			C.dup2(p.stdin_custom_fd, 0)
			fd_close(p.stdin_custom_fd)
		} else {
			fd_close(pipeset[1]) // close write end, child doesn't write to stdin
			C.dup2(pipeset[0], 0)
			fd_close(pipeset[0])
		}
		// Stdout: use custom fd or pipe
		if p.stdout_custom_fd != -1 {
			C.dup2(p.stdout_custom_fd, 1)
			fd_close(p.stdout_custom_fd)
		} else {
			fd_close(pipeset[2]) // close read end, child doesn't read stdout
			C.dup2(pipeset[3], 1)
			fd_close(pipeset[3])
		}
		// Stderr: use custom fd or pipe
		if p.stderr_custom_fd != -1 {
			C.dup2(p.stderr_custom_fd, 2)
			fd_close(p.stderr_custom_fd)
		} else {
			fd_close(pipeset[4]) // close read end, child doesn't read stderr
			C.dup2(pipeset[5], 2)
			fd_close(pipeset[5])
		}
	}
	p.filename = p.unix_resolve_filename() or {
		eprintln(err)
		exit(1)
	}
	if p.work_folder != '' {
		chdir(p.work_folder) or {}
	}
	execve(p.filename, p.args, p.env) or {
		eprintln(err)
		exit(1)
	}
	return 0
}

fn (mut p Process) unix_stop_process() {
	C.kill(p.pid, C.SIGSTOP)
}

fn (mut p Process) unix_resume_process() {
	C.kill(p.pid, C.SIGCONT)
}

fn (mut p Process) unix_term_process() {
	C.kill(p.pid, C.SIGTERM)
}

fn (mut p Process) unix_kill_process() {
	C.kill(p.pid, C.SIGKILL)
}

fn (mut p Process) unix_kill_pgroup() {
	C.kill(-p.pid, C.SIGKILL)
}

fn (mut p Process) unix_wait() {
	p.impl_check_pid_status(false, 0)
}

fn (mut p Process) unix_is_alive() bool {
	return p.impl_check_pid_status(true, C.WNOHANG)
}

fn (mut p Process) impl_check_pid_status(exit_early_on_ret0 bool, waitpid_options int) bool {
	mut cstatus := 0
	mut ret := -1
	$if !emscripten ? {
		ret = C.waitpid(p.pid, &cstatus, waitpid_options)
	}
	p.code = ret
	if ret == -1 {
		p.err = posix_get_error_msg(C.errno)
		return false
	}
	if exit_early_on_ret0 && ret == 0 {
		return true
	}
	mut pret, is_signaled := posix_wait4_to_exit_status(cstatus)
	if is_signaled {
		p.status = .aborted
		p.err = 'Terminated by signal ${pret:2d} (${sigint_to_signal_name(pret)})'
		pret += 128
	} else {
		p.status = .exited
	}
	p.code = pret
	return false
}

// these are here to make v_win.c/v.c generation work in all cases:
fn (mut p Process) win_spawn_process() int {
	return 0
}

fn (mut p Process) win_stop_process() {
}

fn (mut p Process) win_resume_process() {
}

fn (mut p Process) win_term_process() {
}

fn (mut p Process) win_kill_process() {
}

fn (mut p Process) win_kill_pgroup() {
}

fn (mut p Process) win_wait() {
}

fn (mut p Process) win_is_alive() bool {
	return false
}

fn (mut p Process) win_write_string(_idx int, _s string) {
}

fn (mut p Process) win_read_string(_idx int, _maxbytes int) (string, int) {
	return '', 0
}

fn (mut p Process) win_is_pending(_idx int) bool {
	return false
}

fn (mut p Process) win_slurp(_idx int) string {
	return ''
}
