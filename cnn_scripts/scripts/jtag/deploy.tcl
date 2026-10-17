# E-J1 platform access only. Power-cycle in JTAG mode before invoking this script.
# No CONTROL writes: this E-J0 platform cannot run CNN or DataMover tasks.
set ::e_j0_library_only 1
source [file join [file dirname [info script]] .. board check_e_j0.tcl]
unset ::e_j0_library_only

proc save_text {path data} {
	set fd [open $path w]
	puts $fd $data
	close $fd
}

proc validate_transfer {address bytes} {
	require {[string is entier -strict $address] && [string is entier -strict $bytes]} "DDR address and size must be integers"
	require {$bytes > 0 && $bytes <= 4194304 && $bytes % 4 == 0} "DDR size must be word aligned and within 4 MiB"
	require {$address >= 0x26000000 && $address % 4 == 0 && $address + $bytes <= 0x40000000} "DDR transfer is outside the reserved debug workspace"
}

proc check_cache_state {cpu0 cpu1} {
	set values {}
	foreach id [list $cpu0 $cpu1] {
		stop_core $id
		set regs [rrd -nvlist cp15 c1 sctlr]
		require {[dict exists $regs sctlr] && [regexp {^[0-9a-fA-F]{8}$} [dict get $regs sctlr]]} "Cannot read ARM SCTLR"
		scan [dict get $regs sctlr] %x value
		# MMU, data cache and instruction cache must remain disabled after cold reset.
		require {($value & 0x1005) == 0} "ARM MMU/cache enabled; power-cycle instead of taking over a live application"
		lappend values [format "0x%08X" $value]
	}
	targets $cpu0
	check_word 0xF8F02100 1 0 "L2 cache disabled"
	return $values
}

proc record_transfer {fd round kind address input output} {
	set bytes [file size $input]
	validate_transfer $address $bytes
	set start [clock clicks -microseconds]
	dow -data $input $address
	set write_us [expr {[clock clicks -microseconds] - $start}]
	set start [clock clicks -microseconds]
	# Default mrd size is 32 bits: bytes / 4 is the exact word count.
	mrd -bin -file $output $address [expr {$bytes / 4}]
	set read_us [expr {[clock clicks -microseconds] - $start}]
	require {$write_us > 0 && $read_us > 0} "Invalid transfer timer"
	require {[file size $output] == $bytes && [read_binary $output] eq [read_binary $input]} "DDR readback differs: $kind"
	puts $fd [join [list $round $kind [format "0x%08X" $address] $bytes $write_us $read_us [file tail $input] [file tail $output]] \t]
	flush $fd
	puts [format "PASS round=%d %s bytes=%d write=%.3f ms read=%.3f ms" $round $kind $bytes [expr {$write_us / 1000.0}] [expr {$read_us / 1000.0}]]
}

proc platform_access {bundle run_dir} {
	require {![file exists $run_dir]} "Run directory already exists; choose a new directory"
	verify_artifacts $bundle
	source [file join $bundle address_map.tcl]
	require {$ddr_test_bytes == 4096 && [llength $ddr_test_addresses] == 4} "Unexpected E-J0 DDR test geometry"
	foreach address $ddr_test_addresses {validate_transfer $address $ddr_test_bytes}
	file mkdir $run_dir
	set ::platform_run $run_dir
	save_text [file join $run_dir result.txt] RUNNING
	save_text [file join $run_dir execution_kind.txt] HARDWARE
	save_text [file join $run_dir tool_version.txt] [version]
	save_text [file join $run_dir platform.tsv] "csr_base\t[format 0x%08X $csr_base]\nexpected_build_id\t[format 0x%08X $expected_build_id]\nfclk_hz\t100000000\nplatform\tE-J0"
	set transfers [open [file join $run_dir transfers.tsv] w]
	puts $transfers "round\tkind\taddress\tbytes\twrite_us\tread_us\tinput\toutput"
	set sessions [open [file join $run_dir sessions.tsv] w]
	puts $sessions "round\tinitialize_us\tjtag_hz\tcpu0_sctlr\tcpu1_sctlr"
	try {
		for {set round 1} {$round <= 3} {incr round} {
			set start [clock clicks -microseconds]
			lassign [initialize_e_j0 $bundle] cpu0 cpu1
			set initialize_us [expr {[clock clicks -microseconds] - $start}]
			set cable [jtag targets -target-properties -filter {level == 0}]
			require {[llength $cable] == 1} "Missing or ambiguous JTAG cable"
			jtag targets [dict get [lindex $cable 0] node_id]
			set hz [jtag frequency]
			require {[string is integer -strict $hz] && $hz > 0} "Invalid actual JTAG frequency"
			if {$round == 1} {set initial_hz $hz}
			require {$hz == $initial_hz} "JTAG frequency changed between rounds"
			save_text [file join $run_dir targets_$round.txt] [targets -target-properties]
			save_text [file join $run_dir jtag_$round.txt] [jtag targets -target-properties]
			save_text [file join $run_dir jtag_supported_$round.txt] [jtag frequency -list]
			lassign [check_cache_state $cpu0 $cpu1] sctlr0 sctlr1
			check_e_j0_csr $csr_base $expected_build_id
			puts $sessions [join [list $round $initialize_us $hz $sctlr0 $sctlr1] \t]
			flush $sessions
			# Preserve E-J0's write-all/read-all ordering to detect address aliasing.
			foreach kind {zero ones alternating_a alternating_5 address walking_one walking_zero} {
				foreach address $ddr_test_addresses {
					set path [file join $run_dir [format "r%d_%s_%08X.bin" $round $kind $address]]
					set fd [open $path wb]
					puts -nonewline $fd [make_pattern $kind $address $ddr_test_bytes]
					close $fd
					dow -data $path $address
				}
				foreach address $ddr_test_addresses {
					set path [file join $run_dir [format "r%d_%s_%08X.bin" $round $kind $address]]
					set output [file rootname $path]_readback.bin
					mrd -bin -file $output $address [expr {$ddr_test_bytes / 4}]
					require {[read_binary $output] eq [read_binary $path]} "DDR smoke mismatch: $kind at $address"
				}
			}
			foreach bytes {4096 65536 401408 1048576 4194304} {
				set path [file join $run_dir r${round}_bulk_${bytes}.bin]
				set fd [open $path wb]
				puts -nonewline $fd [make_pattern address 0x26000000 $bytes]
				close $fd
				record_transfer $transfers $round address 0x26000000 $path [file rootname $path]_readback.bin
			}
			check_e_j0_csr $csr_base $expected_build_id
			check_cache_state $cpu0 $cpu1
			disconnect
		}
	} finally {
		close $transfers
		close $sessions
	}
	save_text [file join $run_dir result.txt] "PASS E-J1 platform access; no CNN/DataMover verification"
}

proc platform_self_test {} {
	self_test
	foreach {address bytes} {0x26000000 4096 0x3FFFF000 4096 0x26000000 401408} {validate_transfer $address $bytes}
	foreach {address bytes} {0x04000000 4096 0x26000001 4 0x3FFFFFFC 8 0x26000000 0 0x26000000 3 0x26000000 4194308 invalid 4} {
		require {[catch {validate_transfer $address $bytes}]} "Invalid DDR range was accepted"
	}
	puts "PASS E-J1 parameter/pattern self-test; hardware NOT_RUN"
}

if {![info exists ::e_j1_library_only]} {
	if {$argv eq {--self-test}} {
		if {[catch {platform_self_test} message]} {puts stderr $message; exit 1}
	} elseif {[llength $argv] == 3 && [lindex $argv 0] eq "--check-platform"} {
		if {[catch {platform_access [file normalize [lindex $argv 1]] [file normalize [lindex $argv 2]]} message options]} {
			puts stderr "FAIL E-J1: $message"
			puts stderr [dict get $options -errorinfo]
			if {[info exists ::platform_run]} {save_text [file join $::platform_run result.txt] "FAIL E-J1: $message"}
			catch {disconnect}
			exit 1
		}
	} else {
		puts stderr "Usage: xsdb deploy.tcl --check-platform <E-J0 bundle> <new run directory> | --self-test"
		exit 2
	}
}
