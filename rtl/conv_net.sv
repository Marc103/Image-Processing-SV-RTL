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

/* Convolutional filter
 *
 * using parallel row buffering following 'Design for Embedded Image Processing on FPGAs' 
 * by Donald G. Bailey
 * follows    
 * Q[x,y] = f( I[x,y], ... , I[x + dx, y + dy]),  (dx, dy) in W    
 * terminology in the book in comments
 *
 * 'K_DEPTH' is important for the kernel modules that calculate Q[x,y]
 *  i.e if we simply add all the numbers in the window together in our kernel module,
 * 'K_DEPTH has to be sufficiently large enough to hold the resulting value.
 *
 * conv_entry_lut module is actually synthesizable, however, shift registers are used 
 * in place of the FIFO
 *
 * TODO, add stalling mechanism for constant extension
 * actually, since the window size is expected to be small, we will just calculate the 
 * coordinates within the window to decide whether its out of bounds
 *
 * The stalling mechanism would use scale linearly with the window size, the 'naive' method will
 * scale exponentially in terms of resource use (muxes, adders, comparators) but simplifies the
 * design greatly. Also maybe that's not so bad, in software it takes exponential time to check for
 * each index in the window if it is within bounds, and so instead we parallize the operation by
 * trading the exponential time with exponential amount of resource.
 *
 * Side note, works for kernel window dimenions < roughly double the image dimensions
 *
 * It is assumed that after reset, pixel (0,0) is fed first as an input
 */

module conv_net #(
    // We make the fixed point format a part of the interface parameters so that pixel format can
    // be deduced at synthesis time.
    
    // Kernel FP parameters 
    parameter FP_M_KERNEL = 8,
    parameter FP_N_KERNEL = 0,
    parameter FP_S_KERNEL = 0,

    // input image dimensions
    parameter WIDTH = 5,
    parameter HEIGHT = 5,

    parameter FP_M_IMAGE = 8,
    parameter FP_N_IMAGE = 0,
    parameter FP_S_IMAGE = 0,

    // kernel window dimensions
    parameter K_WIDTH = 3,
    parameter K_HEIGHT = 3,

    // Constant extension value
    parameter CONSTANT = 0,

    // how many cycles do we have per pixel (should be < (K_WIDTH * K_HEIGHT))
    parameter CLKS_PER_PIXEL = 1

) ( 
    pixel_data_interface.writer in,
    
    // reset signal
    input rst_n_i,

    // clock
    output pclk_o,

    // data valid, are we about to shift new values in?
    output dv_o,

    // is the pipe full?
    output ispipefull_o,

    // kernel state and cycle count is managed by the conv_net module
    output                            kernel_state_o,
    output [$clog2(CLKS_PER_PIXEL):0] convolution_step_o,

    // output kernel window
    output  [(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE -1):0] kernel_o [K_HEIGHT][K_WIDTH],

    // outgoing pipe pixel col and row
    output  [15:0]  col_o, 
    output  [15:0]  row_o, 

    // kernel status output (ready or busy, 1 is ready 0 is busy)
    output kernel_status_o
); 
    localparam MID_K_H = K_HEIGHT/2;
    localparam MID_K_W = K_WIDTH/2;

    // State for pipe col and row index
    logic [15:0]   col_pipe;
    logic [15:0]   row_pipe;

    logic [15:0]   col_pipe_next;
    logic [15:0]   row_pipe_next;

    // Kernel State for cycles per pixel
    localparam READY = 1'b1;
    localparam BUSY = 1'b0;

    logic kernel_state;
    logic kernel_state_next;

    localparam CLKS_MAX = (CLKS_PER_PIXEL > (K_HEIGHT*K_WIDTH)) ? (K_HEIGHT*K_WIDTH) : CLKS_PER_PIXEL;

    logic [$clog2(CLKS_MAX):0] convolution_step ;
    logic [$clog2(CLKS_MAX):0] convolution_step_next;

    // is pipe full?
    logic ispipefull;
    logic ispipefull_next;

    // Data valid wrt to the kernel state
    logic w_dv_i;
    assign w_dv_i = (kernel_state == READY) && (in.valid == 1) ? 1 : 0;
    assign kernel_status_o = kernel_state;

    always@(*) begin
        
        ////////////////////////////////////////////////////////////////
        // Kernel State logic
        kernel_state_next = kernel_state;
        convolution_step_next = convolution_step;

        case(kernel_state)
            READY: begin
                if(in.valid) begin
                    if(CLKS_MAX == 1) begin
                        kernel_state_next = READY;
                        convolution_step_next = 0;
                    end else begin
                        kernel_state_next = BUSY;
                        convolution_step_next = 0;
                    end
                end
            end
            BUSY: begin
                if(convolution_step == (CLKS_MAX - 2)) begin
                    kernel_state_next = READY;
                    convolution_step_next = (CLKS_MAX - 1);
                end else begin
                    kernel_state_next = BUSY;
                    convolution_step_next = convolution_step + 1;
                end
            end
        endcase


        ////////////////////////////////////////////////////////////////
        // Pipe col and row incrementing logic

        row_pipe_next = row_pipe;
        col_pipe_next = col_pipe;

        if(w_dv_i) begin
            row_pipe_next = row_pipe;
            col_pipe_next = col_pipe + 1;

            // sync
            if((in.col == (WIDTH - 1)) && (in.row == (HEIGHT - 1))) begin
                col_pipe_next = (WIDTH - 1) - MID_K_W;
                row_pipe_next = (HEIGHT - 1) - MID_K_H;
            end
            else begin
                if(col_pipe == (WIDTH - 1)) begin
                    col_pipe_next = 0;
                    if(row_pipe == (HEIGHT -1))
                        row_pipe_next = 0;
                    else
                        row_pipe_next = row_pipe + 1;
                end


            end
        end

        ////////////////////////////////////////////////////////////////
        // Is pipe full? 
        ispipefull_next = 0;

        if(ispipefull == 1) begin
            ispipefull_next = 1;
        end else begin
            if((row_pipe == (HEIGHT-1)) && (col_pipe == (WIDTH-1)) && (w_dv_i == 1)) begin
                ispipefull_next = 1;
            end 
        end

        // reset logic
        if(!rst_n_i) begin
            ispipefull_next = 0;
            col_pipe_next = (WIDTH - 1) - MID_K_W;
            row_pipe_next = (HEIGHT - 1) - MID_K_H;
            kernel_state_next = READY;
            convolution_step_next = (CLKS_MAX - 1);
        end 

    end

    always@(posedge in.clk) begin
        ispipefull       <= ispipefull_next;
        row_pipe         <= row_pipe_next;
        col_pipe         <= col_pipe_next;
        kernel_state     <= kernel_state_next;
        convolution_step <= convolution_step_next;
    end

    // Wiring between modules
    logic [(in.FP_M + in.FP_N + in.FP_S -1):0] w_kernel_cel_cr  [K_HEIGHT][K_WIDTH];
    logic [(in.FP_M + in.FP_N + in.FP_S -1):0] w_kernel_cr_ksa  [K_HEIGHT][K_WIDTH];

    conv_entry_fifo #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DEPTH(in.FP_M + in.FP_N + in.FP_S),
        .K_WIDTH(K_WIDTH),
        .K_HEIGHT(K_HEIGHT),
        .K_DEPTH(FP_M_KERNEL + FP_N_KERNEL + FP_S_KERNEL)
    ) conv_entry (
        .rst_n_i(rst_n_i),    
        .pclk_i(in.clk),
        .dv_i(w_dv_i),
        .pixel_data_i(in.pixel),
        .kernel_o(w_kernel_cel_cr)
    );

    conv_router #(
        .WIDTH(WIDTH),
        .HEIGHT(HEIGHT),
        .DEPTH(in.FP_M + in.FP_N + in.FP_S),
        .K_WIDTH(K_WIDTH),
        .K_HEIGHT(K_HEIGHT),
        .CONSTANT(CONSTANT)
    ) conv_router (
        .kernel_i(w_kernel_cel_cr),
        .col_i(col_pipe),
        .row_i(row_pipe),
        .kernel_o(w_kernel_cr_ksa)
    );

    assign pclk_o = in.clk;
    assign ispipefull_o = ispipefull;
    assign kernel_state_o = kernel_state;
    assign convolution_step_o = convolution_step;
    assign kernel_o = w_kernel_cr_ksa;
    assign col_o = col_pipe;
    assign row_o = row_pipe;
    assign dv_o = w_dv_i;
    
endmodule

/**
 * This module contains the row buffers and window shift registers
 * it takes in the pixel data and pushes it along.
 * The output is the kernel window of data. It's postfixed with 'lut'
 * because it uses shift registers for the row instead of proper FIFOs
 *
 */

module conv_entry_lut #(
    parameter WIDTH = 320,
    parameter HEIGHT = 240,
    parameter DEPTH = 8,
    parameter K_WIDTH = 3,
    parameter K_HEIGHT = 3,
    parameter K_DEPTH = 8
)  (
    // reset, in this module, no effect
    input                rst_n_i,

    // pixel clock
    input                pclk_i,

    // incoming pixel data
    input  [(DEPTH-1):0] pixel_data_i,
    input                dv_i,

    // outgoing kernel window
    output [(DEPTH-1):0] kernel_o  [K_HEIGHT][K_WIDTH]
);

    localparam MID_K_H = HEIGHT/2;
    localparam MID_K_W = WIDTH/2;

    // Kernel Shift Registers
    logic [(DEPTH-1):0] ksr      [K_HEIGHT][K_WIDTH];
    logic [(DEPTH-1):0] ksr_next [K_HEIGHT][K_WIDTH];

    // Buffer Shift Registers
    // in RTL this should be proper FIFOs (well a shift register implementation can be done too if we need to swap BRAM for LUTs)
    // note that there are K_HEIGHT - 1 buffers required, not K_HEIGHT
    logic [(DEPTH-1):0] bsr      [0:(K_HEIGHT-2)][0:(WIDTH-1)];
    logic [(DEPTH-1):0] bsr_next [0:(K_HEIGHT-2)][0:(WIDTH-1)];

    // Indexing variables 
    integer k_r, k_c;
    integer b_r, b_c;
    integer si;

    always@(*) begin
        ////////////////////////////////////////////////////////////////
        // Kernel Shift Register wiring
        for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
            for(k_c = 0; k_c < K_WIDTH; k_c = k_c + 1) begin
                ksr_next[k_r][k_c] = ksr[k_r][k_c];
            end
        end

        if(dv_i) begin
            // main shift registers
            for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
                for(k_c = 1; k_c < K_WIDTH; k_c = k_c + 1) begin
                    ksr_next[k_r][k_c] = ksr[k_r][k_c - 1];
                end
            end

            // first row first register, pixel data fed here
            ksr_next[0][0] = pixel_data_i;

            // rest of rows's first registers, repsective buffer out fed here
            for(k_r = 1; k_r < K_HEIGHT; k_r = k_r + 1) begin
                ksr_next[k_r][0] = bsr[k_r - 1][WIDTH - 1];
            end
        end
        
        ////////////////////////////////////////////////////////////////
        // Buffer Shift Register wiring
        for(b_r = 0; b_r < (K_HEIGHT - 1); b_r = b_r + 1) begin
            for(b_c = 0; b_c < WIDTH; b_c = b_c + 1) begin
                bsr_next[b_r][b_c] = bsr[b_r][b_c];
            end
        end

        if(dv_i) begin
            // main shift registers
            for(b_r = 0; b_r < (K_HEIGHT - 1); b_r = b_r + 1) begin
                for(b_c = 1; b_c < WIDTH; b_c = b_c + 1) begin
                    bsr_next[b_r][b_c] = bsr[b_r][b_c - 1];
                end
            end

            // first row first register, pixel data fed here
            bsr_next[0][0] = pixel_data_i;

            for(b_r = 1; b_r < (K_HEIGHT - 1); b_r = b_r + 1) begin
                bsr_next[b_r][0] = bsr[b_r - 1][WIDTH - 1];
            end
        end

    end

    always@(posedge pclk_i) begin
        // Kernel Shift Register update
        for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
            for(k_c = 0; k_c < K_WIDTH; k_c = k_c + 1) begin
                ksr[k_r][k_c] <= ksr_next[k_r][k_c];
            end
        end

         // Buffer Shift Register update
        for(b_r = 0; b_r < (K_HEIGHT - 1); b_r = b_r + 1) begin
            for(b_c = 0; b_c < WIDTH; b_c = b_c + 1) begin
                bsr[b_r][b_c] <= bsr_next[b_r][b_c];
            end
        end

    end

    assign kernel_o = ksr;

endmodule

/**
 * This module contains the row buffers and window shift registers
 * it takes in the pixel data and pushes it along.
 * The output is the kernel window of data. It is the appropriate FIFO
 * version of 'conv_entry_lut', hence postfixed with 'fifo'
 *
 */

module conv_entry_fifo #(
    parameter WIDTH = 320,
    parameter HEIGHT = 240,
    parameter DEPTH = 8,
    parameter K_WIDTH = 3,
    parameter K_HEIGHT = 3,
    parameter K_DEPTH = 8
)  (
    // reset
    input rst_n_i,

    // pixel clock
    input                                      pclk_i,

    // incoming pixel data
    input  [(DEPTH-1):0]                       pixel_data_i,
    input                                      dv_i,

    // outgoing kernel window
    output [(DEPTH-1):0] kernel_o  [K_HEIGHT][K_WIDTH]
);

    localparam MID_K_H = HEIGHT/2;
    localparam MID_K_W = WIDTH/2;

    // Kernel Shift Registers
    logic [(DEPTH-1):0] ksr      [K_HEIGHT][K_WIDTH];
    logic [(DEPTH-1):0] ksr_next [K_HEIGHT][K_WIDTH];

    ////////////////////////////////////////////////////////////////
    // Wiring for Row Buffers as synchronous FIFOs
    //
    // note that there are K_HEIGHT - 1 buffers required, not K_HEIGHT
    // It is necessary at the start to separate the read and write pointers
    // by the WIDTH of the image before allowing data to be read out

    // rw pointer separation counter
    logic [$clog2(WIDTH):0] pointer_separation;
    logic [$clog2(WIDTH):0] pointer_separation_next;

    // read
    logic               r_rrst_n      ;
    logic               r_rrst_n_next ;
    logic               r_rd          ;
    logic [(DEPTH-1):0] w_rdata       [K_HEIGHT];
    logic               w_rempty      [K_HEIGHT];

    // write
    logic               r_wrst_n      ;
    logic               r_wrst_n_next ;
    logic               r_wr          ;
    logic [(DEPTH-1):0] w_wdata       [K_HEIGHT];
    logic               w_wfull       [K_HEIGHT];

    // Indexing variables
    integer k_r, k_c;
    integer b_r, b_c;

    always@(*) begin
        ////////////////////////////////////////////////////////////////
        // Kernel Shift Register wiring
        for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
            for(k_c = 0; k_c < K_WIDTH; k_c = k_c + 1) begin
                ksr_next[k_r][k_c] = ksr[k_r][k_c];
            end
        end


        if(dv_i) begin
            // main shift registers
            for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
                for(k_c = 1; k_c < K_WIDTH; k_c = k_c + 1) begin
                    ksr_next[k_r][k_c] = ksr[k_r][k_c - 1];
                end
            end

            // first row first register, pixel data fed here
            ksr_next[0][0] = pixel_data_i;

            // rest of rows's first registers, repsective buffer out fed here
            for(k_r = 1; k_r < K_HEIGHT; k_r = k_r + 1) begin
                ksr_next[k_r][0] = w_rdata[k_r - 1];
            end
        end
        

        ////////////////////////////////////////////////////////////////
        // Row Buffer State Control, includes pointer separation

        // logic is,
        // if dv, we can always write
        // if dv, we can only read if pointers are separated by WIDTH
        // if not dv, cant read nor write
        
        pointer_separation_next = pointer_separation;
        r_rd = 0;
        r_wr = 0;

        if(dv_i) begin
            r_wr = 1;

            if(pointer_separation == (WIDTH - 1)) begin
                r_rd = 1;
            end
            else begin
                pointer_separation_next = pointer_separation + 1;
                r_rd = 0;
            end

        end

        // buffer reset logic, todo
        if(!rst_n_i) begin
            r_rrst_n_next = 0;
            r_wrst_n_next = 0;
            pointer_separation_next = 0;
        end else begin
            r_rrst_n_next = 1;
            r_wrst_n_next = 1;
        end
    end

    always@(posedge pclk_i) begin

        // Kernel Shift Register update
        for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
            for(k_c = 0; k_c < K_WIDTH; k_c = k_c + 1) begin
                ksr[k_r][k_c] <= ksr_next[k_r][k_c];
            end
        end

        // Row Buffer Reset update, most logic is purely combinational
        r_rrst_n <= r_rrst_n_next;
        r_wrst_n <= r_wrst_n_next;

        pointer_separation <= pointer_separation_next;

    end

    ////////////////////////////////////////////////////////////////
    // Buffer Shift Register wiring
    // must be $clog2(WIDTH) + 1 instead of $clog(WIDTH)

    genvar b_row;
    
    generate
        // first buffer entry point
        if(K_HEIGHT > 1) begin
            assign w_wdata[0] = pixel_data_i;    
            async_fifo #(
                .DSIZE(DEPTH),
                .ASIZE($clog2(WIDTH) + 1),
                .FALLTHROUGH("FALSE")
            ) entry_fifo_buffer (
                .wclk(pclk_i), 
                .wrst_n(r_wrst_n),
                .winc(r_wr), 
                .wdata(w_wdata[0]),
                .wfull(w_wfull[0]), 
                .awfull(),

                .rclk(pclk_i), 
                .rrst_n(r_rrst_n),
                .rinc(r_rd), 
                .rdata(w_rdata[0]),
                .rempty(w_rempty[0]), 
                .arempty()
            );
            
        end

        // rest of buffer wiring
        for(b_row = 1; b_row < (K_HEIGHT - 1); b_row = b_row + 1) begin

            // i could have done .w_wdata(r_data[previous]) but
            // I think its much more organized to do it this way
            assign w_wdata[b_row] = w_rdata[b_row - 1];
            async_fifo #(
                .DSIZE(DEPTH),
                .ASIZE($clog2(WIDTH) + 1),
                .FALLTHROUGH("FALSE")
            ) entry_fifo_buffer (
                .wclk(pclk_i), 
                .wrst_n(r_wrst_n),
                .winc(r_wr), 
                .wdata(w_wdata[b_row]),
                .wfull(w_wfull[b_row]), 
                .awfull(),

                .rclk(pclk_i), 
                .rrst_n(r_rrst_n),
                .rinc(r_rd), 
                .rdata(w_rdata[b_row]),
                .rempty(w_rempty[b_row]), 
                .arempty()
            );
        end
    endgenerate

    // what does initializing [7:0] ksr [0][0] mean?
    // should be one row/column index pointing to a single byte
    // and so kernel_o = ksr should work.
    // but for some reason, i have to do it this way for a 1x1 window
    assign kernel_o = ksr;


endmodule

/**
 * This module takes the kernel window,
 * and assigns the given constant value to pixels
 * outside the actual image (constant extension).
 */
module conv_router #(
    // input image dimensions
    parameter WIDTH = 320,
    parameter HEIGHT = 240,

    // input image depth
    parameter DEPTH = 8,

    parameter K_WIDTH = 3,
    parameter K_HEIGHT = 3,

    // Constant value for pixels outside image
    parameter CONSTANT = 0
)  (
    // input kernel window
    input  [(DEPTH-1):0]                        kernel_i  [K_HEIGHT][K_WIDTH],

    // row and column for incoming pixel
    input signed [15:0]  col_i, 
    input signed [15:0]  row_i, 

    // outgoing kernel window with constant extension applied
    output [(DEPTH-1):0]                        kernel_o  [K_HEIGHT][K_WIDTH]
);

    localparam MID_K_H = K_HEIGHT / 2;
    localparam MID_K_W = K_WIDTH / 2;

    ////////////////////////////////////////////////////////////////
    // Wiring constant expression muxes

    // The k window order is actually
    /*
     *  bottom right --------- bottom left
     *               |        |
     *               |        |
     *               |        |
     *  top right    --------- top left
     */
    // so we have to be careful on how to properly index

    logic [DEPTH-1:0] r_kernel [K_HEIGHT][K_WIDTH];

    integer k_col, k_row;
    integer k_c, k_r;
    integer k_c_offset, k_r_offset;
    integer k_r_act, k_c_act;

    always@(*) begin
        for(k_row = 0; k_row < K_HEIGHT; k_row = k_row + 1) begin
            for(k_col = 0; k_col < K_WIDTH; k_col = k_col + 1) begin
                k_c = (K_WIDTH - 1) - k_col + ( (K_WIDTH - 1) % 2);
                k_r = (K_HEIGHT - 1) - k_row + ( (K_HEIGHT - 1) % 2);
                k_c_offset = k_c - MID_K_W;
                k_r_offset = k_r - MID_K_H;
                k_r_act = row_i + k_r_offset;
                k_c_act = col_i + k_c_offset;

                if( (k_c_act >= 0) && (k_c_act < WIDTH) &&
                    (k_r_act >= 0) && (k_r_act < HEIGHT) )
                    r_kernel[k_row][k_col] = kernel_i[k_row][k_col];
                else
                    r_kernel[k_row][k_col] = CONSTANT;

            end
        end
    end

    // see conv_entry_fifo comments at the kernel_o assign
    assign kernel_o = r_kernel;

endmodule

/**
 * Kernel convolution with parameterized cycles so we can perform
 * MAC operations over several cycles to save on resources or 1
 * with maximal resource usage.
 * It also takes in the values to multiply the window with, called
 * kernel coefficients.
 *
 *
 * Parameterized optimization:
 * Pass two hex values for each kernel coefficient to perform
 * optimization. Currently supoprted optionsa are:
 *
 * 00 - no optimization (perform multiply normally)
 * 01 - 0
 * 02 - 1/2
 * 03 - -1/2
 * 04 - 1
 * 05 - -1
 * 06 - 4
 * rest of values are unsupported (same effect as 00)
 *
 * For example, a 3x3 kernel with these values
 * [[0,1,0],[x, 1/2, 1], [x, x, x]]
 * can be optimized as
 * OPTIMIZATION = 72'h01_04_01_00_02_04_00_00_00;
 */

module kernel_convolution #(
    // FP parameters 
    parameter FP_M_IMAGE = 8,
    parameter FP_N_IMAGE = 0,
    parameter FP_S_IMAGE = 0,

    parameter FP_M_KERNEL = 8,
    parameter FP_N_KERNEL = 0,
    parameter FP_S_KERNEL = 0,

    // kernel window dimensions
    parameter K_WIDTH = 3,
    parameter K_HEIGHT = 3,

    // how many cycles do we have per pixel
    parameter CLKS_PER_PIXEL = 1
)  (
    // clock
    input pclk_i,

    // data valid, are we about to shift new values in?
    input dv_i,

    // is the pipe full?
    input ispipefull_i,

    // kernel state and cycle count is managed by the conv_net module
    input                            kernel_state_i,
    input [$clog2(CLKS_PER_PIXEL):0] convolution_step_i,

    // input kernel window
    input  [(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE -1):0] kernel_i [K_HEIGHT][K_WIDTH],

    // input kernel coeffs
    input  [(FP_M_KERNEL + FP_N_KERNEL + FP_S_KERNEL -1):0] kernel_coeffs_i  [K_HEIGHT][K_WIDTH],

    // incoming pipe pixel col and row
    input  [15:0]  col_i, 
    input  [15:0]  row_i, 

    // output using interface
    pixel_data_interface.reader out
);
    // Kernel State for cycles per pixel
    localparam READY = 1'b1;
    localparam BUSY = 1'b0;

    // parallel number of macs to perform, ceiling division 
    localparam PARALLEL_MACS = (((K_WIDTH * K_HEIGHT) % CLKS_PER_PIXEL) != 0) ? 
                               (((K_WIDTH * K_HEIGHT) / CLKS_PER_PIXEL) + 1) : 
                               ((K_WIDTH * K_HEIGHT) / CLKS_PER_PIXEL);

    localparam DEPTH     = FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE;    
    localparam K_DEPTH   = FP_M_KERNEL + FP_N_KERNEL + FP_S_KERNEL;
    localparam TEMP_KC_DEPTH = FP_M_KERNEL + FP_N_KERNEL + 1;
    localparam DEPTH_OUT = out.FP_M + out.FP_N + out.FP_S;

    localparam FP_N_K_0 = FP_N_KERNEL >= 0 ? FP_N_KERNEL : 0;
    localparam FP_N_K_1 = FP_N_KERNEL >= 1 ? FP_N_KERNEL : 1;
    localparam FP_N_K_m2 = FP_N_KERNEL >= -2 ? FP_N_KERNEL : -2;
    localparam FP_M_K_0 = FP_M_KERNEL >= 0 ? FP_M_KERNEL : 0;
    localparam FP_M_K_1 = FP_M_KERNEL >= 1 ? FP_M_KERNEL : 1;

    // output format of calculated result
    localparam FP_MC = FP_M_IMAGE + FP_M_KERNEL + 1 + $clog2(K_WIDTH * K_HEIGHT);
    localparam FP_NC = FP_N_IMAGE + FP_N_KERNEL;
    localparam FP_SC = 1;

    // accumulator bit width
    localparam ACC_DEPTH = FP_MC + FP_NC + FP_SC;

    localparam DEPTH_DIFF = (DEPTH_OUT > ACC_DEPTH) ?
                            (DEPTH_OUT - ACC_DEPTH) :
                            (ACC_DEPTH - DEPTH_OUT);
    
    logic signed [(ACC_DEPTH-1):0] accumulator;
    logic signed [(ACC_DEPTH-1):0] accumulator_next;
    logic signed [(ACC_DEPTH-1):0] accumulator_out;

    // flat kernel window
    logic [0:(K_HEIGHT * K_WIDTH * DEPTH) - 1] kernel_flattened;
    logic signed [(FP_M_IMAGE + FP_N_IMAGE + 1 - 1):0] temp_k;

    // flat kernel coefficients
    logic [0:(K_HEIGHT * K_WIDTH * K_DEPTH)-1] kernel_coeffs_flattened;
    logic signed [(FP_M_KERNEL + FP_N_KERNEL + 1 - 1):0] temp_kc;

    // indexing variables
    integer k_c, k_r, si, si_k, si_k_coeffs, cs, offset_k, offset_k_coeffs;
    integer si_opt, offset_opt; // indexing variable for optimization

    // dv_o state
    logic r_dv_o;
    logic r_dv_o_next;
    
    always@(*) begin
        ////////////////////////////////////////////////////////////////
        // Wiring for flattening kernel window
        for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
            for(k_c = 0; k_c < K_WIDTH; k_c = k_c + 1) begin
                si = (k_r * K_WIDTH * DEPTH) + (k_c * DEPTH);
                kernel_flattened[si +: DEPTH] = kernel_i[k_r][k_c];
            end
        end

        ////////////////////////////////////////////////////////////////
        // Wiring for flattening kernel coefficients
        // bottom/top right/left flip, see conv_router notes
        for(k_r = 0; k_r < K_HEIGHT; k_r = k_r + 1) begin
            for(k_c = 0; k_c < K_WIDTH; k_c = k_c + 1) begin
                si = (k_r * K_WIDTH * K_DEPTH) + (k_c * K_DEPTH);
                kernel_coeffs_flattened[si +: K_DEPTH] = kernel_coeffs_i[(K_HEIGHT - 1) - k_r][(K_WIDTH - 1) - k_c];
            end
        end

        ////////////////////////////////////////////////////////////////
        // Kernel calculations wrt to convolution step
        accumulator_next = 0;
        accumulator_out = accumulator;

        si_k = convolution_step_i * PARALLEL_MACS * DEPTH;
        si_k_coeffs = convolution_step_i * PARALLEL_MACS * K_DEPTH;
        si_opt = convolution_step_i * PARALLEL_MACS * 8;
        temp_k = 0;
        temp_kc = 0;

        for(cs = 0; cs < PARALLEL_MACS; cs = cs + 1) begin
            offset_k = si_k + (cs * DEPTH);
            offset_k_coeffs = si_k_coeffs + (cs * K_DEPTH);
            offset_opt = si_opt + (cs * 8);

            if(offset_k < (K_HEIGHT * K_WIDTH * DEPTH)) begin
                // conversions to signed 
                if(FP_S_IMAGE == 0) begin
                    temp_k = { {1'b0}, kernel_flattened[offset_k +: DEPTH] };
                end else begin
                    temp_k = kernel_flattened[offset_k +: DEPTH];
                end

                if(FP_S_KERNEL == 0) begin
                    temp_kc = { {1'b0}, kernel_coeffs_flattened[offset_k_coeffs +: K_DEPTH]};
                end else begin
                    temp_kc = kernel_coeffs_flattened[offset_k_coeffs +: K_DEPTH];
                end
                
                accumulator_out += (temp_k * temp_kc);  
            end
        end

        case(kernel_state_i)
            READY: begin
                if(dv_i) begin 
                    accumulator_next = 0;
                end else begin 
                    accumulator_next = accumulator;
                end  
            end
            BUSY: begin
                accumulator_next = accumulator_out;
            end
        endcase

        // dv_o logic
        r_dv_o_next = 0;

        if(CLKS_PER_PIXEL == 1) begin
            r_dv_o_next = dv_i;
        end else begin
            if(convolution_step_i == (CLKS_PER_PIXEL - 2)) begin
                r_dv_o_next = 1;
            end
        end

    end

    ////////////////////////////////////////////////////////////////
    // Fixed Point output formatting
    // see FP notes

    // rename
    logic [(ACC_DEPTH-1):0] sqc;
    assign sqc = accumulator_out;

    logic [out.FP_M + out.FP_N + out.FP_S -1:0] r_pixel_data;

    // Had to do this to make the repition multipliers and widths constant
    localparam bit_width_sqc = ACC_DEPTH;
    localparam sext_lhs = (out.FP_M - FP_MC) > 0 ? out.FP_M - FP_MC : 0;
    localparam li       = (out.FP_M - FP_MC) > 0 ? bit_width_sqc - 2 : bit_width_sqc - 2 + (out.FP_M - FP_MC);
    localparam zext_rhs = (out.FP_N - FP_NC) > 0 ? out.FP_N - FP_NC : 0;
    localparam ri       = (out.FP_N - FP_NC) > 0 ? 0 : 0 - (out.FP_N - FP_NC);

    always@(*) begin
        r_pixel_data = 0;

        if((li >= 0) && (ri < (bit_width_sqc - 1))) begin
            if(out.FP_S == 1) begin
                r_pixel_data = { sqc[bit_width_sqc-1], {sext_lhs{sqc[bit_width_sqc-1]}} , sqc[ri +: (li - ri + 1)] , {zext_rhs{1'b0}} };
            end else begin
                r_pixel_data = { {sext_lhs{sqc[bit_width_sqc-1]}} , sqc[ri +: (li - ri + 1)] , {zext_rhs{1'b0}} };
            end

        end else begin
            if(out.FP_S == 1) begin
                if(ri == (bit_width_sqc - 1)) begin
                    r_pixel_data = { {sqc[bit_width_sqc-1]}, {sext_lhs{sqc[bit_width_sqc-1]}} , {zext_rhs{1'b0}} };
                end else begin
                    r_pixel_data = { {1'b0}, {sext_lhs{1'b0}} , {zext_rhs{1'b0}} };
                end
            end else begin
                if(ri == (bit_width_sqc - 1)) begin
                    // hack to get around all zero replications in concat error
                    r_pixel_data = { {1'b0} , {sext_lhs{sqc[bit_width_sqc-1]}} , {zext_rhs{1'b0}} } >> 1;
                end else begin
                    // hack to get around all zero replications in concat error
                    r_pixel_data = { {1'b0} , {sext_lhs{1'b0}} , {zext_rhs{1'b0}} } >> 1;
                end

            end
        end
    end


    // pipe col row is already latched, we don't need to track it

    logic [15:0] row_d;
    logic [15:0] col_d;
    logic valid_d;
    logic [out.FP_M + out.FP_N + out.FP_S-1:0] pixel_d;

    assign col_d = out.col;
    assign row_d = out.row;
    assign valid_d = out.valid;
    assign pixel_d = out.pixel;

    assign out.col = col_i;
    assign out.row = row_i;
    
    // dv_o is simple, if we are in the ready state, dv goes high
    // actually, doing that will cause repeated data, need to be more careful
    assign out.valid = (ispipefull_i == 1) ? r_dv_o : 0;
    
    // pixel out
    assign out.pixel = r_pixel_data;    

    always@(posedge pclk_i) begin
        accumulator <= accumulator_next;
        r_dv_o <= r_dv_o_next;
    end

endmodule





