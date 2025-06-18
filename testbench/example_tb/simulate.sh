export bindir="/usr/local/diamond/3.13/bin/lin64"
source /usr/local/diamond/3.13/bin/lin64/diamond_env

rm -rf simulate
mkdir simulate
cd simulate
vlib work

# run vlog on all source files.
# note that the current directory is tb_dir/simulate
vlog -sv ../../util/triggerable_queue_pkg.sv
vlog -sv ../example_tb.sv

# -c argument gets name of testbench module.
vsim -c example_tb -do "run -all; quit"

export bindir=""