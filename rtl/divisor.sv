/*
MIT License

Copyright (c) 2025 Marcos Ferreira

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/*
 * Pipelined divisor module that performs
 * A / B (where A is the dividend and B is
 * the divisor).  By default the pipe length 
 * is 'Q_LENGTH' (width ofA)
 * 
 *
 * The result is a signed number of Q_LENGTH + 1 bit width at q_o,
 * signed remainder of B_WIDTH + 1 bith width at r_o and valid out.
 *
 */

module divisor #(
    // width of Dividend
    parameter A_WIDTH = 16,
    // width of Divisor
    parameter B_WIDTH = 16,
    // width of Result (default A_WIDTH)
    parameter Q_LENGTH = 0,
    // cycles per pixel
    parameter CLKS_PER_PIXEL = 1
) (
    // Dividend
    pixel_data_interface.writer in_a,
    // Divisor
    pixel_data_interface.writer in_b,
    input rst_n_i,
    // Result
    pixel_data_interface.reader out,

    // (optional) remainder
    output reg [B_WIDTH:0] r_o
);
    localparam Q_INDEX = Q_LENGTH - 1;
    localparam NO_PARTS = (Q_LENGTH % CLKS_PER_PIXEL) == 0 ? 
                            (Q_LENGTH / CLKS_PER_PIXEL) : (Q_LENGTH / CLKS_PER_PIXEL) + 1;  
    localparam LOGICAL_PIPE_LENGTH = Q_LENGTH;
    localparam READY = (CLKS_PER_PIXEL - 1);

    logic [A_WIDTH-1:0] a;
    logic               a_signed;
    logic [B_WIDTH-1:0] b;
    logic               b_signed;
    logic               valid;
    logic [15:0]        row;
    logic [15:0]        col;

    logic [A_WIDTH-1:0]         a_start;
    logic [B_WIDTH:0]           b_start;
    logic [Q_LENGTH:0]          q_start;
    
    // intermediary results start
    logic [B_WIDTH:0] inter_start;

    // are inputs valid.
    logic valid_start;

    // row/col
    logic [15:0] row_start;
    logic [15:0] col_start;

    // what is the result sign suppose to be?
    logic sign_start;

    logic [A_WIDTH-1:0]         a_start_next;
    logic [B_WIDTH:0]           b_start_next;
    logic [Q_LENGTH:0]          q_start_next;

    logic [B_WIDTH:0] inter_start_next;

    logic valid_start_next;

    logic sign_start_next;

    logic [15:0] row_start_next;
    logic [15:0] col_start_next;

    // wiring for division parts
    logic [A_WIDTH-1:0] a_w     [NO_PARTS];
    logic [B_WIDTH:0]   b_w     [NO_PARTS];
    logic [Q_LENGTH:0]  q_w     [NO_PARTS];
    logic [B_WIDTH:0]   inter_w [NO_PARTS];
    logic               valid_w [NO_PARTS];
    logic               sign_w  [NO_PARTS];
    logic [15:0]        row_w   [NO_PARTS];
    logic [15:0]        col_w   [NO_PARTS];

    // wiring for intermediate result
    logic [Q_LENGTH:0] q_0;

    logic [Q_LENGTH:0] out_d;
    logic [Q_LENGTH:0] q_w_d;
    logic valid_d;
    assign valid_d = out.valid;
    assign q_w_d =  q_w[NO_PARTS-1];
    assign out_d = out.pixel;


    always_comb begin
        ////////////////////////////////////////////////////////////////
        // entry to division pipeline, setting start values
        a_start_next = a;
        b_start_next = {{1'b0},b};
        valid_start_next = valid;
        row_start_next = row;
        col_start_next = col;

        // determine sign of final result
        sign_start_next = (a_signed & a[A_WIDTH-1]) ^ (b_signed & b[B_WIDTH-1]);
        
        // set first q result (none since we need everything else first)
        q_start_next = 0;

        // determine signedness to convert to unsigned format
        if(a_signed) begin
            if(a[A_WIDTH-1]) begin
                a_start_next = ~a + 1;
            end
        end 

        // set initial intermediate result
        // must happen after a_start_next determined (due to potential sign conversion)
        inter_start_next = {{B_WIDTH{1'b0}},a_start_next[A_WIDTH-1]};

        // a_start_next, shift left, first bit consumed and placed in inter_start above.
        // *order matters
        a_start_next = {a_start_next[A_WIDTH-2:0],1'b0};

        if(b_signed) begin
            if(b[B_WIDTH-1]) begin
                // don't do '{{1'b0},(~b + 1)}'
                b_start_next = ~b + 1;
                b_start_next[B_WIDTH] = 0;
            end
        end

        ////////////////////////////////////////////////////////////////
        // exit: conversion to signed format with result sign
        out.pixel = q_w[NO_PARTS-1];
        r_o = {{1'b0},inter_w[NO_PARTS-1][B_WIDTH:1]};
        out.valid = valid_w[NO_PARTS-1];
        if(sign_w[NO_PARTS-1] == 1) begin
            out.pixel = ~q_w[NO_PARTS-1] + 1;;
            r_o = ~{{1'b0},inter_w[NO_PARTS-1][B_WIDTH:1]} + 1;
        end
        out.row = row_w[NO_PARTS-1];
        out.col = col_w[NO_PARTS-1];

    end

    ////////////////////////////////////////////////////////////////
    // Division pipeline, consisting of divisor_parts

    // genvars
    genvar i, k;
    

    generate
        // first part 
        divisor_part #(
            .A_WIDTH(A_WIDTH),
            .B_WIDTH(B_WIDTH),
            .Q_LENGTH(Q_LENGTH),
            .Q_SPACE(LOGICAL_PIPE_LENGTH - 0 - 1),
            .CLKS_PER_PIXEL(CLKS_PER_PIXEL)
        ) div_part (
            .clk_i(in_a.clk),
            .rst_n_i(rst_n_i),
            .a_i(a_start),
            .b_i(b_start),
            .inter_i(inter_start),
            .q_i(q_start),
            .sign_i(sign_start),
            .valid_i(valid_start),
            .row_i(row_start),
            .col_i(col_start),

            .a_o(a_w[0]),
            .b_o(b_w[0]),
            .inter_o(inter_w[0]),
            .q_o(q_w[0]),
            .sign_o(sign_w[0]),
            .valid_o(valid_w[0]),
            .row_o(row_w[0]),
            .col_o(col_w[0])
        );

        // rest of parts
        
        for(i = CLKS_PER_PIXEL; i < LOGICAL_PIPE_LENGTH; i = i + CLKS_PER_PIXEL) begin
            divisor_part #(
                .A_WIDTH(A_WIDTH),
                .B_WIDTH(B_WIDTH),
                .Q_LENGTH(Q_LENGTH),
                .Q_SPACE(LOGICAL_PIPE_LENGTH - i - 1),
                .CLKS_PER_PIXEL(CLKS_PER_PIXEL)
            ) div_part (
                .clk_i(in_a.clk),
                .rst_n_i(rst_n_i),
                .a_i(a_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .b_i(b_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .inter_i(inter_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .q_i(q_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .sign_i(sign_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .valid_i(valid_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .row_i(row_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),
                .col_i(col_w[(i - CLKS_PER_PIXEL)/CLKS_PER_PIXEL]),

                .a_o(a_w[i/CLKS_PER_PIXEL]),
                .b_o(b_w[i/CLKS_PER_PIXEL]),
                .inter_o(inter_w[i/CLKS_PER_PIXEL]),
                .q_o(q_w[i/CLKS_PER_PIXEL]),
                .sign_o(sign_w[i/CLKS_PER_PIXEL]),
                .valid_o(valid_w[i/CLKS_PER_PIXEL]),
                .row_o(row_w[i/CLKS_PER_PIXEL]),
                .col_o(col_w[i/CLKS_PER_PIXEL])
            );
        end
        
    endgenerate


    always@(posedge in_a.clk) begin
        a        <= in_a.pixel;
        a_signed <= in_a.FP_S[0];
        b        <= in_b.pixel;
        b_signed <= in_b.FP_S[0];
        valid    <= in_a.valid & in_b.valid;
        if(!rst_n_i) begin
            valid <= 0;
        end
        // assumed that in_a and in_b row/cols match
        row      <= in_a.row;
        col      <= in_a.col;

        a_start     <= a_start_next;
        b_start     <= b_start_next;
        inter_start <= inter_start_next;
        q_start     <= q_start_next;
        valid_start <= valid_start_next;
        sign_start  <= sign_start_next;
        row_start   <= row_start_next;
        col_start   <= col_start_next;
    end

endmodule

module divisor_part #(
    // width of Dividend
    parameter A_WIDTH = 16,
    // width of Divisor
    parameter B_WIDTH = 16,
    // width of Result (default A_WIDTH)
    parameter Q_LENGTH = 0,
    // cycles per pixel
    parameter CLKS_PER_PIXEL = 1,
    // used to check Q in bounds.
    parameter Q_SPACE = 0
) (
    input clk_i,
    input rst_n_i,
    input [A_WIDTH-1:0] a_i,
    input [B_WIDTH:0]   b_i,
    input [B_WIDTH:0]   inter_i,
    input [Q_LENGTH:0]  q_i,
    input sign_i,
    input valid_i,
    input [15:0] row_i,
    input [15:0] col_i,

    output reg [A_WIDTH-1:0] a_o,
    output reg [B_WIDTH:0]   b_o,
    output reg [B_WIDTH:0]   inter_o,
    output reg [Q_LENGTH:0]  q_o,
    output reg sign_o,
    output reg valid_o,
    output reg [15:0] row_o,
    output reg [15:0] col_o
);
    localparam READY = (CLKS_PER_PIXEL - 1);
    
    // This state is only used when CLKS_PER_PIXEL > 1
    logic [A_WIDTH-1:0] a;
    logic [B_WIDTH:0]   b;
    logic [B_WIDTH:0]   inter;
    logic [Q_LENGTH:0]  q;
    logic sign;
    logic valid;
    logic [15:0] row;
    logic [15:0] col;

    logic [A_WIDTH-1:0] a_next;
    logic [B_WIDTH:0]   b_next;
    logic [B_WIDTH:0]   inter_next;
    logic [Q_LENGTH:0]  q_next;
    logic sign_next;
    logic valid_next;
    logic [15:0] row_next;
    logic [15:0] col_next;

    logic [$clog2(CLKS_PER_PIXEL)-1:0] state;
    logic [$clog2(CLKS_PER_PIXEL)-1:0] state_next;

    always_comb begin

        ////////////////////////////////////////////////////////////////
        // state logic
        state_next = state;
        // ready wait state
        if(state == READY) begin
            if(valid_i == 1) begin
                state_next = 0;
            end 
        // processing
        end else begin
            state_next = state + 1;
        end

        if(!rst_n_i) begin
            state_next = READY;
        end
        
        ////////////////////////////////////////////////////////////////
        // division logic entry
        a_next = a;
        b_next = b;
        inter_next = inter;
        q_next = q;
        sign_next = sign;
        valid_next = valid;
        row_next = row;
        col_next = col;

        // to prevent wrong repeating valids
        if(CLKS_PER_PIXEL > 1) begin
            if((state == READY) && (valid == 1)) begin
                valid_next = 0;
            end
        end
        
        ////////////////////////////////////////////////////////////////
        // division logic main

        // work on inputs (first cycle)
        if(state == READY) begin
            // a_next shift
            a_next = {a_i[A_WIDTH-2:0],1'b0};
            b_next = b_i;
            // q_next shift
            q_next = {q_i[Q_LENGTH-1:0],1'b0};
            valid_next = valid_i;
            sign_next = sign_i;

            // default to no subtract
            inter_next = {inter_i[B_WIDTH-1:0],a_i[A_WIDTH-1]};

            // if intermediate result is >= then divisor, set 1
            // at q_bit position and subtract, store result in next inter and shift in new value.
            if(inter_i >= b_i) begin
                q_next[0] = 1;
                inter_next = inter_i - b_i;
                inter_next = {inter_next[B_WIDTH-1:0],a_i[A_WIDTH-1]};
            end

            // passing along row and col
            row_next = row_i;
            col_next = col_i;

        // cases when pipe is longer then Q length (i.e 7 / 3 not easily divisible)
        // just maintain values.
        end else if((state >= Q_SPACE) && (state != READY)) begin
            a_next = a;
            b_next = b;
            q_next = q;
            inter_next = inter;
            valid_next = valid;
            sign_next = sign;
            row_next = row;
            col_next = col;
        // next cycles work on same state (saving resources)
        end else begin
            a_next = {a[A_WIDTH-2:0], 1'b0};
            b_next = b;
            q_next = {q[Q_LENGTH-1:0],1'b0};
            valid_next = valid;
            sign_next = sign;

            inter_next = {inter[B_WIDTH-1:0],a[A_WIDTH-1]};

            if(inter >= b) begin
                q_next[0] = 1;
                inter_next = inter - b;
                inter_next = {inter_next[B_WIDTH-1:0],a[A_WIDTH-1]};
            end

            row_next = row;
            col_next = col;
        end

        

        ////////////////////////////////////////////////////////////////
        // division exit assign
        a_o = a;
        b_o = b;
        q_o = q;
        inter_o = inter;
        valid_o = (state == READY) && (valid == 1) ? 1 : 0;
        sign_o = sign;
        row_o = row;
        col_o = col;

    end

    always@(posedge clk_i) begin
        a     <= a_next;
        b     <= b_next;
        q     <= q_next;
        inter <= inter_next;
        valid <= valid_next;
        sign  <= sign_next;
        row   <= row_next;
        col   <= col_next;

        state <= state_next;
    end


endmodule