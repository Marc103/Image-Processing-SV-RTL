`timescale 1ns/10ps

/**
 * Divisor TB
 */

////////////////////////////////////////////////////////////////
// imports
import testbench_common_pkg::*;
import testbench_util_pkg::*;
import triggerable_queue_pkg::*;
import camera_simulation_pkg::*;
import pixel_data_interface_utils_pkg::*;
import golden_models_pkg::*;
`include "testbench_util_pkg.svh"

////////////////////////////////////////////////////////////////
// includes 
`include "divisor.sv"

module divisor_tb;
    ////////////////////////////////////////////////////////////////
    // shared localparams
    localparam real PERIOD = 5;

    localparam FP_M = 15;
    localparam FP_N = 0;
    localparam FP_S = 1;

    localparam FP_M_OUT = FP_M + FP_N + FP_S;
    // Model does not work for FP_N_OUT > 0
    localparam FP_N_OUT = 1;
    // result will always be signed
    localparam FP_S_OUT = 1;

    localparam A_WIDTH = FP_M + FP_N + FP_S;
    localparam B_WIDTH = FP_M + FP_N + FP_S;
    localparam Q_LENGTH = FP_M_OUT + FP_N_OUT + FP_S_OUT - 1;

    // number of tests
    localparam N = 30;

    // clks per pixel
    localparam CLKS_PER_PIXEL = 1;

    // inter pixel, must be >= CLKS_PER_PIXEL
    localparam INTER_PIXEL = 11;

    ////////////////////////////////////////////////////////////////
    // clock generation
    logic pixclk = 0;
    always begin #(PERIOD/2); pixclk = ~pixclk; end

    ////////////////////////////////////////////////////////////////
    // interface instantiation and connection
    // we need some logic connected to interfaces so that vcd file captures them for gtkwave.

    pixel_data_interface #(
        .FP_M(FP_M),
        .FP_N(FP_N),
        .FP_S(FP_S)
    ) pixel_data_to_dut_iface_a(pixclk);

    pixel_data_interface #(
        .FP_M(FP_M),
        .FP_N(FP_N),
        .FP_S(FP_S)
    ) pixel_data_to_dut_iface_b(pixclk);

    pixel_data_interface #(
        .FP_M(FP_M_OUT),
        .FP_N(FP_N_OUT),
        .FP_S(FP_S_OUT)
    ) pixel_data_from_dut_iface(pixclk);

    logic [A_WIDTH-1:0] a = 0;
    logic a_signed = 0;

    logic [B_WIDTH-1:0] b = 0;
    logic b_signed = 0;

    logic valid = 0;

    logic [Q_LENGTH:0] q;
    logic [B_WIDTH:0]  r;

    ////////////////////////////////////////////////////////////////
    // Test related state
    integer i, passed;
    logic [15:0] current_test = 0;
    logic [15:0] recieved_test = 0;

    logic signed [A_WIDTH-1:0] a_tests [N];
    logic a_signed_tests [N];

    logic signed [B_WIDTH-1:0] b_tests [N];
    logic b_signed_tests [N];

    logic valid_tests [N];

    logic signed [Q_LENGTH:0] q_expected [N];
    logic signed [B_WIDTH:0]  r_expected [N];

    logic signed [Q_LENGTH:0] q_result[N];
    logic signed [B_WIDTH:0] r_result[N];

    logic unsigned [A_WIDTH-1+FP_N_OUT:0] a_as_unsigned;
    logic unsigned [B_WIDTH-1:0] b_as_unsigned;

    ////////////////////////////////////////////////////////////////
    // DUT
    divisor #(
        .A_WIDTH(A_WIDTH),
        .B_WIDTH(B_WIDTH),
        .Q_LENGTH(Q_LENGTH),
        .CLKS_PER_PIXEL(CLKS_PER_PIXEL)
    ) dut (
        .in_a(pixel_data_to_dut_iface_a),
        .in_b(pixel_data_to_dut_iface_b),
        .out(pixel_data_from_dut_iface),
        .r_o(r)
    );
    assign pixel_data_to_dut_iface_a.pixel = a;
    assign pixel_data_to_dut_iface_a.valid = valid;
    assign pixel_data_to_dut_iface_a.row = 16'hABCD;
    assign pixel_data_to_dut_iface_a.col = 16'hABCD;

    assign pixel_data_to_dut_iface_b.pixel = b;
    assign pixel_data_to_dut_iface_b.valid = valid;
    assign pixel_data_to_dut_iface_b.row = 16'hABCD;
    assign pixel_data_to_dut_iface_b.col = 16'hABCD;

    clocked_valid_interface dut_requester_interface(pixclk, pixel_data_to_dut_iface_a.valid);
    clocked_valid_interface dut_responder_interface(pixclk, pixel_data_from_dut_iface.valid);

    ////////////////////////////////////////////////////////////////
    // execution entry point

    initial begin
        // setup dumpfiles
        $dumpfile("waves.vcd");
        $dumpvars(0, divisor_tb);

        // setting tests
        for(i = 0; i < N; i++) begin
            a_tests[i] = $urandom;
            a_signed_tests[i] = FP_S;
            b_tests[i] = $urandom;
            b_signed_tests[i] = FP_S;
            valid_tests[i] = 1;
            if(b_tests[i] == 0) begin
                b_tests[i] = 1;
            end
            
        end

        // some edge cases
        
        a_tests[0] = 16'b1111_1111_1111_1111;
        a_signed_tests[0] = FP_S;
        b_tests[0] = 16'b0000_0000_0000_0001;
        b_signed_tests[0] = FP_S;
        valid_tests[0] = 1;

        a_tests[1] = 16'b1111_1111_1111_1111;
        a_signed_tests[1] = FP_S;
        b_tests[1] = 16'b0000_0000_0000_0001;
        b_signed_tests[1] = FP_S;
        valid_tests[1] = 1;

        a_tests[2] = 16'b0000_0000_0000_0001;
        a_signed_tests[2] = FP_S;
        b_tests[2] = 16'b1111_1111_1111_1111;
        b_signed_tests[2] = FP_S;
        valid_tests[2] = 1;

        a_tests[3] = 16'b0000_0000_0000_0000;
        a_signed_tests[3] = FP_S;
        b_tests[3] = 16'b1111_1111_1111_1111;
        b_signed_tests[3] = FP_S;
        valid_tests[3] = 1;
        
        current_test = 0;

        // golden model
        for(i = 0; i < N; i++) begin
            a_as_unsigned = 0;
            a_as_unsigned[A_WIDTH-1:0] = a_tests[i];
            b_as_unsigned = b_tests[i];
            if(a_signed_tests[i] & a_tests[i][A_WIDTH-1]) begin
                a_as_unsigned = ~a_as_unsigned + 1;
            end
            if(b_signed_tests[i] & b_tests[i][B_WIDTH-1]) begin
                b_as_unsigned = ~b_as_unsigned + 1;
            end
            a_as_unsigned = a_as_unsigned << FP_N_OUT;
            q_expected[i] = a_as_unsigned / b_as_unsigned;
            r_expected[i] = a_as_unsigned % b_as_unsigned;
            if((a_signed_tests[i] & a_tests[i][A_WIDTH-1]) ^ (b_signed_tests[i] & b_tests[i][B_WIDTH-1])) begin
                q_expected[i] = ~q_expected[i] + 1;
                r_expected[i] = ~r_expected[i] + 1;
            end
        end
        
        // let driver and monitor run...
        #10000;
        passed = 1;
        // compare
        for(i = 0; i < N; i++) begin
            a_as_unsigned = a_tests[i];
            a_as_unsigned = a_as_unsigned << FP_N_OUT;
            
            b_as_unsigned = b_tests[i];
            if((a_signed_tests[i] == 0) && (b_signed_tests[i] == 0)) begin
                $display("%d / %d expects %d R %d",
                         a_as_unsigned, b_as_unsigned, q_expected[i], r_expected[i]);
            end
            if((a_signed_tests[i] == 0) && (b_signed_tests[i] == 1)) begin
                $display("%d / %d expects %d R %d",
                         a_as_unsigned, b_tests[i], q_expected[i], r_expected[i]);
            end
            if((a_signed_tests[i] == 1) && (b_signed_tests[i] == 0)) begin
                $display("%d / %d expects %d R %d",
                         a_tests[i], b_as_unsigned, q_expected[i], r_expected[i]);
            end
            if((a_signed_tests[i] == 1) && (b_signed_tests[i] == 1)) begin
                $display("%d / %d expects %d R %d",
                         a_tests[i], b_tests[i], q_expected[i], r_expected[i]);
            end

            assert((q_expected[i] == q_result[i]) && (r_expected[i] == r_result[i])) begin
                $display("      passed.");
            end else begin
                $display("        instead recieved %d R %d.",q_result[i], r_result[i]);
                passed = 0;
                //$finish;
            end
        end
        if(passed == 0) begin 
            $display("Divisor test failed,");
            $error("check results."); 
            $finish;
        end
        $display("Divisor test passed.");
        $finish;
    end

    // driver
    always@(posedge pixclk) begin
        a            <= a_tests[current_test];
        a_signed     <= a_signed_tests[current_test];
        b            <= b_tests[current_test];
        b_signed     <= b_signed_tests[current_test];
        valid        <= valid_tests[current_test];
        current_test <= current_test + 1;
        for (int i = 1; i < INTER_PIXEL; i++) begin
            @(posedge pixclk);
            valid <= 0;
        end

    end

    // monitor
    always@(negedge pixclk) begin
        if(pixel_data_from_dut_iface.valid == 1) begin
            q_result[recieved_test] = pixel_data_from_dut_iface.pixel;
            r_result[recieved_test] = r;
            recieved_test++;
        end
    end


endmodule