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

/* Bilinear Interpolation
 *
 * A stream processing version of Bilinear interpolation without
 * having the need of a full size frame buffer.
 *
 * Three key assumptions
 * 1. Input and output image dimensions are the same
 * 2. The geometric transformations are small enough such that it
 *    can 'play nice' within 'N_LINES' ** 2, buffered
 * 3. FP of in = FP of out, if there are accuracy issues, append 0's to
 *    the right of image pixel and add FP_N.
 *
 * There are some nice optimizations we can make that can reduce the multipliers
 * needed in the read/write address calculations to buffer. For the writes its
 * taking advantage of the fact that we know what order the pixels (should) arrive
 * in and for the read its knowing that adjacent pixels have the same address or the
 * +1 (made easier if we can guarantee WIDTH is even, since we will have the same
 * number of odd and even pixels in a line). But what was that saying? "Premature
 * optimization is the root of all evil"...
 *
 * For now, good enough.
 *
 * Note! In the reverse mapper,
 * The row and col numbers will be treated as 11 bit 
 * signed numbers, so we can dedicate more bits to the matrix values.
 * So in reality we have a -1024 <-> 1023 range.
 *
 *
 */

 module bilinear_xform #(
    // image dimensions
    parameter WIDTH = 320,
    parameter HEIGHT = 240,

    // How lines to buffer in terms of 
    // power of two (.i.e 2 is 2^2 = 4)
    parameter N_LINES_POW2 = 2,

    // Turns out, the optimal condition to decide where
    // the pipe (buffer) is full and output pixels should
    // being driven is entirely dependant on the transformations
    // done for the reverse mapping. So, it too will be parameterized
    parameter PIPE_ROW = 1,
    parameter PIPE_COL = 0,

    // how precisely should the coordinates be transformed
    // (how many bits for decimal place) 
    parameter PRECISION = 8,

    parameter CLKS_PER_PIXEL = 1
 ) (
    pixel_data_interface.writer in,
    pixel_data_interface.reader out,

    // affine transformation matrix
    input signed [11+PRECISION-1:0] matrix_i [3][3],

    // reset signal
    input rst_n_i
 );
    // this impacts address resolution
    // note the address width will always be using even
    localparam ODD_NO_PIXELS = (WIDTH / 2);
    localparam EVEN_NO_PIXELS = (WIDTH / 2) + (WIDTH % 2);

    // Since the number of lines in the buffer is guaranteed to be
    // a power of 2, we don't have to worry about odd/even
    localparam NO_LINES = (2 ** N_LINES_POW2) / 2;

    localparam ADDR_WIDTH = $clog2(EVEN_NO_PIXELS * NO_LINES);

    // Can't do this unfortunately, not sure why? says
    // "parameter refernce ... not valid when actual interface in the instance
    // is an arrayed instance element or below a generate construct"
    // localparam DATA_WIDTH = in.FP_M + in.FP_N + in.FP_S;

    localparam DATA_DEPTH = EVEN_NO_PIXELS * NO_LINES;
    localparam CLKS_MAX = (CLKS_PER_PIXEL > 6) ? 6 : CLKS_PER_PIXEL;

    ////////////////////////////////////////////////////////////////
    // Row buffer control wires consists of 4 Simple DPRAM
    // split amongst even and odd lines, and then amongst even and 
    // columns.
    //
    // A small 2x2 array will be used to setup the control wires
    //
    // ID | Row , Col
    // ---------------
    // 00 | even, even
    // 01 | even, odd
    // 10 | odd , even
    // 11 | odd , odd  

    // read
    logic [ADDR_WIDTH-1:0] r_rdaddr [0:1][0:1];
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] w_rddata [0:1][0:1];
    logic                  w_rddv [0:1][0:1];
    logic                  r_rden [0:1][0:1];

    // write
    logic [ADDR_WIDTH-1:0] r_wraddr [0:1][0:1];
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] r_wrdata [0:1][0:1];
    logic                  r_wrdv [0:1][0:1];

    ////////////////////////////////////////////////////////////////
    // Buffer instantiation and wiring
    genvar i;
    genvar k;
    generate
        for(i = 0; i < 2; i += 1) begin
            for(k = 0; k < 2; k += 1) begin         
                RAM_2Port #(
                    .WIDTH(in.FP_M + in.FP_N + in.FP_S),
                    .DEPTH(DATA_DEPTH)
                ) sdpram (
                    .i_Wr_Clk(in.clk),
                    .i_Wr_Addr(r_wraddr[i][k]),
                    .i_Wr_DV(r_wrdv[i][k]),
                    .i_Wr_Data(r_wrdata[i][k]),

                    .i_Rd_Clk(out.clk),
                    .i_Rd_Addr(r_rdaddr[i][k]),
                    .i_Rd_En(r_rden[i][k]),
                    .o_Rd_DV(w_rddv[i][k]),
                    .o_Rd_Data(w_rddata[i][k])
                );
                
                /*
                // ECP5 specific RAM instantiation
                ecp5_ram_sdp #(
                    .WIDTH(in.FP_M + in.FP_N + in.FP_S),
                    .DEPTH(DATA_DEPTH)
                ) sdpram (
                    .wr_clk_i(in.clk),
                    .wr_addr_i(r_wraddr[i][k]),
                    .wr_dv_i(r_wrdv[i][k]),
                    .wr_data_i(r_wrdata[i][k]),

                    .rd_clk_i(out.clk),
                    .rd_addr_i(r_rdaddr[i][k]),
                    .rd_en_i(r_rden[i][k]),
                    .rd_dv_o(w_rddv[i][k]),
                    .rd_data_o(w_rddata[i][k])
                );
                */
                          
            end
        end
    endgenerate

    ////////////////////////////////////////////////////////////////
    // Write pixel to buffer combinational logic
    logic [N_LINES_POW2-1:0] colmod_wr;

    always_comb begin
        for(int i = 0; i < 2; i += 1) begin
            for(int k = 0; k < 2; k += 1) begin
                r_wraddr[i][k] = 0;
                r_wrdata[i][k] = 0;
                r_wrdv[i][k] = 0;
            end
        end
        
        colmod_wr = in.row[N_LINES_POW2-1:0];
        r_wrdata[in.row[0]][in.col[0]] = in.pixel;

        if((in.col % 2) == 0) begin
            r_wraddr[in.row[0]][in.col[0]] = ((colmod_wr >> 1) * (EVEN_NO_PIXELS)) + (in.col >> 1);

        end else begin
            r_wraddr[in.row[0]][in.col[0]] = ((colmod_wr >> 1) * ( ODD_NO_PIXELS)) + (in.col >> 1);
        end

        if(in.valid == 1) begin
            r_wrdv[in.row[0]][in.col[0]] = 1;
        end 
    end

    

    // See diagram    
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] Q11;
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] Q21;
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] Q12;
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] Q22;

    ////////////////////////////////////////////////////////////////
    // Read pixels from buffer combinational logic
    logic [N_LINES_POW2-1:0] colmod_rd_0;
    logic [N_LINES_POW2-1:0] colmod_rd_1;
    
    // coordinates being requested from reverse mapping output pixel
    logic [15:0] col_req;
    logic [15:0] row_req;
    logic [15:0] col_reqp;
    logic [15:0] row_reqp;

    // Mux values for Q**
    logic mux_row [0:1];
    logic mux_col [0:1];
    logic mux_row_next [0:1];
    logic mux_col_next [0:1];

    // state to track in bounds
    logic inbounds[0:1][0:1];
    logic inbounds_next[0:1][0:1];


    always_comb begin
        ////////////////////////////////////////////////////////////////
        // Address Generation and Muxing Q**

        col_reqp = col_req + 1;
        row_reqp = row_req + 1;
        
        colmod_rd_0 = row_req[N_LINES_POW2-1:0];
        colmod_rd_1 = row_reqp[N_LINES_POW2-1:0];

        // setting read null values and read enable high, and inbounds as 0
        for(int i = 0; i < 2; i += 1) begin
            for(int k = 0; k < 2; k += 1) begin
                r_rdaddr[i][k] = 0;
                r_rden[i][k] = 1;
                inbounds_next[i][k] = 0;
            end
        end 

        // defaults for Q**
        Q11 = 0;
        Q21 = 0;
        Q12 = 0;
        Q22 = 0;

        // Q11
        if((col_req % 2) == 0) begin
            r_rdaddr[row_req[0]][col_req[0]] = ((colmod_rd_0 >> 1) * (EVEN_NO_PIXELS)) + (col_req >> 1);
        end else begin
            r_rdaddr[row_req[0]][col_req[0]] = ((colmod_rd_0 >> 1) * ( ODD_NO_PIXELS)) + (col_req >> 1);
        end
            
        
        // Q21
        if((col_reqp % 2) == 0) begin
            r_rdaddr[row_req[0]][col_reqp[0]] = ((colmod_rd_0 >> 1) * (EVEN_NO_PIXELS)) + (col_reqp >> 1);
        end else begin
            r_rdaddr[row_req[0]][col_reqp[0]] = ((colmod_rd_0 >> 1) * ( ODD_NO_PIXELS)) + (col_reqp >> 1);
        end

        // Q12
        if((col_req % 2) == 0) begin
            r_rdaddr[row_reqp[0]][col_req[0]] = ((colmod_rd_1 >> 1) * (EVEN_NO_PIXELS)) + (col_req >> 1);
        end else begin
            r_rdaddr[row_reqp[0]][col_req[0]] = ((colmod_rd_1 >> 1) * ( ODD_NO_PIXELS)) + (col_req >> 1);
        end                

        // Q22
        if((col_reqp % 2) == 0) begin
            r_rdaddr[row_reqp[0]][col_reqp[0]] = ((colmod_rd_1 >> 1) * (EVEN_NO_PIXELS)) + (col_reqp >> 1);
        end else begin
            r_rdaddr[row_reqp[0]][col_reqp[0]] = ((colmod_rd_1 >> 1) * ( ODD_NO_PIXELS)) + (col_reqp >> 1);
        end

        // setting mux values for Q**
        mux_row_next[0] = row_req[0];
        mux_row_next[1] = row_reqp[0];
        mux_col_next[0] = col_req[0];
        mux_col_next[1] = col_reqp[0];

        // determing if within bound
        // only relevant if requested pixel is in bound
        if((row_req >= 0) && (row_req < HEIGHT) && (col_req >= 0) && (col_req < WIDTH)) begin
            inbounds_next[0][0] = 1;
            
            if((row_req >= 0) && (row_req < HEIGHT) && (col_reqp >= 0) && (col_reqp < WIDTH)) begin
                inbounds_next[0][1] = 1;
            end

            if((row_reqp >= 0) && (row_reqp < HEIGHT) && (col_req >= 0) && (col_req < WIDTH)) begin
                inbounds_next[1][0] = 1;
            end

            if((row_reqp >= 0) && (row_reqp < HEIGHT) && (col_reqp >= 0) && (col_reqp < WIDTH)) begin
                inbounds_next[1][1] = 1;
            end
        end
        
        // finally setting according to inbounds
        Q11 = inbounds[0][0] == 1 ? w_rddata[mux_row[0]][mux_col[0]] : 0;
        Q21 = inbounds[0][1] == 1 ? w_rddata[mux_row[0]][mux_col[1]] : 0;
        Q12 = inbounds[1][0] == 1 ? w_rddata[mux_row[1]][mux_col[0]] : 0;
        Q22 = inbounds[1][1] == 1 ? w_rddata[mux_row[1]][mux_col[1]] : 0;

    end

    ////////////////////////////////////////////////////////////////
    // Output Driver

    // Need to wait for the buffer to fill before driving output pixels
    logic ispipefull;
    logic ispipefull_next;

    // Need to keep driving pixels when frame completes (to avoid overwrite)
    logic isframedone;
    logic isframedone_next;

    // Is the reverse mapper ready to recieve a new pixel
    logic w_status;

    logic [15:0] row_driver;
    logic [15:0] col_driver;
    logic dv_driver;

    // unfortunately because of how i designed the dv_driver signal
    // the last pixel does not get a valid high signal, so we have to do this
    logic [$clog2(CLKS_MAX)-1:0] last_pixel_counter;
    logic new_f;

    logic [$clog2(CLKS_MAX)-1:0] last_pixel_counter_next;
    logic new_f_next;

    logic [15:0] row_driver_next;
    logic [15:0] col_driver_next;

    always_comb begin
        row_driver_next = row_driver;
        col_driver_next = col_driver;
        last_pixel_counter_next = last_pixel_counter;
        new_f_next = new_f;
        dv_driver = 0;

        // output driver logic
        // w_status, ensure that when we are flushing the pipe, not to drive pixels
        // too fast
        if(((in.valid == 1) && (ispipefull == 1)) || ((isframedone == 1) && (w_status == 1))) begin
            dv_driver = 1;
            if(new_f == 1) begin
                dv_driver = 0;
            end
            if(col_driver == (WIDTH - 1)) begin
                col_driver_next = 0;
                if(row_driver == (HEIGHT - 1)) begin
                    row_driver_next = 0;
                end else begin
                    row_driver_next = row_driver + 1;
                end 
            end else begin
                col_driver_next = col_driver + 1;
                row_driver_next = row_driver;
            end
        end

        // additional dv driver logic to handle last pixel
        if((row_driver == (HEIGHT - 1)) && (col_driver == (WIDTH - 1)) && (new_f == 0)) begin
            if(last_pixel_counter == (CLKS_MAX - 1)) begin
                dv_driver = 1;
                new_f_next = 1;
            end 
            last_pixel_counter_next = last_pixel_counter + 1;
        end
        if((row_driver == 0) && (col_driver == 0)) begin
            new_f_next = 0;
            last_pixel_counter_next = 0;
        end

        // is frame done logic
        isframedone_next = 0;
        if(isframedone == 1) begin
            isframedone_next = 1;
            // output frame finished, reset isframedone to track new incoming frame
            // ispipefull should also be reset
            if((row_driver == (HEIGHT - 1)) && (col_driver == (WIDTH - 1))) begin
                isframedone_next = 0;
            end
        end else begin
            // input frame finished, keep driving output pixels during vsync blank
            if((in.row == (HEIGHT - 1)) && (in.col == (WIDTH - 1)) && (in.valid == 1)) begin
                isframedone_next = 1;
            end
        end 

        // pipe full logic with frame done added
        ispipefull_next = 0;
        if(ispipefull == 1) begin
            ispipefull_next = 1;
            // frame being consumed is like the pipe being flushed, reset
            if((isframedone == 1) && (isframedone_next == 0)) begin
                ispipefull_next = 0;
            end
        end else begin
            if((in.row >= PIPE_ROW) && (in.col >= PIPE_COL) && (in.valid == 1)) begin
                ispipefull_next = 1;
            end
        end

        // reset logic
        if(!rst_n_i) begin
            ispipefull_next = 0;
            isframedone_next = 0;
            row_driver_next = 0;
            col_driver_next = 0;
            last_pixel_counter_next = 0;
            new_f_next = 0;
        end
    end

    ////////////////////////////////////////////////////////////////
    // Reverse Mapper

    logic [15:0] w_row_0;
    logic [15:0] w_col_0;
    logic [15:0] w_row_int_xform_0;
    logic [15:0] w_col_int_xform_0;
    logic [PRECISION-1:0] w_row_frac_xform_0;
    logic [PRECISION-1:0] w_col_frac_xform_0;
    logic w_dv_0;

    reverse_mapper #(
        .PRECISION(PRECISION),
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .CLKS_PER_PIXEL(CLKS_PER_PIXEL)
    ) reverse_mapper (
        .clk(in.clk),
        .rst_n_i(rst_n_i),
        .row_i(row_driver),
        .col_i(col_driver),
        .dv_i(dv_driver),
        .matrix_i(matrix_i),
        
        .row_o(w_row_0),
        .col_o(w_col_0),
        .row_int_xform_o(w_row_int_xform_0),
        .row_frac_xform_o(w_row_frac_xform_0),
        .col_int_xform_o(w_col_int_xform_0),
        .col_frac_xform_o(w_col_frac_xform_0),
        .dv_o(w_dv_0),
        .status_o(w_status)
    );

    ////////////////////////////////////////////////////////////////
    // Bilinear Interpolater

    bilinear_interpolater #(
        .FP_M(in.FP_M),
        .FP_N(in.FP_N),
        .FP_S(in.FP_S)
    ) bilinear_interpolater (
        .clk(in.clk),
        .row_i(w_row_0),
        .col_i(w_col_0),
        .row_int_xform_i(w_row_int_xform_0),
        .col_int_xform_i(w_col_int_xform_0),
        .row_frac_xform_i(w_row_frac_xform_0),
        .col_frac_xform_i(w_col_frac_xform_0),
        .dv_i(w_dv_0),

        .Q11_i(Q11),
        .Q21_i(Q21),
        .Q12_i(Q12),
        .Q22_i(Q22),

        .row_req_o(row_req),
        .col_req_o(col_req),

        .row_o(out.row),
        .col_o(out.col),
        .pixel_o(out.pixel),
        .dv_o(out.valid)
    );
    
    
    always@(posedge in.clk) begin
        mux_row <= mux_row_next;
        mux_col <= mux_col_next;
        inbounds <= inbounds_next;

        row_driver <= row_driver_next;
        col_driver <= col_driver_next;
        ispipefull <= ispipefull_next;
        isframedone <= isframedone_next;

        last_pixel_counter <= last_pixel_counter_next;
        new_f <= new_f_next;
    end

    // debug wires (vcd doesn't track interface signals directly)
    logic [in.FP_M + in.FP_N + in.FP_S-1:0] pixel_i;
    logic [15:0] row_i;
    logic [15:0] col_i;
    logic valid_i;

    logic [out.FP_M + out.FP_N + out.FP_S-1:0] pixel_o;
    logic [15:0] row_o;
    logic [15:0] col_o;
    logic valid_o;

    assign pixel_i = in.pixel;
    assign row_i = in.row;
    assign col_i = in.col;
    assign valid_i = in.valid;

    assign pixel_o = out.pixel;
    assign col_o = out.col;
    assign row_o = out.row;
    assign valid_o = out.valid;

endmodule

/**
 * This module takes output coordinates from the output driver 
 * and through a series of affine and non-affine transformations 
 * gives the reverse mapping onto the input image
 * The row and col numbers will be treated as 11 bit 
 * signed numbers, so we can dedicate more bits to the matrix values.
 */

module reverse_mapper #(
    // how many bits for decimal place for col and row fractional part
    parameter PRECISION = 8,
    
    // used for look up table
    parameter WIDTH = 8,
    parameter HEIGHT = 8,

    // how many cycles do we have
    parameter CLKS_PER_PIXEL = 1
) (
    input clk,
    input rst_n_i,

    input [15:0] row_i,
    input [15:0] col_i,
    input dv_i,

    // transformation matrix
    input signed [11+PRECISION-1:0] matrix_i [3][3],

    output [15:0] row_o,
    output [15:0] col_o,

    // transformed coordinates
    output [15:0]     row_int_xform_o,
    output [PRECISION-1:0] row_frac_xform_o,

    output [15:0]     col_int_xform_o,
    output [PRECISION-1:0] col_frac_xform_o,

    output dv_o,

    // we need to let our pixel driver know
    // when it can drive pixels according to 
    // CLKS_PER_PIXEL
    output status_o
);
    logic [15:0] r_row_int_xform;
    logic [15:0] r_col_int_xform;
    logic [15:0] r_row_frac_xform;
    logic [15:0] r_col_frac_xform;
    
    // input state
    logic signed [15:0] r_row;
    logic signed [15:0] r_col;
    logic r_dv;

    logic [15:0] r_row_next;
    logic [15:0] r_col_next;
    logic r_dv_next;

    // accumulator
    logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_row = 0;
    logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_col = 0;

    logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_row_next;
    logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_col_next;

    logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_row_out;
    logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_col_out;

    // state and index variables, 6 multiplies to be done
    localparam CLKS_MAX = (CLKS_PER_PIXEL > 6) ? 6 : CLKS_PER_PIXEL;
    localparam PARALLEL_MACS = ((6 % CLKS_MAX) != 0) ? 
                               ((6 / CLKS_MAX) + 1) : 
                               (6 / CLKS_MAX);

    
    logic [$clog2(CLKS_MAX):0] step;
    logic [$clog2(CLKS_MAX):0] step_next;
    logic r_dv_o;
    logic r_dv_o_next;

    // index variables
    integer si, offset;

    // eplicitly stating subscripts as signed
    logic signed [10:0] r_row_11bit;
    logic signed [10:0] r_col_11bit;
    logic signed [10:0] one_11bit;
    assign r_row_11bit = r_row[10:0];
    assign r_col_11bit = r_col[10:0];
    assign one_11bit = 1;

    // place in array for synthesis tool
    logic signed [10:0] coord_flatten [6];
    logic signed [11+PRECISION-1:0] matrix_flatten [6];

    always_comb begin
        
        ////////////////////////////////////////////////////////////////
        // Matrix calculations wrt to step
        // assigning flattened arrays
        matrix_flatten[0] = matrix_i[0][0];
        matrix_flatten[1] = matrix_i[0][1];
        matrix_flatten[2] = matrix_i[0][2];
        matrix_flatten[3] = matrix_i[1][0];
        matrix_flatten[4] = matrix_i[1][1];
        matrix_flatten[5] = matrix_i[1][2];

        coord_flatten[0] = r_col_11bit;
        coord_flatten[1] = r_row_11bit;
        coord_flatten[2] = one_11bit;
        coord_flatten[3] = r_col_11bit;
        coord_flatten[4] = r_row_11bit;
        coord_flatten[5] = one_11bit;

        si = step * PARALLEL_MACS;
        acc_row_out = acc_row;
        acc_col_out = acc_col;
        

        for(int s = 0; s < PARALLEL_MACS; s += 1) begin
            offset = si + s;
            if(offset < 6) begin
                // for acc col
                if(offset < 3) begin
                    acc_col_out += (matrix_flatten[offset] * coord_flatten[offset]);
                // for acc row
                end else begin
                    acc_row_out += (matrix_flatten[offset] * coord_flatten[offset]);
                end
            end
        end
        
        ////////////////////////////////////////////////////////////////
        // State logic and registering data
        step_next = 0;

        if(step == (CLKS_MAX - 1)) begin
            r_dv_next = dv_i;
            r_row_next = row_i;
            r_col_next = col_i;

            acc_row_next = 0;
            acc_col_next = 0;
            
            if(dv_i == 1) begin
                step_next = 0;
            end else begin
                step_next = step;
            end
            if(CLKS_MAX == 1) step_next = 0;
        end else begin
            r_dv_next = r_dv;
            r_row_next = r_row;
            r_col_next = r_col;

            acc_row_next = acc_row_out;
            acc_col_next = acc_col_out;

            step_next = step + 1;
        end

        // dv_o logic
        r_dv_o_next = 0;

        if(CLKS_MAX == 1) begin
            r_dv_o_next = dv_i;
        end else begin
            if(step == (CLKS_MAX - 2)) begin
                r_dv_o_next = 1;
            end
        end

        if(!rst_n_i) begin
            step_next = (CLKS_MAX - 1);
        end
    end

    // pipeline
    always@(posedge clk) begin
        r_row <= r_row_next;
        r_col <= r_col_next;
        r_dv  <= r_dv_next;

        r_dv_o = r_dv_o_next;
        step <= step_next;
        acc_row <= acc_row_next;
        acc_col <= acc_col_next;
    end

    assign row_o = r_row;
    assign col_o = r_col;
    assign dv_o = r_dv_o;

    assign row_int_xform_o = acc_row_out[16 + PRECISION-1:PRECISION];
    assign col_int_xform_o = acc_col_out[16 + PRECISION-1:PRECISION];
    assign row_frac_xform_o = acc_row_out[PRECISION-1:0];
    assign col_frac_xform_o = acc_col_out[PRECISION-1:0];
    assign status_o = (CLKS_MAX == 1) ? 1 : ((step == (CLKS_MAX - 1)) ? 1 : 0);

endmodule


/**
 * This module takes coordinates from the reverse_mapper
 * fetches the appropriate 4 pixel values, and performs
 * bilinear interpolation
 */

////////////////////////////////////////////////////////////////
// Bilinear xform related
// see fig.10.7 in 'Design for Embedded Image Processing on 
// FPGAs' by Donald G. Bailey
/*
 * Diagramtic Representation of whats going on
 *
 *                Qtop
 *                 |
 *    Q11          v        Q21
 *  (xi, yi) ----------- (xi + 1, yi)
 *      |          |         |
 *      | (xf, yf) .         |
 *      |          |         |
 *  (xi, yi + 1) -------- (xi + 1, yi + 1)
 *    Q12          ^         Q22
 *                 |
 *                Qbot
 *
 * synonyms
 * Q11 <=> I[xi, yi]
 * Q21 <=> I[xi + 1, yi]
 * Q12 <=> I[xi, yi + 1]
 * Q22 <=> I[xi + 1, yi + 1]
 *
 * Qtop <=> Iyi   = I[xi, yi] + xf(I[xi + 1, yi] - I[xi, yi])
 *                = Q11 + xf * (Q21 - Q11)
 *
 * Qbot <=> Iyi+1 = I[xi, yi + 1] + xf(I[xi + 1,yi + 1] - I[xi, yi + 1])
 *                = Q12 + xf * (Q22 - Q12)
 *
 * then 'Qfinal' will be the weighted sum of Qtop and Qbot.
 *
 * Qfinal <=> I[x,y] = Iyi + yf(Iyi+1 - Iyi)
 *                   = Qtop + yf(Qbot - Qtop)
 */

module bilinear_interpolater#(
    parameter FP_M = 8,
    parameter FP_N = 0,
    parameter FP_S = 0,

    // how many bits for decimal place for col and row fractional part
    parameter PRECISION = 8

) (
    input clk,

    input [15:0] row_i,
    input [15:0] col_i,

    // reversed mapped coordinates
    input [15:0]          row_int_xform_i,
    input [PRECISION-1:0] row_frac_xform_i,

    input [15:0]          col_int_xform_i,
    input [PRECISION-1:0] col_frac_xform_i,

    input dv_i,

    input [FP_M + FP_N + FP_S -1:0] Q11_i,
    input [FP_M + FP_N + FP_S -1:0] Q21_i,
    input [FP_M + FP_N + FP_S -1:0] Q12_i,
    input [FP_M + FP_N + FP_S -1:0] Q22_i,

    // fetch from buffer this coordinates
    // (row/col int rerouted basically)
    output [15:0] row_req_o,
    output [15:0] col_req_o,

    output [15:0] row_o,
    output [15:0] col_o,

    output [FP_M + FP_N + FP_S -1:0] pixel_o,

    output dv_o
);

    // we need to sign the fractional values by appending a 0
    localparam PRECISION_S = PRECISION + 1;


    // the simulator doesn't play nice with using arrays for pipelinig for some reason?
    // so I am explicitly stating everything (how painful)
    // It turns out, using [3] instead of [0:1] to specify the lenght of the array
    // solves this problem, why? I don't know. 

    // coordinates
    logic [15:0] row_pipe [3];
    logic [15:0] col_pipe [3];
    logic dv_pipe [3];

    // transformed coordinates 
    logic [15:0] row_int_xform_pipe [3];
    logic [15:0] col_int_xform_pipe [3];

    logic [PRECISION-1:0] row_frac_xform_pipe [3];
    logic [PRECISION-1:0] col_frac_xform_pipe [3];

    // signed fractional parts (by appending 0)
    logic signed [PRECISION_S-1:0] row_frac_xform_pipe_2_im_0;
    logic signed [PRECISION_S-1:0] col_frac_xform_pipe_1_im_0;

    // assumed to be signed
    logic signed [FP_M + FP_N + 1 -1:0] Qtop;
    logic signed [FP_M + FP_N + 1 -1:0] Qbot;

    // assumed to be signed
    logic signed [FP_M + FP_N + 1 -1:0] Qtop_next;
    logic signed [FP_M + FP_N + 1 -1:0] Qbot_next;

    logic [FP_M + FP_N + FP_S -1:0] Qfinal;

    // unsigned numbers need to be converted to sign first
    logic signed [FP_M + FP_N + 1 -1:0] Q11_;
    logic signed [FP_M + FP_N + 1 -1:0] Q21_;
    logic signed [FP_M + FP_N + 1 -1:0] Q12_;
    logic signed [FP_M + FP_N + 1 -1:0] Q22_;
    
    // logic for calculations and intermediate values
    logic signed [FP_M + FP_N + 1 + 1 -1:0]                   Qtop_im_0;
    logic signed [PRECISION_S + FP_M + FP_N + 1 + 1 -1:0]     Qtop_im_1;
    logic signed [PRECISION_S + FP_M + FP_N + 1 + 1 + 1 -1:0] Qtop_im_2;
    logic signed [PRECISION + FP_M + FP_N + 1 -1:0] Qtop_im_pad;

    logic signed [FP_M + FP_N + 1 + 1 -1:0]                   Qbot_im_0;
    logic signed [PRECISION_S + FP_M + FP_N + 1 + 1 -1:0]     Qbot_im_1;
    logic signed [PRECISION_S + FP_M + FP_N + 1 + 1 + 1 -1:0] Qbot_im_2;
    logic signed [PRECISION + FP_M + FP_N + 1 -1:0] Qbot_im_pad;

    logic signed [FP_M + FP_N + 1 + 1 -1:0]                   Qfinal_im_0;
    logic signed [PRECISION_S + FP_M + FP_N + 1 + 1 -1:0]     Qfinal_im_1;
    logic signed [PRECISION_S + FP_M + FP_N + 1 + 1 + 1 -1:0] Qfinal_im_2;
    logic signed [PRECISION + FP_M + FP_N + 1 -1:0] Qfinal_im_pad;

    always_comb begin
        // if unsigned, convert to sign by appending 0
        Q11_ = Q11_i;
        Q21_ = Q21_i;
        Q12_ = Q12_i;
        Q22_ = Q22_i;

        if(FP_S == 0) begin
            Q11_ = {{1'b0}, Q11_i};
            Q21_ = {{1'b0}, Q21_i};
            Q12_ = {{1'b0}, Q12_i};
            Q22_ = {{1'b0}, Q22_i};
        end 
        
        ////////////////////////////////////////////////////////////////
        // In STAGE 1 calculations
        // Qtop = Q11 + xf * (Q21 - Q11)
        col_frac_xform_pipe_1_im_0 = {{1'b0},col_frac_xform_pipe[1]};

        Qtop_im_0 = Q21_ - Q11_;
        Qtop_im_1 = col_frac_xform_pipe_1_im_0 * Qtop_im_0;
        Qtop_im_pad = {Q11_, {PRECISION{1'b0}}};
        Qtop_im_2 = Qtop_im_pad + Qtop_im_1;
        Qtop_next = Qtop_im_2[FP_M + FP_N + 1 - 1 + PRECISION: PRECISION];

        // Qbot = Q12 + xf * (Q22 - Q12)
        Qbot_im_0 = Q22_ - Q12_;
        Qbot_im_1 = col_frac_xform_pipe_1_im_0 * Qbot_im_0;
        Qbot_im_pad = {Q12_, {PRECISION{1'b0}}};
        Qbot_im_2 = Qbot_im_pad + Qbot_im_1;
        Qbot_next = Qbot_im_2[FP_M + FP_N + 1 - 1 + PRECISION: PRECISION];

        ////////////////////////////////////////////////////////////////
        // STAGE 2 calculations
        // Qfinal = Qtop + yf(Qbot - Qtop)
        row_frac_xform_pipe_2_im_0 = {{1'b0},row_frac_xform_pipe[2]};

        Qfinal_im_0 = Qbot - Qtop;
        Qfinal_im_1 = row_frac_xform_pipe_2_im_0 * Qfinal_im_0;
        Qfinal_im_pad = {Qtop, {PRECISION{1'b0}}};
        Qfinal_im_2 =  Qfinal_im_pad + Qfinal_im_1;
        Qfinal = Qfinal_im_2[FP_M + FP_N + FP_S - 1 + PRECISION: PRECISION];

    end

    logic [15:0] r_row_req;
    logic [15:0] r_col_req;

    // pipeline
    always@(posedge clk) begin
        // Stage 0 - entry, fetch requested pixels
        row_pipe[0] <= row_i;
        col_pipe[0] <= col_i;
        dv_pipe[0]  <= dv_i;

        row_int_xform_pipe[0] <= row_int_xform_i;
        col_int_xform_pipe[0] <= col_int_xform_i;

        row_frac_xform_pipe[0] <= row_frac_xform_i;
        col_frac_xform_pipe[0] <= col_frac_xform_i;

        r_row_req <= row_int_xform_i;
        r_col_req <= col_int_xform_i;

        // Stage 1 - pixels recieved, calculate Qbot and Qtop
        row_pipe[1] <= row_pipe[0];
        col_pipe[1] <= col_pipe[0];
        dv_pipe[1]  <= dv_pipe[0];

        row_int_xform_pipe[1] <= row_int_xform_pipe[0];
        col_int_xform_pipe[1] <= col_int_xform_pipe[0];

        row_frac_xform_pipe[1] <= row_frac_xform_pipe[0];
        col_frac_xform_pipe[1] <= col_frac_xform_pipe[0];

        // Qtop_next; see always_comb
        // Qbot_next; see always_comb

        // Stage 2 - Qbot, Qtop recieved, Qfinal calculated and outputted
        Qtop <= Qtop_next;
        Qbot <= Qbot_next;

        row_pipe[2] <= row_pipe[1];
        col_pipe[2] <= col_pipe[1];
        dv_pipe[2]  <= dv_pipe[1];

        row_int_xform_pipe[2] <= row_int_xform_pipe[1];
        col_int_xform_pipe[2] <= col_int_xform_pipe[1];

        row_frac_xform_pipe[2] <= row_frac_xform_pipe[1];
        col_frac_xform_pipe[2] <= col_frac_xform_pipe[1];

        // Qfinal; see always_comb

    end
    
    assign row_o = row_pipe[2];
    assign col_o = col_pipe[2];
    assign dv_o = dv_pipe[2];
    assign pixel_o = Qfinal;
    assign row_req_o = r_row_req;
    assign col_req_o = r_col_req;

endmodule

