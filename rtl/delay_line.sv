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
 * Delay Line
 * Knowing the image dimensions, we don't need to
 * buffer the row and column alongside the pixel data and
 * instead can figure it out using the PIPE_ROW, PIPE_COL offsets
 * in conjunction with total DELAY cycles.
 * 
 * Considering row and column wires are 32 bits, this saves a lot of space.
 */

module delay_line #(
    parameter WIDTH = 100,
    parameter HEIGHT = 100,
    parameter DELAY = 200,
    parameter CLKS_PER_PIXEL = 1
) (
    input rst_n_i,
    pixel_data_interface.writer in,
    pixel_data_interface.reader out
);
    localparam DSIZE = in.FP_M + in.FP_N + in.FP_S;
    localparam ASIZE = $clog2(DELAY) + 1;

    logic [15:0] delay_row [CLKS_PER_PIXEL];
    logic [15:0] delay_col [CLKS_PER_PIXEL];

    logic [15:0] delay_row_next;
    logic [15:0] delay_col_next;

    logic valid_out      [CLKS_PER_PIXEL];
    logic valid_out_next;

    logic [in.FP_M + in.FP_N + in.FP_S-1:0] pixel_out      [CLKS_PER_PIXEL];
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] pixel_out_next;

    logic valid_d;
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] pixel_d;
    logic [15:0] row_d;
    logic [15:0] col_d;

    logic [$clog2(DELAY):0] pointer_separation;
    logic [$clog2(DELAY):0] pointer_separation_next;

    // write
    logic               r_wrst_n      ;
    logic               r_wrst_n_next ;
    logic               r_wr          ;
    logic [(DSIZE-1):0] w_wdata       ;
    logic               w_wfull       ;
    
    // read
    logic               r_rrst_n      ;
    logic               r_rrst_n_next ;
    logic               r_rd          ;
    logic [(DSIZE-1):0] w_rdata       ;
    logic               w_rempty      ;

    async_fifo #(
        .DSIZE(DSIZE),
        .ASIZE(ASIZE),
        .FALLTHROUGH("FALSE")
    ) delay_buffer (
        .wclk(in.clk), 
        .wrst_n(r_wrst_n),
        .winc(r_wr), 
        .wdata(w_wdata),
        .wfull(w_wfull), 
        .awfull(),

        .rclk(in.clk), 
        .rrst_n(r_rrst_n),
        .rinc(r_rd), 
        .rdata(w_rdata),
        .rempty(w_rempty), 
        .arempty()
    );

    assign w_wdata = in.pixel;
    assign out.pixel = pixel_out[CLKS_PER_PIXEL-1];
    assign out.valid = valid_out[CLKS_PER_PIXEL-1];
    assign out.row   = delay_row[CLKS_PER_PIXEL-1];
    assign out.col   = delay_col[CLKS_PER_PIXEL-1];

    assign pixel_d = out.pixel;
    assign valid_d = out.valid;
    assign row_d   = out.row;
    assign col_d   = out.col;
    
    always_comb begin 
        pixel_out_next = w_rdata;
        valid_out_next = 0;
        ////////////////////////////////////////////////////////////////
        // Row Buffer State Control, includes pointer separation

        // logic is,
        // if dv, we can always write
        // if dv, we can only read if pointers are separated by DELAY
        // if not dv, cant read nor write
        pointer_separation_next = pointer_separation;
        r_rd = 0;
        r_wr = 0;

        if(in.valid) begin
            r_wr = 1;

            if(pointer_separation == (DELAY - 1)) begin
                r_rd = 1;
            end
            else begin
                pointer_separation_next = pointer_separation + 1;
                r_rd = 0;
            end
        end
        valid_out_next = r_rd; 

        // delay row/col logic
        delay_row_next = delay_row[0];
        delay_col_next = delay_col[0];

        if(r_rd == 1) begin
            delay_col_next = delay_col[0] + 1;
            if(delay_col[0] == (WIDTH - 1)) begin
                delay_col_next = 0;
                delay_row_next = delay_row[0] + 1;
                if(delay_row[0] == (HEIGHT - 1)) begin
                    delay_row_next = 0;
                end 
            end 
        end

        // reset logic
        if(!rst_n_i) begin
            valid_out_next = 0;
            pixel_out_next = 0;
            delay_row_next = (HEIGHT - 1);
            delay_col_next = (WIDTH - 1);
            r_rrst_n_next = 0;
            r_wrst_n_next = 0;
            pointer_separation_next = 0;
        end else begin
            r_rrst_n_next = 1;
            r_wrst_n_next = 1;
        end
    end

    always@(posedge in.clk) begin
        valid_out[0] <= valid_out_next;
        pixel_out[0] <= pixel_out_next;
        delay_row[0] <= delay_row_next;
        delay_col[0] <= delay_col_next;

        for(int i = 1; i < CLKS_PER_PIXEL; i += 1) begin
            valid_out[i] <= valid_out[i-1];
            pixel_out[i] <= pixel_out[i-1];
            delay_row[i] <= delay_row[i-1];
            delay_col[i] <= delay_col[i-1];
        end

        // Row Buffer Reset update, most logic is purely combinational
        r_rrst_n <= r_rrst_n_next;
        r_wrst_n <= r_wrst_n_next;

        pointer_separation <= pointer_separation_next;

        
    end

endmodule