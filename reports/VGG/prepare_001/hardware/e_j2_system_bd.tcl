
################################################################
# This is a generated script based on design: e_j2_system
#
# Though there are limitations about the generated script,
# the main purpose of this utility is to make learning
# IP Integrator Tcl commands easier.
################################################################

namespace eval _tcl {
proc get_script_folder {} {
   set script_path [file normalize [info script]]
   set script_folder [file dirname $script_path]
   return $script_folder
}
}
variable script_folder
set script_folder [_tcl::get_script_folder]

################################################################
# Check if script is running in correct Vivado version.
################################################################
set scripts_vivado_version 2024.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
   puts ""
   if { [string compare $scripts_vivado_version $current_vivado_version] > 0 } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2042 -severity "ERROR" " This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Sourcing the script failed since it was created with a future version of Vivado."}

   } else {
     catch {common::send_gid_msg -ssname BD::TCL -id 2041 -severity "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_bd_tcl to create an updated script."}

   }

   return 1
}

################################################################
# START
################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source e_j2_system_script.tcl

# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./myproj/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
   create_project project_1 myproj -part xc7z020clg484-2
}


# CHANGE DESIGN NAME HERE
variable design_name
set design_name e_j2_system

# If you do not already have an existing IP Integrator design open,
# you can create a design using the following command:
#    create_bd_design $design_name

# Creating design if needed
set errMsg ""
set nRet 0

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

if { ${design_name} eq "" } {
   # USE CASES:
   #    1) Design_name not set

   set errMsg "Please set the variable <design_name> to a non-empty value."
   set nRet 1

} elseif { ${cur_design} ne "" && ${list_cells} eq "" } {
   # USE CASES:
   #    2): Current design opened AND is empty AND names same.
   #    3): Current design opened AND is empty AND names diff; design_name NOT in project.
   #    4): Current design opened AND is empty AND names diff; design_name exists in project.

   if { $cur_design ne $design_name } {
      common::send_gid_msg -ssname BD::TCL -id 2001 -severity "INFO" "Changing value of <design_name> from <$design_name> to <$cur_design> since current design is empty."
      set design_name [get_property NAME $cur_design]
   }
   common::send_gid_msg -ssname BD::TCL -id 2002 -severity "INFO" "Constructing design in IPI design <$cur_design>..."

} elseif { ${cur_design} ne "" && $list_cells ne "" && $cur_design eq $design_name } {
   # USE CASES:
   #    5) Current design opened AND has components AND same names.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 1
} elseif { [get_files -quiet ${design_name}.bd] ne "" } {
   # USE CASES: 
   #    6) Current opened design, has components, but diff names, design_name exists in project.
   #    7) No opened design, design_name exists in project.

   set errMsg "Design <$design_name> already exists in your project, please set the variable <design_name> to another value."
   set nRet 2

} else {
   # USE CASES:
   #    8) No opened design, design_name not in project.
   #    9) Current opened design, has components, but diff names, design_name not in project.

   common::send_gid_msg -ssname BD::TCL -id 2003 -severity "INFO" "Currently there is no design <$design_name> in project, so creating one..."

   create_bd_design $design_name

   common::send_gid_msg -ssname BD::TCL -id 2004 -severity "INFO" "Making design <$design_name> as current_bd_design."
   current_bd_design $design_name

}

common::send_gid_msg -ssname BD::TCL -id 2005 -severity "INFO" "Currently the variable <design_name> is equal to \"$design_name\"."

if { $nRet != 0 } {
   catch {common::send_gid_msg -ssname BD::TCL -id 2006 -severity "ERROR" $errMsg}
   return $nRet
}

set bCheckIPsPassed 1
##################################################################
# CHECK IPs
##################################################################
set bCheckIPs 1
if { $bCheckIPs == 1 } {
   set list_check_ips "\ 
xilinx.com:ip:processing_system7:5.5\
cnn.local:user:cnn_board_top:1.0\
xilinx.com:ip:proc_sys_reset:5.0\
xilinx.com:ip:xlconstant:1.1\
xilinx.com:ip:axi_datamover:5.1\
xilinx.com:ip:xlconcat:2.1\
"

   set list_ips_missing ""
   common::send_gid_msg -ssname BD::TCL -id 2011 -severity "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

   foreach ip_vlnv $list_check_ips {
      set ip_obj [get_ipdefs -all $ip_vlnv]
      if { $ip_obj eq "" } {
         lappend list_ips_missing $ip_vlnv
      }
   }

   if { $list_ips_missing ne "" } {
      catch {common::send_gid_msg -ssname BD::TCL -id 2012 -severity "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
      set bCheckIPsPassed 0
   }

}

if { $bCheckIPsPassed != 1 } {
  common::send_gid_msg -ssname BD::TCL -id 2023 -severity "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 3
}

##################################################################
# DESIGN PROCs
##################################################################



# Procedure to create entire design; Provide argument to make
# procedure reusable. If parentCell is "", will use root.
proc create_root_design { parentCell } {

  variable script_folder
  variable design_name

  if { $parentCell eq "" } {
     set parentCell [get_bd_cells /]
  }

  # Get object for parentCell
  set parentObj [get_bd_cells $parentCell]
  if { $parentObj == "" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2090 -severity "ERROR" "Unable to find parent cell <$parentCell>!"}
     return
  }

  # Make sure parentObj is hier blk
  set parentType [get_property TYPE $parentObj]
  if { $parentType ne "hier" } {
     catch {common::send_gid_msg -ssname BD::TCL -id 2091 -severity "ERROR" "Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."}
     return
  }

  # Save current instance; Restore later
  set oldCurInst [current_bd_instance .]

  # Set parent object as current
  current_bd_instance $parentObj


  # Create interface ports
  set DDR_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:interface:ddrx_rtl:1.0 DDR_0 ]

  set FIXED_IO_0 [ create_bd_intf_port -mode Master -vlnv xilinx.com:display_processing_system7:fixedio_rtl:1.0 FIXED_IO_0 ]


  # Create ports

  # Create instance: ps7, and set properties
  set ps7 [ create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7 ]
  set_property -dict [list \
    CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666687} \
    CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158730} \
    CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} \
    CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} \
    CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} \
    CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111115} \
    CONFIG.PCW_CLK0_FREQ {100000000} \
    CONFIG.PCW_CLK1_FREQ {10000000} \
    CONFIG.PCW_CLK2_FREQ {10000000} \
    CONFIG.PCW_CLK3_FREQ {10000000} \
    CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
    CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} \
    CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_ENET1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_EN_CLK0_PORT {1} \
    CONFIG.PCW_EN_CLK1_PORT {0} \
    CONFIG.PCW_EN_CLK2_PORT {0} \
    CONFIG.PCW_EN_CLK3_PORT {0} \
    CONFIG.PCW_EN_DDR {1} \
    CONFIG.PCW_EN_EMIO_UART0 {0} \
    CONFIG.PCW_EN_RST0_PORT {1} \
    CONFIG.PCW_EN_UART0 {1} \
    CONFIG.PCW_FCLK_CLK0_BUF {TRUE} \
    CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_FPGA_FCLK0_ENABLE {1} \
    CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_14_PULLUP {enabled} \
    CONFIG.PCW_MIO_14_SLEW {slow} \
    CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} \
    CONFIG.PCW_MIO_15_PULLUP {enabled} \
    CONFIG.PCW_MIO_15_SLEW {slow} \
    CONFIG.PCW_MIO_TREE_PERIPHERALS {unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#UART 0#UART\
0#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned}\
\
    CONFIG.PCW_MIO_TREE_SIGNALS {unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#rx#tx#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned#unassigned}\
\
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY0 {0.063} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY1 {0.062} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY2 {0.065} \
    CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY3 {0.083} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_0 {-0.007} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_1 {-0.010} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_2 {-0.006} \
    CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_3 {-0.048} \
    CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} \
    CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 1.8V} \
    CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_SD0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_UART0_BAUD_RATE {115200} \
    CONFIG.PCW_UART0_GRP_FULL_ENABLE {0} \
    CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
    CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
    CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} \
    CONFIG.PCW_UART_PERIPHERAL_VALID {1} \
    CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} \
    CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE {0} \
    CONFIG.PCW_UIPARAM_DDR_AL {0} \
    CONFIG.PCW_UIPARAM_DDR_BL {8} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.25} \
    CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM {0} \
    CONFIG.PCW_UIPARAM_DDR_ENABLE {1} \
    CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} \
    CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)} \
    CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} \
    CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} \
    CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {0} \
    CONFIG.PCW_USB0_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USB1_PERIPHERAL_ENABLE {0} \
    CONFIG.PCW_USE_M_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_GP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP0 {1} \
    CONFIG.PCW_USE_S_AXI_HP1 {1} \
    CONFIG.PCW_USE_S_AXI_HP2 {1} \
    CONFIG.PCW_USE_S_AXI_HP3 {0} \
  ] $ps7


  # Create instance: cnn, and set properties
  set cnn [ create_bd_cell -type ip -vlnv cnn.local:user:cnn_board_top:1.0 cnn ]

  # Create instance: reset_fclk0, and set properties
  set reset_fclk0 [ create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 reset_fclk0 ]
  set_property CONFIG.C_AUX_RESET_HIGH {1} $reset_fclk0


  # Create instance: zero, and set properties
  set zero [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 zero ]
  set_property CONFIG.CONST_VAL {0} $zero


  # Create instance: one, and set properties
  set one [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconstant:1.1 one ]
  set_property CONFIG.CONST_VAL {1} $one


  # Create instance: axi_control, and set properties
  set axi_control [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_control ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $axi_control


  # Create instance: axi_gp, and set properties
  set axi_gp [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_gp ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {2} \
  ] $axi_gp


  # Create instance: axi_feature, and set properties
  set axi_feature [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_feature ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $axi_feature


  # Create instance: axi_weight, and set properties
  set axi_weight [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_weight ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $axi_weight


  # Create instance: axi_output, and set properties
  set axi_output [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_output ]
  set_property -dict [list \
    CONFIG.NUM_MI {1} \
    CONFIG.NUM_SI {1} \
  ] $axi_output


  # Create instance: dma_gp, and set properties
  set dma_gp [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_datamover:5.1 dma_gp ]
  set_property -dict [list \
    CONFIG.c_addr_width {32} \
    CONFIG.c_dummy {0} \
    CONFIG.c_enable_mm2s {1} \
    CONFIG.c_enable_mm2s_adv_sig {1} \
    CONFIG.c_enable_s2mm {1} \
    CONFIG.c_enable_s2mm_adv_sig {1} \
    CONFIG.c_include_mm2s {Full} \
    CONFIG.c_include_s2mm {Full} \
    CONFIG.c_m_axi_mm2s_data_width {32} \
    CONFIG.c_m_axi_s2mm_data_width {32} \
    CONFIG.c_m_axis_mm2s_tdata_width {32} \
    CONFIG.c_mm2s_btt_used {23} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_mm2s_include_sf {false} \
    CONFIG.c_s2mm_btt_used {23} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_s_axis_s2mm_tdata_width {32} \
  ] $dma_gp


  # Create instance: dma_feature, and set properties
  set dma_feature [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_datamover:5.1 dma_feature ]
  set_property -dict [list \
    CONFIG.c_addr_width {32} \
    CONFIG.c_dummy {1} \
    CONFIG.c_enable_mm2s {1} \
    CONFIG.c_enable_mm2s_adv_sig {1} \
    CONFIG.c_enable_s2mm {0} \
    CONFIG.c_include_mm2s {Full} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_mm2s_btt_used {23} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_mm2s_include_sf {false} \
  ] $dma_feature


  # Create instance: dma_weight, and set properties
  set dma_weight [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_datamover:5.1 dma_weight ]
  set_property -dict [list \
    CONFIG.c_addr_width {32} \
    CONFIG.c_dummy {1} \
    CONFIG.c_enable_mm2s {1} \
    CONFIG.c_enable_mm2s_adv_sig {1} \
    CONFIG.c_enable_s2mm {0} \
    CONFIG.c_include_mm2s {Full} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {64} \
    CONFIG.c_mm2s_btt_used {23} \
    CONFIG.c_mm2s_burst_size {16} \
    CONFIG.c_mm2s_include_sf {false} \
  ] $dma_weight


  # Create instance: dma_output, and set properties
  set dma_output [ create_bd_cell -type ip -vlnv xilinx.com:ip:axi_datamover:5.1 dma_output ]
  set_property -dict [list \
    CONFIG.c_addr_width {32} \
    CONFIG.c_dummy {0} \
    CONFIG.c_enable_mm2s {0} \
    CONFIG.c_enable_s2mm {1} \
    CONFIG.c_enable_s2mm_adv_sig {1} \
    CONFIG.c_include_s2mm {Full} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_s2mm_btt_used {23} \
    CONFIG.c_s2mm_burst_size {16} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
  ] $dma_output


  # Create instance: gp_halted, and set properties
  set gp_halted [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 gp_halted ]
  set_property CONFIG.NUM_PORTS {2} $gp_halted


  # Create instance: hp_halted, and set properties
  set hp_halted [ create_bd_cell -type ip -vlnv xilinx.com:ip:xlconcat:2.1 hp_halted ]
  set_property CONFIG.NUM_PORTS {3} $hp_halted


  # Create interface connections
  connect_bd_intf_net -intf_net axi_control_M00_AXI [get_bd_intf_pins axi_control/M00_AXI] [get_bd_intf_pins cnn/S_AXI]
  connect_bd_intf_net -intf_net axi_feature_M00_AXI [get_bd_intf_pins axi_feature/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP0]
  connect_bd_intf_net -intf_net axi_gp_M00_AXI [get_bd_intf_pins axi_gp/M00_AXI] [get_bd_intf_pins ps7/S_AXI_GP0]
  connect_bd_intf_net -intf_net axi_output_M00_AXI [get_bd_intf_pins axi_output/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP2]
  connect_bd_intf_net -intf_net axi_weight_M00_AXI [get_bd_intf_pins axi_weight/M00_AXI] [get_bd_intf_pins ps7/S_AXI_HP1]
  connect_bd_intf_net -intf_net cnn_FEATURE_CMD [get_bd_intf_pins cnn/FEATURE_CMD] [get_bd_intf_pins dma_feature/S_AXIS_MM2S_CMD]
  connect_bd_intf_net -intf_net cnn_GP_READ_CMD [get_bd_intf_pins cnn/GP_READ_CMD] [get_bd_intf_pins dma_gp/S_AXIS_MM2S_CMD]
  connect_bd_intf_net -intf_net cnn_GP_WRITE_CMD [get_bd_intf_pins cnn/GP_WRITE_CMD] [get_bd_intf_pins dma_gp/S_AXIS_S2MM_CMD]
  connect_bd_intf_net -intf_net cnn_GP_WRITE_DATA [get_bd_intf_pins cnn/GP_WRITE_DATA] [get_bd_intf_pins dma_gp/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net cnn_OUTPUT_CMD [get_bd_intf_pins cnn/OUTPUT_CMD] [get_bd_intf_pins dma_output/S_AXIS_S2MM_CMD]
  connect_bd_intf_net -intf_net cnn_OUTPUT_DATA [get_bd_intf_pins cnn/OUTPUT_DATA] [get_bd_intf_pins dma_output/S_AXIS_S2MM]
  connect_bd_intf_net -intf_net cnn_WEIGHT_CMD [get_bd_intf_pins cnn/WEIGHT_CMD] [get_bd_intf_pins dma_weight/S_AXIS_MM2S_CMD]
  connect_bd_intf_net -intf_net dma_feature_M_AXIS_MM2S [get_bd_intf_pins cnn/FEATURE_DATA] [get_bd_intf_pins dma_feature/M_AXIS_MM2S]
  connect_bd_intf_net -intf_net dma_feature_M_AXIS_MM2S_STS [get_bd_intf_pins cnn/FEATURE_STATUS] [get_bd_intf_pins dma_feature/M_AXIS_MM2S_STS]
  connect_bd_intf_net -intf_net dma_feature_M_AXI_MM2S [get_bd_intf_pins dma_feature/M_AXI_MM2S] [get_bd_intf_pins axi_feature/S00_AXI]
  connect_bd_intf_net -intf_net dma_gp_M_AXIS_MM2S [get_bd_intf_pins cnn/GP_READ_DATA] [get_bd_intf_pins dma_gp/M_AXIS_MM2S]
  connect_bd_intf_net -intf_net dma_gp_M_AXIS_MM2S_STS [get_bd_intf_pins cnn/GP_READ_STATUS] [get_bd_intf_pins dma_gp/M_AXIS_MM2S_STS]
  connect_bd_intf_net -intf_net dma_gp_M_AXIS_S2MM_STS [get_bd_intf_pins cnn/GP_WRITE_STATUS] [get_bd_intf_pins dma_gp/M_AXIS_S2MM_STS]
  connect_bd_intf_net -intf_net dma_gp_M_AXI_MM2S [get_bd_intf_pins dma_gp/M_AXI_MM2S] [get_bd_intf_pins axi_gp/S00_AXI]
  connect_bd_intf_net -intf_net dma_gp_M_AXI_S2MM [get_bd_intf_pins dma_gp/M_AXI_S2MM] [get_bd_intf_pins axi_gp/S01_AXI]
  connect_bd_intf_net -intf_net dma_output_M_AXIS_S2MM_STS [get_bd_intf_pins cnn/OUTPUT_STATUS] [get_bd_intf_pins dma_output/M_AXIS_S2MM_STS]
  connect_bd_intf_net -intf_net dma_output_M_AXI_S2MM [get_bd_intf_pins dma_output/M_AXI_S2MM] [get_bd_intf_pins axi_output/S00_AXI]
  connect_bd_intf_net -intf_net dma_weight_M_AXIS_MM2S [get_bd_intf_pins cnn/WEIGHT_DATA] [get_bd_intf_pins dma_weight/M_AXIS_MM2S]
  connect_bd_intf_net -intf_net dma_weight_M_AXIS_MM2S_STS [get_bd_intf_pins cnn/WEIGHT_STATUS] [get_bd_intf_pins dma_weight/M_AXIS_MM2S_STS]
  connect_bd_intf_net -intf_net dma_weight_M_AXI_MM2S [get_bd_intf_pins dma_weight/M_AXI_MM2S] [get_bd_intf_pins axi_weight/S00_AXI]
  connect_bd_intf_net -intf_net ps7_DDR [get_bd_intf_ports DDR_0] [get_bd_intf_pins ps7/DDR]
  connect_bd_intf_net -intf_net ps7_FIXED_IO [get_bd_intf_ports FIXED_IO_0] [get_bd_intf_pins ps7/FIXED_IO]
  connect_bd_intf_net -intf_net ps7_M_AXI_GP0 [get_bd_intf_pins ps7/M_AXI_GP0] [get_bd_intf_pins axi_control/S00_AXI]

  # Create port connections
  connect_bd_net -net cnn_o_gp_dma_rstn  [get_bd_pins cnn/o_gp_dma_rstn] \
  [get_bd_pins dma_gp/m_axi_mm2s_aresetn] \
  [get_bd_pins dma_gp/m_axis_mm2s_cmdsts_aresetn] \
  [get_bd_pins dma_gp/m_axi_s2mm_aresetn] \
  [get_bd_pins dma_gp/m_axis_s2mm_cmdsts_aresetn]
  connect_bd_net -net cnn_o_gp_halt  [get_bd_pins cnn/o_gp_halt] \
  [get_bd_pins dma_gp/mm2s_halt] \
  [get_bd_pins dma_gp/s2mm_halt]
  connect_bd_net -net cnn_o_hp_dma_rstn  [get_bd_pins cnn/o_hp_dma_rstn] \
  [get_bd_pins dma_feature/m_axi_mm2s_aresetn] \
  [get_bd_pins dma_feature/m_axis_mm2s_cmdsts_aresetn] \
  [get_bd_pins dma_weight/m_axi_mm2s_aresetn] \
  [get_bd_pins dma_weight/m_axis_mm2s_cmdsts_aresetn] \
  [get_bd_pins dma_output/m_axi_s2mm_aresetn] \
  [get_bd_pins dma_output/m_axis_s2mm_cmdsts_aresetn]
  connect_bd_net -net cnn_o_hp_halt  [get_bd_pins cnn/o_hp_halt] \
  [get_bd_pins dma_feature/mm2s_halt] \
  [get_bd_pins dma_weight/mm2s_halt] \
  [get_bd_pins dma_output/s2mm_halt]
  connect_bd_net -net dma_feature_mm2s_halt_cmplt  [get_bd_pins dma_feature/mm2s_halt_cmplt] \
  [get_bd_pins hp_halted/In0]
  connect_bd_net -net dma_gp_mm2s_halt_cmplt  [get_bd_pins dma_gp/mm2s_halt_cmplt] \
  [get_bd_pins gp_halted/In0]
  connect_bd_net -net dma_gp_s2mm_halt_cmplt  [get_bd_pins dma_gp/s2mm_halt_cmplt] \
  [get_bd_pins gp_halted/In1]
  connect_bd_net -net dma_output_s2mm_halt_cmplt  [get_bd_pins dma_output/s2mm_halt_cmplt] \
  [get_bd_pins hp_halted/In2]
  connect_bd_net -net dma_weight_mm2s_halt_cmplt  [get_bd_pins dma_weight/mm2s_halt_cmplt] \
  [get_bd_pins hp_halted/In1]
  connect_bd_net -net gp_halted_dout  [get_bd_pins gp_halted/dout] \
  [get_bd_pins cnn/i_gp_halted]
  connect_bd_net -net hp_halted_dout  [get_bd_pins hp_halted/dout] \
  [get_bd_pins cnn/i_hp_halted]
  connect_bd_net -net one_dout  [get_bd_pins one/dout] \
  [get_bd_pins reset_fclk0/dcm_locked] \
  [get_bd_pins cnn/i_ce] \
  [get_bd_pins dma_gp/mm2s_allow_addr_req] \
  [get_bd_pins dma_gp/s2mm_allow_addr_req] \
  [get_bd_pins dma_feature/mm2s_allow_addr_req] \
  [get_bd_pins dma_weight/mm2s_allow_addr_req] \
  [get_bd_pins dma_output/s2mm_allow_addr_req]
  connect_bd_net -net ps7_FCLK_CLK0  [get_bd_pins ps7/FCLK_CLK0] \
  [get_bd_pins axi_control/ACLK] \
  [get_bd_pins axi_control/M00_ACLK] \
  [get_bd_pins axi_control/S00_ACLK] \
  [get_bd_pins ps7/M_AXI_GP0_ACLK] \
  [get_bd_pins axi_gp/ACLK] \
  [get_bd_pins axi_gp/M00_ACLK] \
  [get_bd_pins axi_gp/S00_ACLK] \
  [get_bd_pins axi_gp/S01_ACLK] \
  [get_bd_pins ps7/S_AXI_GP0_ACLK] \
  [get_bd_pins axi_feature/ACLK] \
  [get_bd_pins axi_feature/M00_ACLK] \
  [get_bd_pins axi_feature/S00_ACLK] \
  [get_bd_pins ps7/S_AXI_HP0_ACLK] \
  [get_bd_pins axi_weight/ACLK] \
  [get_bd_pins axi_weight/M00_ACLK] \
  [get_bd_pins axi_weight/S00_ACLK] \
  [get_bd_pins ps7/S_AXI_HP1_ACLK] \
  [get_bd_pins axi_output/ACLK] \
  [get_bd_pins axi_output/M00_ACLK] \
  [get_bd_pins axi_output/S00_ACLK] \
  [get_bd_pins ps7/S_AXI_HP2_ACLK] \
  [get_bd_pins cnn/i_clk] \
  [get_bd_pins reset_fclk0/slowest_sync_clk] \
  [get_bd_pins dma_gp/m_axi_mm2s_aclk] \
  [get_bd_pins dma_gp/m_axis_mm2s_cmdsts_aclk] \
  [get_bd_pins dma_gp/m_axi_s2mm_aclk] \
  [get_bd_pins dma_gp/m_axis_s2mm_cmdsts_awclk] \
  [get_bd_pins dma_feature/m_axi_mm2s_aclk] \
  [get_bd_pins dma_feature/m_axis_mm2s_cmdsts_aclk] \
  [get_bd_pins dma_weight/m_axi_mm2s_aclk] \
  [get_bd_pins dma_weight/m_axis_mm2s_cmdsts_aclk] \
  [get_bd_pins dma_output/m_axi_s2mm_aclk] \
  [get_bd_pins dma_output/m_axis_s2mm_cmdsts_awclk]
  connect_bd_net -net ps7_FCLK_RESET0_N  [get_bd_pins ps7/FCLK_RESET0_N] \
  [get_bd_pins reset_fclk0/ext_reset_in]
  connect_bd_net -net reset_fclk0_interconnect_aresetn  [get_bd_pins reset_fclk0/interconnect_aresetn] \
  [get_bd_pins axi_control/ARESETN] \
  [get_bd_pins axi_gp/ARESETN] \
  [get_bd_pins axi_feature/ARESETN] \
  [get_bd_pins axi_weight/ARESETN] \
  [get_bd_pins axi_output/ARESETN]
  connect_bd_net -net reset_fclk0_peripheral_aresetn  [get_bd_pins reset_fclk0/peripheral_aresetn] \
  [get_bd_pins cnn/i_rstn] \
  [get_bd_pins axi_control/M00_ARESETN] \
  [get_bd_pins axi_control/S00_ARESETN] \
  [get_bd_pins axi_gp/M00_ARESETN] \
  [get_bd_pins axi_gp/S00_ARESETN] \
  [get_bd_pins axi_gp/S01_ARESETN] \
  [get_bd_pins axi_feature/M00_ARESETN] \
  [get_bd_pins axi_feature/S00_ARESETN] \
  [get_bd_pins axi_weight/M00_ARESETN] \
  [get_bd_pins axi_weight/S00_ARESETN] \
  [get_bd_pins axi_output/M00_ARESETN] \
  [get_bd_pins axi_output/S00_ARESETN]
  connect_bd_net -net zero_dout  [get_bd_pins zero/dout] \
  [get_bd_pins reset_fclk0/aux_reset_in] \
  [get_bd_pins reset_fclk0/mb_debug_sys_rst]

  # Create address segments
  assign_bd_address -offset 0x43C00000 -range 0x00001000 -target_address_space [get_bd_addr_spaces ps7/Data] [get_bd_addr_segs cnn/S_AXI/Reg] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_gp/Data_MM2S] [get_bd_addr_segs ps7/S_AXI_GP0/GP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_gp/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_GP0/GP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_feature/Data_MM2S] [get_bd_addr_segs ps7/S_AXI_HP0/HP0_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_weight/Data_MM2S] [get_bd_addr_segs ps7/S_AXI_HP1/HP1_DDR_LOWOCM] -force
  assign_bd_address -offset 0x00000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_output/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_HP2/HP2_DDR_LOWOCM] -force

  # Exclude Address Segments
  exclude_bd_addr_seg -offset 0xE0000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces dma_gp/Data_MM2S] [get_bd_addr_segs ps7/S_AXI_GP0/GP0_IOP]
  exclude_bd_addr_seg -offset 0x40000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_gp/Data_MM2S] [get_bd_addr_segs ps7/S_AXI_GP0/GP0_M_AXI_GP0]
  exclude_bd_addr_seg -offset 0xE0000000 -range 0x00400000 -target_address_space [get_bd_addr_spaces dma_gp/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_GP0/GP0_IOP]
  exclude_bd_addr_seg -offset 0x40000000 -range 0x40000000 -target_address_space [get_bd_addr_spaces dma_gp/Data_S2MM] [get_bd_addr_segs ps7/S_AXI_GP0/GP0_M_AXI_GP0]


  # Restore current instance
  current_bd_instance $oldCurInst

  validate_bd_design
  save_bd_design
}
# End of create_root_design()


##################################################################
# MAIN FLOW
##################################################################

create_root_design ""


