export bindir="/usr/local/diamond/3.13/bin/lin64"
source /usr/local/diamond/3.13/bin/lin64/diamond_env

rm -rf simulate
mkdir simulate
cd simulate
vlib work

# Directories
TB_DIR="../../../testbench"
RTL_DIR="../../../rtl"
TP_DIR="../../../third-party"

# Include directory flags
INCLUDE_FLAGS="-incdir "$RTL_DIR" -incdir "$TB_DIR" -incdir "$TB_DIR"/util -incdir "$TP_DIR""

# Run vlog on all source files.
error_highlighter() {
    grep --color -e ".*Errors: [1-9].*" -e "^"
}

vlog $INCLUDE_FLAGS -sv $TB_DIR/util/triggerable_queue_pkg.sv | error_highlighter
vlog $INCLUDE_FLAGS -sv $TB_DIR/util/testbench_common_pkg.sv | error_highlighter
vlog $INCLUDE_FLAGS -sv $TB_DIR/util/testbench_util_pkg.sv | error_highlighter
vlog $INCLUDE_FLAGS -sv $TB_DIR/util/camera_simulation_pkg.sv | error_highlighter
vlog $INCLUDE_FLAGS -sv $TB_DIR/util/pixel_data_interface_utils_pkg.sv | error_highlighter
vlog $INCLUDE_FLAGS -sv $TB_DIR/util/golden_models_pkg.sv | error_highlighter

vlog $INCLUDE_FLAGS -sv ../divisor_tb.sv | error_highlighter

# -c argument gets name of testbench module.
vsim -c divisor_tb -do "run -all; quit" | error_highlighter

export bindir=""

