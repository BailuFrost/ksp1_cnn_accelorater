# Single inference only; source existing helpers without running their test entry.
set ::cu8_library_only 1
source [file join [file dirname [info script]] test_cu8_board.tcl]
unset ::cu8_library_only

proc infer_load {payload name address bytes run_dir} {
	set path [file join $payload $name]
	require {[file size $path] == $bytes && [list $name $address $bytes] in {
		{tiny_cmd.bin 0x04000000 448} {tiny_weights.bin 0x12000000 1993472} {input.bin 0x05000000 6272}
	}} "Invalid TinyCNN transfer"
	dow -data $path $address
	set readback [file join $run_dir $name.readback]
	mrd -bin -file $readback $address [expr {$bytes / 4}]
	require {[read_binary $path] eq [read_binary $readback]} "DDR readback mismatch: $name"
}

proc infer_run {bundle run_dir} {
	require {[file isdirectory $run_dir] && ![file exists [file join $run_dir result.txt]]} "Use a new Python-prepared directory"
	set payload [file join $run_dir payload]
	verify_artifacts $payload {tiny_cmd.bin tiny_weights.bin input.bin expected.bin}
	verify_artifacts $bundle {e_j2.xsa e_j2_system_wrapper.bit ps7_init.tcl address_map.tcl init_checks.tcl}
	source [file join $bundle address_map.tcl]
	require {$csr_base == 0x43C00000 && $expected_build_id == 0x20261015} "Wrong hardware map"
	set ::infer_run_dir $run_dir
	save_text [file join $run_dir result.txt] RUNNING
	save_text [file join $run_dir execution_kind.txt] HARDWARE
	save_text [file join $run_dir tool_version.txt] [version]
	lassign [initialize_e_j0 $bundle e_j2_system_wrapper.bit e_j2.xsa] cpu0 cpu1
	save_text [file join $run_dir targets.txt] [targets -target-properties]
	save_text [file join $run_dir cache_state.txt] [check_cache_state $cpu0 $cpu1]
	check_word [expr {$csr_base + 0x1C}] 0xFFFFFFFF $expected_build_id BUILD_ID
	cu8_wait $csr_base ready 5000
	foreach {name address bytes} {tiny_cmd.bin 0x04000000 448 tiny_weights.bin 0x12000000 1993472 input.bin 0x05000000 6272} {
		infer_load $payload $name $address $bytes $run_dir
	}
	mwr 0x04200000 0xA5A5A5A5 6
	mwr 0x041FFFC0 0xA5A5A5A5 4
	mwr [expr {$csr_base + 8}] 0x04000000
	mwr [expr {$csr_base + 0x20}] 448
	check_word [expr {$csr_base + 8}] 0xFFFFFFFF 0x04000000 MODEL_BASE
	check_word [expr {$csr_base + 0x20}] 0xFFFFFFFF 448 MODEL_BYTES
	mwr $csr_base 1
	set status [cu8_wait $csr_base done 60000]
	set error_code [cu8_word [expr {$csr_base + 0x18}]]
	set layer [cu8_word [expr {$csr_base + 0x14}]]
	set low [cu8_word [expr {$csr_base + 0x0C}]]
	set high [cu8_word [expr {$csr_base + 0x10}]]
	set cycles [expr {($high << 32) | $low}]
	save_text [file join $run_dir csr.txt] "$status $error_code $layer $cycles"
	mrd -bin -file [file join $run_dir output.bin] 0x04200000 6
	mrd -bin -file [file join $run_dir runtime.bin] 0x041FFFC0 4
	require {$error_code == 0 && $layer == 5 && $cycles > 0} "Invalid completion CSR"
	require {[read_binary [file join $run_dir output.bin]] eq [read_binary [file join $payload expected.bin]]} "INT16 output mismatch"
	binary scan [read_binary [file join $run_dir runtime.bin]] iu* words
	require {$words eq [list $low $high 5 1]} "GP runtime record mismatch"
	save_text [file join $run_dir result.txt] "PASS TinyCNN inference"
	disconnect
}

if {![info exists ::infer_library_only]} {
	if {[llength $argv] != 2} {puts stderr "Use scripts/jtag/infer_tiny.py <new run directory>"; exit 2}
	if {[catch {infer_run [file normalize [lindex $argv 0]] [file normalize [lindex $argv 1]]} message options]} {
		puts stderr "$message\n[dict get $options -errorinfo]"
		if {[info exists ::infer_run_dir]} {
			catch {save_text [file join $::infer_run_dir failure_csr.txt] [mrd -value 0x43C00000 9]}
			catch {mrd -bin -file [file join $::infer_run_dir failure_runtime.bin] 0x041FFFC0 4}
			save_text [file join $::infer_run_dir result.txt] "FAIL TinyCNN: $message"
		}
		catch {disconnect}
		exit 1
	}
}
