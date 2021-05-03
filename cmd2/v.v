module main

import os
import cli { Command, Flag }
import v.util

fn main() {
	mut v_cmd := &Command{
		name: 'v',
		description: 'v is a tool for managing v source code.'
		version: util.full_v_version(true)
		// sort_commands: false
		execute: main_fn
	}

	v_cmd.add_flag(Flag {
		flag: .bool
		name: 'verbose'
		description: 'Set the verbosity of the output.'
		abbrev: 'v'
		global: true
	})

	v_cmd.add_command(init_cmd())
	v_cmd.add_command(exec_cmd())
	v_cmd.add_command(build_cmd())
	v_cmd.add_command(fmt_cmd())
	v_cmd.add_command(run_cmd())
	/*
	v_cmd.add_commands([
		tool_cmd('fmt', 'Format the V code provided.')
		tool_cmd('vet' , 'Reports suspicious code constructs in code provided.')
		tool_cmd('up', 'Format the V code provided.')
		tool_cmd('self', 'Run the V-self-compiler, use -prod to optimize compilation.')
		tool_cmd('tracev', 'Run the V-self-compiler, use -prod to optimize compilation.') // TODO: just trace?
	])
	*/

	// comment
	v_cmd.parse(os.args)
}

/*
fn tool_cmd(name string, description string) Command {
	return Command {
		name: name, 
		description: description,
		execute: fn(cmd Command) {
			is_verbose := cmd.flags.get_bool('verbose') or { false }
			util.launch_tool(is_verbose, 'v' + cmd.name, cmd.args)
		}
	}
}
*/

fn main_fn(cmd Command)? {
	if cmd.args.len < 1 {
		println('error: no tool or path provided.')
		return
	}

	// try finding a tool that matches first argument
	if tool_exists(cmd.args[0]) {
		mut args := ['exec']
		args << cmd.args

		mut exec_cmd := cmd.get_command('exec') or { panic('failed to get \'exec\' subcommand') }
		exec_cmd.parse(args)
		return
	}

	if os.exists(cmd.args[0]) || os.exists(cmd.args.last()) {
		mut args := ['build']
		args << cmd.args

		mut build_cmd := cmd.get_command('build') or { panic('failed to get \'build\' subcommand') }
		build_cmd.parse(args)
		return
	}

	println('error: no tool or path found.')
}
