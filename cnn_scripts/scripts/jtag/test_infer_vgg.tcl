# All XSDB commands below are mocks. Never use these files as board evidence.
set ::vgg_library_only 1
source [file join [file dirname [info script]] infer_vgg.tcl]
unset ::vgg_library_only
proc verify_artifacts {args} {error "SHA checks must not be called"}
set root [file normalize [lindex $argv 0]]
set payload [file join $root payload]
file mkdir $payload
set data [string repeat "\x37" 1472]
set fd [open [file join $payload vgg_cmd.bin] wb]
puts -nonewline $fd $data
close $fd
set ::vgg_chunk_bytes 256
set ::corrupt 0
set ::fail_download 0
set ::writes 0
proc dow {mode path address} {
	require {$mode eq "-data"} "Unexpected download mode"
	if {$::fail_download} {error "Invalid DAP ACK value: 6"}
	set ::memory($address) [read_binary $path]
	incr ::writes
}
proc mrd {args} {
	lassign $args mode option path address words
	require {$mode eq "-bin" && $option eq "-file"} "Unexpected memory read"
	set data $::memory($address)
	require {[string length $data] == $words * 4} "Wrong XSDB word count"
	if {$::corrupt} {set data [string replace $data 0 0 "\x00"]}
	set fd [open $path wb]
	puts -nonewline $fd $data
	close $fd
}
vgg_load $payload vgg_cmd.bin 0x04000000 1472 $root
require {$::writes == 6} "Expected five 256-byte chunks and a 192-byte tail"
require {[read_binary [file join $root vgg_cmd.bin.readback]] eq $data} "Chunk join mismatch"
require {![file exists [file join $root transfer.bin]]} "Successful transfer left temporary chunk"
set ::corrupt 1
require {[catch {vgg_load $payload vgg_cmd.bin 0x04000000 1472 $root}]} "Corrupt DDR readback accepted"
require {[string match "*phase=readback" $::vgg_transfer_context]} "Missing failed readback context"
set ::corrupt 0
set ::fail_download 1
require {[catch {vgg_load $payload vgg_cmd.bin 0x04000000 1472 $root}]} "Failed download accepted"
require {[string match "file=vgg_cmd.bin\noffset=0\naddress=0x04000000\n*phase=download" $::vgg_transfer_context]} "Missing failed download context"
set ::fail_download 0
unset ::vgg_transfer_context
set before $::writes
require {[catch {vgg_load $payload vgg_cmd.bin 0x04000004 1472 $root}]} "Invalid address accepted"
require {$::writes == $before} "Invalid transfer reached hardware"

set ::vgg_chunk_bytes 262144
set ::vgg_batch_address 0x06000000
set ::vgg_batch_bytes 401408
set batch_data [string repeat "\x37" 401408]
set fd [open [file join $payload input_bin.bin] wb]
puts -nonewline $fd $batch_data
close $fd
vgg_load $payload input_bin.bin 0x06000000 401408 $root
set before $::writes
vgg_load $payload input_bin.bin 0x06000000 401408 $root 0
require {$::writes == $before} "Final bank verification downloaded inputs again"
require {[read_binary [file join $root input_bin.bin.final_readback]] eq $batch_data} "Resident bank readback mismatch"
set ::corrupt 1
require {[catch {vgg_load $payload input_bin.bin 0x06000000 401408 $root 0}]} "Overwritten resident inputs accepted"
set ::corrupt 0
require {[catch {vgg_load $payload input_bin.bin 0x05000000 401408 $root}]} "Working-buffer overlap accepted"
unset -nocomplain ::vgg_transfer_context

# Exercise the complete controller with fake transfers and synthetic completion.
rename vgg_load vgg_load_checked
proc vgg_load {payload name address bytes run_dir {download 1}} {
	if {$download} {
		lappend ::transfers [list $name $address $bytes]
		if {$name eq "vgg_cmd.bin"} {set ::registers(67108928) 0x05000000}
	} else {
		incr ::bank_checks
	}
}
proc check_cache_state {args} {return {00000000 00000000}}
proc version {} {return MOCK}
proc connect {args} {require {$args eq {-url tcp:127.0.0.1:3121}} "Wrong server"}
proc stop_core {id} {require {$id in {cpu0 cpu1}} "Wrong CPU"}
proc rst {args} {require {$args eq {-system -stop}} "Wrong reset"}
proc fpga {args} {incr ::programmed}
proc loadhw {args} {}
set ::mock_jtag_hz 15000000
set ::mock_frequency_writes 0
set ::mock_bad_chain 0
set ::programmed 0
proc targets {args} {
	require {$::mock_jtag_hz == 1000000} "CPU lookup happened before JTAG frequency setup"
	if {[lindex $args 0] ne "-target-properties"} {return}
	if {$::mock_bad_chain} {
		if {[llength $args] > 1} {return {}}
		return [list [dict create target_id 1 name {whole scan chain (DR shift through all zeroes)}]]
	}
	set result {}
	foreach {id name} {cpu0 {ARM Cortex-A9 MPCore #0} cpu1 {ARM Cortex-A9 MPCore #1} fpga xc7z020} {
		if {[llength $args] == 1 || [lindex $args 2] eq "name == \"$name\""} {
			lappend result [dict create target_id $id name $name]
		}
	}
	return $result
}
proc jtag {command args} {
	switch $command {
		targets {
			if {[lindex $args 0] eq "-target-properties"} {return [list [dict create node_id mock_cable]]}
			require {$args eq "mock_cable"} "Wrong cable selected"
		}
		frequency {
			if {$args eq "-list"} {return {1000000 6000000 15000000}}
			if {[llength $args] == 1} {
				set ::mock_jtag_hz [lindex $args 0]
				incr ::mock_frequency_writes
			}
			return $::mock_jtag_hz
		}
		default {error "Unexpected JTAG command"}
	}
}
proc disconnect {} {}
set ::started 0
set ::mock_done 0
set ::mock_resets 0
set ::fail_on_start 0
set ::bank_checks 0
set ::error_status 0
set ::transfers {}
proc mwr {address value {count 1}} {
	lappend ::register_writes [list $address $value $count]
	set ::registers($address) $value
	if {$address == 0x43C00000} {
		require {$count == 1} "Unexpected CONTROL word count"
		switch $value {
			1 {
				require {!$::mock_done} "Restart without clearing completion"
				incr ::started
				set ::mock_done 1
				if {$::started == $::fail_on_start} {error "mock image failure"}
			}
			8 {set ::mock_done 0}
			2 {
				require {!$::mock_done} "Reset before clearing completion"
				incr ::mock_resets
			}
			default {error "Unexpected CONTROL write"}
		}
	}
}
proc mrd {args} {
	if {[lindex $args 0] eq "-value"} {
		set address [lindex $args 1]
		switch [format %08X $address] {
			F800025C {return 0}
			43C00004 {return [expr {$::error_status ? 4 : ($::mock_done ? 2 : 0x40)}]}
			43C00018 {return 0}
			43C00014 {return 20}
			43C0000C {return [expr {0x89ABCDEF + $::started - 1}]}
			43C00010 {return 1}
			43C0001C {return 0x20261015}
			default {return $::registers($address)}
		}
	}
	lassign $args mode option path address words
	if {$address == 0x04200000} {
		require {$words == 500} "VGG output must read 500 words"
		set logits [lrepeat 1000 0]
		lset logits $::started 100
		set data [binary format s* $logits]
	} else {
		require {$address == 0x041FFFC0 && $words == 4} "Wrong runtime read"
		set data [binary format i* [list [expr {0x89ABCDEF + $::started - 1}] 1 20 1]]
	}
	set fd [open $path wb]
	puts -nonewline $fd $data
	close $fd
}
set run [file join $root run]
set bundle [file join $root hardware]
file mkdir [file join $run payload] $bundle
save_text [file join $run request.json] "{}"
foreach {name bytes} {vgg_cmd.bin 1472 vgg_weights.bin 286836800 input.bin 401408} {
	set fd [open [file join $run payload $name] wb]
	seek $fd [expr {$bytes - 1}]
	puts -nonewline $fd "\x00"
	close $fd
}
foreach name {e_j2.xsa e_j2_system_wrapper.bit} {
	save_text [file join $bundle $name] MOCK
}
save_text [file join $bundle init_checks.tcl] {set ps_readback_checks {}}
save_text [file join $bundle ps7_init.tcl] {proc ps7_init {} {}; proc ps7_post_config {} {}}
save_text [file join $bundle address_map.tcl] {set csr_base 0x43C00000; set expected_build_id 0x20261015}
set ::mock_bad_chain 1
require {[catch {vgg_run $bundle $run 1000 1000000} message]} "All-zero scan chain accepted"
require {[string match "*matches=0*whole scan chain*all zeroes*" $message]} "Missing target failure omitted scan chain evidence"
require {$::started == 0 && $::programmed == 0 && [llength $::transfers] == 0} "Bad scan chain reached programming or inference"
require {[file exists [file join $run jtag.txt]] && [file exists [file join $run targets_before_init.txt]]} "Early failure lost diagnostics"
file delete [file join $run result.txt]
set ::mock_bad_chain 0
set ::mock_jtag_hz 15000000
vgg_run $bundle $run 1000 1000000
require {$::programmed == 1} "Initialization did not program the FPGA"
require {$::mock_jtag_hz == 1000000} "JTAG frequency not applied"
require {[string match "*actual_hz=1000000" [string trim [read_binary [file join $run jtag.txt]]]]} "JTAG frequency not recorded"
require {$::started == 1 && [llength $::transfers] == 3} "Wrong start or transfer count"
require {[lindex $::transfers 1] eq {vgg_weights.bin 0x12000000 286836800}} "Wrong VGG weight contract"
require {[lsearch -exact $::register_writes {0x04200000 0xA5A5A5A5 500}] >= 0} "Wrong output sentinel length"
require {[string trim [read_binary [file join $run csr.txt]]] eq "2 0 20 6604705263"} "64-bit cycle read failed"
require {[string trim [read_binary [file join $run result.txt]]] eq "PASS VGG16 execution"} "Missing completion marker"
require {[catch {vgg_run $bundle $run 1000 1000000}]} "Reused run accepted"

proc batch_fixture {directory} {
	file mkdir [file join $directory payload]
	save_text [file join $directory request.json] "{}"
	save_text [file join $directory batch.tsv] "100663296\t1204224\t401408\t3\t67108928\t83886080"
	foreach {name bytes} {vgg_cmd.bin 1472 vgg_weights.bin 286836800 input_bin.bin 1204224} {
		set fd [open [file join $directory payload $name] wb]
		seek $fd [expr {$bytes - 1}]
		puts -nonewline $fd "\x00"
		close $fd
	}
	set ::started 0
	set ::mock_done 0
	set ::mock_resets 0
	set ::programmed 0
	set ::bank_checks 0
	set ::transfers {}
}
set batch_run [file join $root batch_run]
batch_fixture $batch_run
foreach invalid {
	{83886080 1204224 401408 3 67108928 83886080}
	{100663296 1204224 401408 4 67108928 83886080}
	{100663296 1204224 401408 3 67108932 83886080}
} {
	save_text [file join $batch_run batch.tsv] [join $invalid \t]
	require {[catch {vgg_run $bundle $batch_run 1000 1000000}]} "Invalid batch layout accepted"
	require {$::programmed == 0 && $::started == 0 && [llength $::transfers] == 0} "Invalid batch reached hardware"
}
save_text [file join $batch_run batch.tsv] "100663296\t1204224\t401408\t3\t67108928\t83886080"
vgg_run $bundle $batch_run 1000 1000000
require {$::programmed == 1 && $::started == 3 && $::mock_resets == 2} "Batch initialization/restart count wrong"
require {[llength $::transfers] == 3 && $::bank_checks == 1} "Batch payload downloaded more than once or bank not rechecked"
require {[lindex $::transfers 1] eq {vgg_weights.bin 0x12000000 286836800}} "Batch weight transfer changed"
require {$::registers(67108928) == 0x05000000} "First instruction was not restored"
for {set index 0} {$index < 3} {incr index} {
	set directory [file join $batch_run images [format %04d [expr {$index + 1}]]]
	require {[string trim [read_binary [file join $directory input_address.txt]]] eq [format 0x%08X [expr {0x06000000 + $index * 401408}]]} "Batch input address wrong"
	binary scan [read_binary [file join $directory output.bin]] s* logits
	require {[lindex $logits [expr {$index + 1}]] == 100} "Per-image output overwritten"
	require {[string trim [read_binary [file join $directory result.txt]]] eq "PASS VGG16 execution"} "Missing per-image marker"
}
set failed_run [file join $root failed_batch]
batch_fixture $failed_run
set ::fail_on_start 2
require {[catch {vgg_run $bundle $failed_run 1000 1000000} message]} "Failed image accepted"
require {$message eq "mock image failure" && $::started == 2} "Batch did not stop at failed image"
require {[file exists [file join $failed_run images 0001 output.bin]]} "Failure discarded completed image"
require {![file exists [file join $failed_run images 0003]]} "Batch continued after failure"
set ::fail_on_start 0
set frequency_writes $::mock_frequency_writes
require {[initialize_e_j0 $bundle e_j2_system_wrapper.bit e_j2.xsa] eq {cpu0 cpu1}} "Legacy initialization failed"
require {$::mock_frequency_writes == $frequency_writes} "Legacy caller unexpectedly changed JTAG frequency"
set ::error_status 1
require {[catch {cu8_wait 0x43C00000 done 1}]} "CSR error accepted"
puts "PASS VGG Tcl MOCK ONLY: single/batch, chunks, input-bank immutability, one-time transfers, restarts, addresses, isolated outputs, partial failure, 64-bit cycles, early JTAG setup"
