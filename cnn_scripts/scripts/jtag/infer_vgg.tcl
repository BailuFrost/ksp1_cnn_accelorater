# Reuse initialization, cache checks and CSR polling without running test entries.
set ::cu8_library_only 1
source [file join [file dirname [info script]] test_cu8_board.tcl]
unset ::cu8_library_only
set ::vgg_chunk_bytes 262144

proc vgg_load {payload name address bytes run_dir {download 1}} {
	set path [file join $payload $name]
	set valid [expr {[list $name $address $bytes] in {
		{vgg_cmd.bin 0x04000000 1472} {vgg_weights.bin 0x12000000 286836800} {input.bin 0x05000000 401408}
	}}]
	if {$name eq "input_bin.bin" && [info exists ::vgg_batch_address]} {
		set valid [expr {$address == $::vgg_batch_address && $bytes == $::vgg_batch_bytes
			&& $address >= 0x05620000 && $address % 64 == 0 && $bytes > 0
			&& $bytes % 401408 == 0 && $address + $bytes <= 0x0B000000}]
	}
	require {$valid && $download in {0 1}} "Invalid VGG16 transfer"
	require {[file size $path] == $bytes} "VGG16 file length mismatch: $name"
	require {$::vgg_chunk_bytes > 0 && $::vgg_chunk_bytes % 4 == 0} "Invalid transfer chunk size"
	set chunk_path [file join $run_dir transfer.bin]
	set chunk_readback [file join $run_dir transfer.readback]
	set source [open $path rb]
	set suffix [expr {$download ? "readback" : "final_readback"}]
	set output [open [file join $run_dir $name.$suffix] wb]
	try {
		for {set offset 0} {$offset < $bytes} {incr offset $count} {
			set count [expr {min($::vgg_chunk_bytes, $bytes - $offset)}]
			set data [read $source $count]
			require {[string length $data] == $count} "Short payload read: $name"
			set fd [open $chunk_path wb]
			puts -nonewline $fd $data
			close $fd
			if {$download} {
				set ::vgg_transfer_context "file=$name\noffset=$offset\naddress=[format 0x%08X [expr {$address + $offset}]]\nbytes=$count\nverified_prefix_bytes=$offset\nphase=download"
				dow -data $chunk_path [expr {$address + $offset}]
			}
			set ::vgg_transfer_context "file=$name\noffset=$offset\naddress=[format 0x%08X [expr {$address + $offset}]]\nbytes=$count\nverified_prefix_bytes=$offset\nphase=readback"
			mrd -bin -file $chunk_readback [expr {$address + $offset}] [expr {$count / 4}]
			set actual [read_binary $chunk_readback]
			require {$actual eq $data} "DDR readback mismatch: $name offset=$offset"
			puts -nonewline $output $actual
			if {($offset + $count) % 16777216 == 0 || $offset + $count == $bytes} {
				puts "DDR verified $name [expr {$offset + $count}]/$bytes bytes"
				flush stdout
			}
		}
		require {[read $source 1] eq ""} "Payload changed length: $name"
	} finally {
		close $source
		close $output
	}
	file delete -force $chunk_path $chunk_readback
	unset ::vgg_transfer_context
}

proc vgg_infer {csr_base run_dir timeout_ms} {
	mwr 0x04200000 0xA5A5A5A5 500
	mwr 0x041FFFC0 0xA5A5A5A5 4
	mwr [expr {$csr_base + 8}] 0x04000000
	mwr [expr {$csr_base + 0x20}] 1472
	check_word [expr {$csr_base + 8}] 0xFFFFFFFF 0x04000000 MODEL_BASE
	check_word [expr {$csr_base + 0x20}] 0xFFFFFFFF 1472 MODEL_BYTES
	mwr $csr_base 1
	set status [cu8_wait $csr_base done $timeout_ms]
	set error_code [cu8_word [expr {$csr_base + 0x18}]]
	set layer [cu8_word [expr {$csr_base + 0x14}]]
	set low [cu8_word [expr {$csr_base + 0x0C}]]
	set high [cu8_word [expr {$csr_base + 0x10}]]
	set cycles [expr {($high << 32) | $low}]
	save_text [file join $run_dir csr.txt] "$status $error_code $layer $cycles"
	mrd -bin -file [file join $run_dir output.bin] 0x04200000 500
	mrd -bin -file [file join $run_dir runtime.bin] 0x041FFFC0 4
	require {($status & 0x77) == 2 && $error_code == 0 && $layer == 20 && $cycles > 0} "Invalid VGG16 completion CSR"
	require {[file size [file join $run_dir output.bin]] == 2000 && [file size [file join $run_dir runtime.bin]] == 16} "Invalid output length"
	binary scan [read_binary [file join $run_dir runtime.bin]] iu* words
	require {$words eq [list $low $high 20 1]} "GP runtime record mismatch"
	save_text [file join $run_dir result.txt] "PASS VGG16 execution"
}

proc vgg_run {bundle run_dir timeout_ms jtag_hz} {
	require {[string is integer -strict $timeout_ms] && $timeout_ms > 0} "Invalid inference timeout"
	require {[string is integer -strict $jtag_hz] && $jtag_hz > 0} "Invalid JTAG frequency"
	require {[file isdirectory $run_dir] && [file isfile [file join $run_dir request.json]]
		&& ![file exists [file join $run_dir result.txt]]} "Use a new Python-prepared directory"
	set payload [file join $run_dir payload]
	set batch [file exists [file join $run_dir batch.tsv]]
	set input_name input.bin
	set input_address 0x05000000
	set input_bytes 401408
	if {$batch} {
		set values [split [string trim [read_binary [file join $run_dir batch.tsv]]]]
		require {[llength $values] == 6} "Invalid batch control record"
		foreach value $values {require {[string is wideinteger -strict $value]} "Non-integer batch control value"}
		lassign $values input_address input_bytes stride count patch original
		require {$stride == 401408 && $count > 0 && $input_bytes == $stride * $count
			&& $input_address % 64 == 0 && $input_address >= 0x05620000
			&& $input_address + $input_bytes <= 0x0B000000
			&& $patch == 0x04000040 && $original == 0x05000000} "Invalid batch addresses or size"
		set ::vgg_batch_address $input_address
		set ::vgg_batch_bytes $input_bytes
		set input_name input_bin.bin
	}
	foreach {name bytes} [list vgg_cmd.bin 1472 vgg_weights.bin 286836800 $input_name $input_bytes] {
		require {[file isfile [file join $payload $name]] && [file size [file join $payload $name]] == $bytes} "Invalid payload: $name"
	}
	foreach name {e_j2.xsa e_j2_system_wrapper.bit ps7_init.tcl address_map.tcl init_checks.tcl} {
		require {[file isfile [file join $bundle $name]] && [file size [file join $bundle $name]] > 0} "Missing hardware file: $name"
	}
	source [file join $bundle address_map.tcl]
	require {$csr_base == 0x43C00000 && $expected_build_id == 0x20261015} "Wrong hardware map"
	set ::vgg_run_dir $run_dir
	unset -nocomplain ::vgg_active_image
	save_text [file join $run_dir result.txt] RUNNING
	save_text [file join $run_dir execution_kind.txt] HARDWARE
	save_text [file join $run_dir tool_version.txt] [version]
	lassign [initialize_e_j0 $bundle e_j2_system_wrapper.bit e_j2.xsa $jtag_hz $run_dir] cpu0 cpu1
	save_text [file join $run_dir targets.txt] [targets -target-properties]
	puts "transfer_chunk_bytes=$::vgg_chunk_bytes"
	flush stdout
	save_text [file join $run_dir cache_state.txt] [check_cache_state $cpu0 $cpu1]
	check_word [expr {$csr_base + 0x1C}] 0xFFFFFFFF $expected_build_id BUILD_ID
	cu8_wait $csr_base ready 5000
	foreach {name address bytes} [list vgg_cmd.bin 0x04000000 1472 vgg_weights.bin 0x12000000 286836800 $input_name $input_address $input_bytes] {
		vgg_load $payload $name $address $bytes $run_dir
	}
	if {$batch} {
		check_word $patch 0xFFFFFFFF $original ORIGINAL_INPUT
		for {set index 0} {$index < $count} {incr index} {
			set directory [file join $run_dir images [format %04d [expr {$index + 1}]]]
			file mkdir $directory
			set ::vgg_active_image $directory
			if {$index > 0} {
				mwr $csr_base 8
				cu8_wait $csr_base ready 5000
				mwr $csr_base 2
				cu8_wait $csr_base ready 5000
			}
			set address [expr {$input_address + $index * $stride}]
			mwr $patch $address
			check_word $patch 0xFFFFFFFF $address IMAGE_INPUT
			save_text [file join $directory input_address.txt] [format 0x%08X $address]
			vgg_infer $csr_base $directory $timeout_ms
			puts "PASS VGG16 image=[expr {$index + 1}]/$count input=[format 0x%08X $address]"
			flush stdout
		}
		unset ::vgg_active_image
		mwr $patch $original
		check_word $patch 0xFFFFFFFF $original RESTORED_INPUT
		save_text [file join $run_dir restored_input_address.txt] [format 0x%08X $original]
		# Recheck the resident inputs after all layers have written their intermediate features.
		vgg_load $payload $input_name $input_address $input_bytes $run_dir 0
	} else {
		vgg_infer $csr_base $run_dir $timeout_ms
	}
	save_text [file join $run_dir final_cache_state.txt] [check_cache_state $cpu0 $cpu1]
	save_text [file join $run_dir result.txt] "PASS VGG16 execution"
	disconnect
}

if {![info exists ::vgg_library_only]} {
	if {[llength $argv] != 4} {puts stderr "Use infer_vgg.py with its fixed path configuration"; exit 2}
	if {[catch {vgg_run [file normalize [lindex $argv 0]] [file normalize [lindex $argv 1]] [lindex $argv 2] [lindex $argv 3]} message options]} {
		puts stderr "$message\n[dict get $options -errorinfo]"
		if {[info exists ::vgg_run_dir]} {
			if {[info exists ::vgg_transfer_context]} {
				save_text [file join $::vgg_run_dir failure_transfer.txt] $::vgg_transfer_context
			}
			catch {save_text [file join $::vgg_run_dir failure_csr.txt] [mrd -value 0x43C00000 9]}
			catch {mrd -bin -file [file join $::vgg_run_dir failure_runtime.bin] 0x041FFFC0 4}
			if {[info exists ::vgg_active_image]} {
				save_text [file join $::vgg_active_image result.txt] "FAIL VGG16: $message"
				save_text [file join $::vgg_run_dir failed_image.txt] [file tail $::vgg_active_image]
			}
			save_text [file join $::vgg_run_dir result.txt] "FAIL VGG16: $message"
		}
		catch {disconnect}
		exit 1
	}
}
