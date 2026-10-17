# Hardware entry is launched by check_cu8_board.py after package validation.
set ::e_j1_library_only 1
source [file join [file dirname [info script]] deploy.tcl]
unset ::e_j1_library_only

proc cu8_word {address} {
	return [expr {[lindex [mrd -value $address 1] 0] & 0xFFFFFFFF}]
}

proc cu8_wait {base mode timeout_ms} {
	set deadline [expr {[clock milliseconds] + $timeout_ms}]
	while {1} {
		set status [cu8_word [expr {$base + 4}]]
		require {($status & 0x24) == 0} [format "CNN error: STATUS=0x%08X ERROR_CODE=0x%08X" $status [cu8_word [expr {$base + 0x18}]]]
		if {$mode eq "ready" && ($status & 0x77) == 0x40} {return $status}
		if {$mode eq "done" && ($status & 0x77) == 2} {return $status}
		require {[clock milliseconds] < $deadline} "Timeout waiting for $mode; STATUS=$status"
		after 10
	}
}

proc cu8_load {input address output} {
	set bytes [file size $input]
	# Only the three fixed D5 payloads may be written by this entry.
	require {[list $address $bytes] in {{0x04000000 320} {0x12000000 296512} {0x05000000 288}}} "Invalid micro-network DDR transfer"
	dow -data $input $address
	mrd -bin -file $output $address [expr {$bytes / 4}]
	require {[read_binary $output] eq [read_binary $input]} "DDR payload readback mismatch: $input"
}

proc cu8_run {bundle run_dir runs} {
	require {[string is integer -strict $runs] && $runs >= 1 && $runs <= 100} "Invalid run count"
	require {[file isdirectory $run_dir] && ![file exists [file join $run_dir result.txt]]} "Run must be freshly prepared by Python"
	verify_artifacts $bundle {e_j2.xsa e_j2_system_wrapper.bit ps7_init.tcl address_map.tcl init_checks.tcl implementation_summary.json simulation_summary.json}
	source [file join $bundle address_map.tcl]
	require {$csr_base == 0x43C00000 && $expected_build_id == 0x20261015} "Unexpected CU8 hardware map"
	set ::cu8_run_dir $run_dir
	save_text [file join $run_dir result.txt] RUNNING
	save_text [file join $run_dir execution_kind.txt] HARDWARE
	save_text [file join $run_dir tool_version.txt] [version]
	lassign [initialize_e_j0 $bundle e_j2_system_wrapper.bit e_j2.xsa] cpu0 cpu1
	save_text [file join $run_dir targets.txt] [targets -target-properties]
	save_text [file join $run_dir cache_state.txt] [check_cache_state $cpu0 $cpu1]
	set cables [jtag targets -target-properties -filter {level == 0}]
	require {[llength $cables] == 1} "Missing or ambiguous JTAG cable"
	jtag targets [dict get [lindex $cables 0] node_id]
	save_text [file join $run_dir jtag.txt] "[jtag targets -target-properties]\nfrequency_hz=[jtag frequency]"
	targets $cpu0
	check_word [expr {$csr_base + 0x1C}] 0xFFFFFFFF $expected_build_id BUILD_ID
	cu8_wait $csr_base ready 5000
	set payload [file join $run_dir payload]
	foreach {name address} {micro_cmd.bin 0x04000000 micro_weights.bin 0x12000000} {
		cu8_load [file join $payload $name] $address [file join $run_dir $name.readback]
	}
	set expected [read_binary [file join $payload expected.bin]]
	require {[string length $expected] == 16} "Expected logits must contain eight INT16 lanes"
	set records [open [file join $run_dir runs.tsv] w]
	puts $records "run\tstatus\terror\tlayer\tcycles"
	try {
		for {set number 1} {$number <= $runs} {incr number} {
			cu8_wait $csr_base ready 5000
			# Layer 1 overwrites feature A; reload the original input for every run.
			cu8_load [file join $payload micro_input.bin] 0x05000000 [file join $run_dir r${number}_input.bin]
			mwr 0x04200000 0xA5A5A5A5 4
			mwr 0x041FFFC0 0xA5A5A5A5 4
			mwr [expr {$csr_base + 8}] 0x04000000
			mwr [expr {$csr_base + 0x20}] 320
			check_word [expr {$csr_base + 8}] 0xFFFFFFFF 0x04000000 MODEL_BASE
			check_word [expr {$csr_base + 0x20}] 0xFFFFFFFF 320 MODEL_BYTES
			mwr $csr_base 1
			set status [cu8_wait $csr_base done 60000]
			set error_code [cu8_word [expr {$csr_base + 0x18}]]
			set layer [cu8_word [expr {$csr_base + 0x14}]]
			set low [cu8_word [expr {$csr_base + 0x0C}]]
			set high [cu8_word [expr {$csr_base + 0x10}]]
			set cycles [expr {($high << 32) | $low}]
			puts $records [join [list $number [format 0x%08X $status] [format 0x%08X $error_code] $layer $cycles] \t]
			flush $records
			require {$error_code == 0 && $layer == 3 && $cycles > 0} "Invalid completion diagnostics"
			set output [file join $run_dir r${number}_output.bin]
			set runtime [file join $run_dir r${number}_runtime.bin]
			mrd -bin -file $output 0x04200000 4
			mrd -bin -file $runtime 0x041FFFC0 4
			require {[read_binary $output] eq $expected} "Final logits/padded lane differ from D5 golden"
			binary scan [read_binary $runtime] iu* words
			require {[llength $words] == 4 && [lindex $words 0] == $low && [lindex $words 1] == $high && [lindex $words 2] == 3 && [lindex $words 3] == 1} "GP runtime record differs from CSR"
			mwr $csr_base 8
			cu8_wait $csr_base ready 5000
			# shortcut: this is an idle reset; in-flight DMA cancellation needs a dedicated board test.
			mwr $csr_base 2
			cu8_wait $csr_base ready 5000
			puts "PASS CU8 run=$number cycles=$cycles compute_ms=[expr {$cycles / 100000.0}]"
		}
	} finally {close $records}
	check_word [expr {$csr_base + 0x1C}] 0xFFFFFFFF $expected_build_id BUILD_ID
	save_text [file join $run_dir final_status.txt] [format 0x%08X [cu8_wait $csr_base ready 5000]]
	check_cache_state $cpu0 $cpu1
	save_text [file join $run_dir result.txt] "PASS CU8 micro network"
	disconnect
}

if {![info exists ::cu8_library_only]} {
	if {[llength $argv] != 3} {
		puts stderr "Use: python scripts/jtag/check_cu8_board.py <new run directory>"
		exit 2
	}
	if {[catch {cu8_run [file normalize [lindex $argv 0]] [file normalize [lindex $argv 1]] [lindex $argv 2]} message options]} {
		puts stderr "FAIL CU8: $message\n[dict get $options -errorinfo]"
		if {[info exists ::cu8_run_dir]} {
			catch {save_text [file join $::cu8_run_dir failure_csr.txt] [mrd -value 0x43C00000 9]}
			catch {mrd -bin -file [file join $::cu8_run_dir failure_runtime.bin] 0x041FFFC0 4}
			save_text [file join $::cu8_run_dir result.txt] "FAIL CU8: $message"
		}
		catch {disconnect}
		exit 1
	}
}
