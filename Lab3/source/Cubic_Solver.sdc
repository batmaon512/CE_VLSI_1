current_design Cubic_Solver

create_clock -name clk -add -period 10.0 -waveform {0.0 5.0} [get_ports {clk}]

set_input_delay -clock [get_clocks clk] -add_delay 2.5 [get_ports {rst_n start FP_a[*] FP_b[*] FP_c[*] FP_d[*]}]
set_output_delay -clock [get_clocks clk] -add_delay 2.5 [get_ports {done FP_x0_re[*] FP_x0_im[*] FP_x1_re[*] FP_x1_im[*] FP_x2_re[*] FP_x2_im[*]}]

set_max_fanout 15.000 [current_design]
set_max_transition 1.2 [current_design]
