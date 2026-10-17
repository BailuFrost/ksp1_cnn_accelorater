# Run with XSDB after a power cycle in JTAG mode; --self-test never connects.
proc require {condition message} {
	if {![uplevel 1 [list expr $condition]]} {error $message}
}

proc read_binary {path} {
	set fd [open $path rb]
	set data [read $fd]
	close $fd
	return $data
}

proc make_pattern {kind address bytes} {
	require {$bytes > 0 && $bytes % 4 == 0} "Pattern size must be positive and word aligned"
	set words {}
	for {set index 0} {$index < $bytes / 4} {incr index} {
		switch $kind {
			zero {set word 0}
			ones {set word 0xFFFFFFFF}
			alternating_a {set word 0xAAAAAAAA}
			alternating_5 {set word 0x55555555}
			address {set word [expr {$address + 4 * $index}]}
			walking_one {set word [expr {1 << ($index % 32)}]}
			walking_zero {set word [expr {(1 << ($index % 32)) ^ 0xFFFFFFFF}]}
			default {error "Unknown DDR pattern: $kind"}
		}
		lappend words $word
	}
	return [binary format i* $words]
}

proc unique_target {filter} {
	set matches [targets -target-properties -filter $filter]
	require {[llength $matches] == 1} "Missing or ambiguous hardware target: $filter"
	return [dict get [lindex $matches 0] target_id]
}

proc stop_core {id} {
	targets $id
	if {![string match Stopped* [state]]} {stop -timeout 5000}
	require {[string match Stopped* [state]]} "ARM core did not stop"
}

proc check_word {address mask expected label} {
	set value [lindex [mrd -value $address 1] 0]
	puts [format "%s @0x%08X = 0x%08X" $label $address $value]
	require {($value & $mask) == ($expected & $mask)} "Readback mismatch: $label"
}

proc verify_artifacts {bundle {required {e_j0.xsa e_j0_system_wrapper.bit ps7_init.tcl address_map.tcl init_checks.tcl implementation_summary.json simulation_summary.json}}} {
	set fd [open [file join $bundle artifact_hashes.tsv] r]
	set lines [split [read $fd] \n]
	close $fd
	set names {}
	foreach line [lrange $lines 1 end] {
		if {$line eq ""} {continue}
		lassign [split $line \t] name expected
		require {[file tail $name] eq $name && [regexp {^[0-9a-f]{64}$} $expected]} "Invalid artifact hash record"
		set path [file join $bundle $name]
		require {[file isfile $path]} "Missing hardware artifact: $path"
		set text [exec certutil -hashfile $path SHA256]
		require {[regexp -line {^([0-9a-fA-F]{64})\r?$} $text -> actual]} "Cannot parse SHA256: $name"
		require {[string tolower $actual] eq $expected} "Artifact changed: $name"
		lappend names $name
	}
	foreach name $required {
		require {$name in $names} "Required artifact is not covered by hashes: $name"
	}
}

proc self_test {} {
	binary scan [make_pattern address 0x26000000 8] i* words
	require {$words eq {637534208 637534212}} "Address pattern or byte order failed"
	binary scan [make_pattern alternating_a 0 4] H* hex
	require {$hex eq "aaaaaaaa"} "Constant pattern failed"
	binary scan [make_pattern walking_one 0 128] i* words
	require {[lindex $words 0] == 1 && [lindex $words 31] == -2147483648} "Walking bit pattern failed"
	require {[catch {make_pattern invalid 0 4}]} "Unknown pattern accepted"
	require {[catch {make_pattern zero 0 3}]} "Unaligned pattern accepted"
	require {[catch {make_pattern zero 0 0}]} "Empty pattern accepted"
	puts "PASS E-J0 Tcl pattern self-test (no hardware connected)"
}

proc initialize_e_j0 {bundle {bit_name e_j0_system_wrapper.bit} {xsa_name e_j0.xsa}} {
	source [file join $bundle init_checks.tcl]
	connect -url tcp:127.0.0.1:3121
	puts "TARGETS: [targets -target-properties]"
	set cpu0 [unique_target {name == "ARM Cortex-A9 MPCore #0"}]
	set cpu1 [unique_target {name == "ARM Cortex-A9 MPCore #1"}]
	set fpga_id [unique_target {name == "xc7z020"}]
	stop_core $cpu0
	stop_core $cpu1
	targets $cpu0
	check_word 0xF800025C 7 0 "BOOT_MODE (JTAG)"
	rst -system -stop
	set cpu0 [unique_target {name == "ARM Cortex-A9 MPCore #0"}]
	set cpu1 [unique_target {name == "ARM Cortex-A9 MPCore #1"}]
	set fpga_id [unique_target {name == "xc7z020"}]
	stop_core $cpu0
	stop_core $cpu1
	targets $cpu0
	# Generated PS procedures use namespace globals, not main's local variables.
	uplevel #0 [list source [file join $bundle ps7_init.tcl]]
	ps7_init
	targets $fpga_id
	fpga -file [file join $bundle $bit_name]
	targets $cpu0
	ps7_post_config
	# XSDB needs the matching XSA memory map before allowing PL CSR accesses.
	loadhw -hw [file join $bundle $xsa_name]
	foreach {address mask value label} $ps_readback_checks {
		check_word $address $mask $value $label
	}
	return [list $cpu0 $cpu1]
}

proc check_e_j0_csr {csr_base expected_build_id} {
	check_word [expr {$csr_base + 0x1C}] 0xFFFFFFFF $expected_build_id BUILD_ID
	check_word [expr {$csr_base + 4}] 0x7F 0 "E-J0 STATUS (start disabled)"
	foreach {offset value} {0x08 0x04000000 0x20 320} {
		mwr [expr {$csr_base + $offset}] $value
		check_word [expr {$csr_base + $offset}] 0xFFFFFFFF $value "CSR write/read"
		mwr [expr {$csr_base + $offset}] 0
		check_word [expr {$csr_base + $offset}] 0xFFFFFFFF 0 "CSR restored"
	}
}

proc main {bundle run_dir} {
	require {![file exists $run_dir]} "Run directory already exists; choose a new directory"
	verify_artifacts $bundle
	source [file join $bundle address_map.tcl]
	require {$ddr_test_bytes == 4096} "Unexpected DDR smoke-test size"
	foreach address $ddr_test_addresses {
		require {$address >= 0x26000000 && $address + $ddr_test_bytes <= 0x40000000 && $address % 4096 == 0} "DDR test range is outside the reserved workspace"
	}
	file mkdir $run_dir
	set ::run_created $run_dir
	set result [open [file join $run_dir result.txt] w]
	puts $result "RUNNING"
	close $result
	lassign [initialize_e_j0 $bundle] cpu0 cpu1
	check_e_j0_csr $csr_base $expected_build_id
	# Write every block before reading any block to expose address aliasing.
	foreach kind {zero ones alternating_a alternating_5 address walking_one walking_zero} {
		foreach address $ddr_test_addresses {
			set input [file join $run_dir [format "%s_%08X.bin" $kind $address]]
			set fd [open $input wb]
			puts -nonewline $fd [make_pattern $kind $address $ddr_test_bytes]
			close $fd
			dow -data $input $address
		}
		foreach address $ddr_test_addresses {
			set output [file join $run_dir [format "%s_%08X_readback.bin" $kind $address]]
			mrd -bin -file $output $address [expr {$ddr_test_bytes / 4}]
			require {[read_binary $output] eq [make_pattern $kind $address $ddr_test_bytes]} "DDR mismatch: $kind at $address"
		}
		puts "PASS DDR pattern $kind: four 4096-byte blocks"
	}
	stop_core $cpu0
	stop_core $cpu1
	set result [open [file join $run_dir result.txt] w]
	puts $result "PASS E-J0 DDR/CSR/init readback smoke test; no CNN/DataMover verification"
	close $result
	disconnect
}

if {[info exists ::e_j0_library_only] && $::e_j0_library_only} {
	# E-J1 reuses the validated initialization and CSR procedures without running main.
} elseif {[llength $argv] == 1 && [lindex $argv 0] eq "--self-test"} {
	self_test
} elseif {[llength $argv] == 2} {
	if {[catch {main [file normalize [lindex $argv 0]] [file normalize [lindex $argv 1]]} message options]} {
		puts stderr "FAIL E-J0: $message"
		puts stderr [dict get $options -errorinfo]
		if {[info exists ::run_created]} {
			set result [open [file join $::run_created result.txt] w]
			puts $result "FAIL E-J0: $message"
			close $result
		}
		exit 1
	}
} else {
	puts stderr "Usage: xsdb check_e_j0.tcl <E-J0 bundle directory> <new run directory>"
	exit 2
}
