/**
 * Convolution Model
 */
class ConvolutionModel #(
    // FP parameters
    parameter FP_M_IMAGE = 8,
    parameter FP_N_IMAGE = 0,
    parameter FP_S_IMAGE = 0,

    parameter FP_M_KERNEL = 8,
    parameter FP_N_KERNEL = 0,
    parameter FP_S_KERNEL = 0,

    parameter FP_M_IMAGE_OUT = 16,
    parameter FP_N_IMAGE_OUT = -8,
    parameter FP_S_IMAGE_OUT = 0,

    parameter KERNEL_WIDTH = 3,
    parameter KERNEL_HEIGHT = 3
);

    localparam DEPTH     = FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE;
    localparam K_DEPTH   = FP_M_KERNEL + FP_N_KERNEL + FP_S_KERNEL;
    localparam DEPTH_OUT = FP_M_IMAGE_OUT + FP_N_IMAGE_OUT + FP_S_IMAGE_OUT;

    // output format of calculated result
    localparam FP_MC = FP_M_IMAGE + FP_M_KERNEL + 1 + $clog2(KERNEL_WIDTH * KERNEL_HEIGHT) ;
    localparam FP_NC = FP_N_IMAGE + FP_N_KERNEL;
    localparam FP_SC = 1;

    /// accumulator bit width
    localparam ACC_DEPTH = FP_MC + FP_NC + FP_SC;

    localparam DEPTH_DIFF = (DEPTH_OUT > ACC_DEPTH) ?
                            (DEPTH_OUT - ACC_DEPTH) :
                            (ACC_DEPTH - DEPTH_OUT);

    TriggerableQueue#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) input_queue;
    TriggerableQueueBroadcaster#(DigitalImage#(DEPTH_OUT)) output_queue;
    TriggerableQueue#(error_info_t) errors;

    /// convolutional kernel to be set by user code
    DigitalImage#(FP_M_KERNEL + FP_N_KERNEL + FP_S_KERNEL) kernel;

    function new(TriggerableQueueBroadcaster#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) image_source,
                 TriggerableQueue#(error_info_t) errors);
        this.input_queue = new();
        this.output_queue = new();

        image_source.add_queue(this.input_queue);

        this.errors = errors;
    endfunction

    function automatic DigitalImage#(FP_M_IMAGE_OUT + FP_N_IMAGE_OUT + FP_S_IMAGE_OUT)
        convolve(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im);
        int k_mid_x = kernel.width / 2;
        int k_mid_y = kernel.height / 2;
        int k_x_adj = (kernel.width + 1) % 2;
        int k_y_adj = (kernel.height + 1) % 2;

        bit do_display;

        // Had to do this to make the repition multipliers and widths constant
        localparam bit_width_sqc = ACC_DEPTH;
        localparam sext_lhs = (FP_M_IMAGE_OUT - FP_MC) > 0 ? FP_M_IMAGE_OUT - FP_MC : 0;
        localparam li       = (FP_M_IMAGE_OUT - FP_MC) > 0 ? bit_width_sqc - 2 : bit_width_sqc - 2 + (FP_M_IMAGE_OUT - FP_MC);
        localparam zext_rhs = (FP_N_IMAGE_OUT - FP_NC) > 0 ? FP_N_IMAGE_OUT - FP_NC : 0;
        localparam ri       = (FP_N_IMAGE_OUT - FP_NC) > 0 ? 0 : 0 - (FP_N_IMAGE_OUT - FP_NC);

        DigitalImage#(DEPTH_OUT) out;

        out = new(im.width, im.height);

        // Iterate over each pixel in the input image
        for (int y = 0; y < im.height; y++) begin
            reg signed [(ACC_DEPTH-1):0] sqc = 0;
            reg signed [(FP_M_IMAGE + FP_N_IMAGE + 1 - 1):0] temp_k;
            reg signed [(FP_M_KERNEL + FP_N_KERNEL + 1 - 1):0] temp_kc;

            for (int x = 0; x < im.width; x++) begin
                //do_display = ((x >= 25) && (x < 40) && (y >= 35) && (y < 50));
                do_display = 0;
                sqc = 0;
                // Iterate over each pixel in the kernel
                for (int ky = 0; ky < kernel.height; ky++) begin
                    for (int kx = 0; kx < kernel.width; kx++) begin
                        // Calculate the corresponding pixel in the input image
                        int ix = x + kx - k_mid_x + k_x_adj;
                        int iy = y + ky - k_mid_y + k_y_adj;

                        // Ensure the kernel does not go out of bounds
                        if ((ix >= 0) && (ix < im.width) && (iy >= 0) && (iy < im.height)) begin
                            // conversions to signed
                            if(FP_S_IMAGE == 0) begin
                                temp_k = { {1'b0}, im.image[iy][ix] };
                            end else begin
                                temp_k = im.image[iy][ix];
                            end

                            if(FP_S_KERNEL == 0) begin
                                temp_kc = { {1'b0}, kernel.image[ky][kx]};
                            end else begin
                                temp_kc = kernel.image[ky][kx];
                            end

                            // Accumulate the sum of the products
                            sqc += temp_k * temp_kc;

                            if (do_display)
                              $display("temp_pix = %04x, temp_kern = %04x, accum = %08x", temp_k, temp_kc, sqc);
                        end
                    end
                end
                if((li >= 0) && (ri < (bit_width_sqc - 1))) begin
                    if(FP_S_IMAGE_OUT == 1) begin
                        out.image[y][x] = { sqc[bit_width_sqc-1], {sext_lhs{sqc[bit_width_sqc-1]}} , sqc[ri +: (li - ri + 1)] , {zext_rhs{1'b0}} };
                    end else begin
                        out.image[y][x] = { {sext_lhs{sqc[bit_width_sqc-1]}} , sqc[ri +: (li - ri + 1)] , {zext_rhs{1'b0}} };
                    end

                end else begin
                    if(FP_S_IMAGE_OUT == 1) begin
                        if(ri == (bit_width_sqc - 1)) begin
                            out.image[y][x] = { {sqc[bit_width_sqc-1]}, {sext_lhs{sqc[bit_width_sqc-1]}} , {zext_rhs{1'b0}} };
                        end else begin
                            out.image[y][x] = { {1'b0}, {sext_lhs{1'b0}} , {zext_rhs{1'b0}} };
                        end
                    end else begin
                        if(ri == (bit_width_sqc - 1)) begin
                            // hack to get around all zero replications in concat error
                            out.image[y][x] = { {1'b0} ,{sext_lhs{sqc[bit_width_sqc-1]}} , {zext_rhs{1'b0}} } >> 1;
                        end else begin
                            // hack to get around all zero replications in concat error
                            out.image[y][x] = { {1'b0} ,{sext_lhs{1'b0}} , {zext_rhs{1'b0}} } >> 1;
                        end

                    end
                end

                if (do_display) $display("@(%4d, %4d):  sqc_final = %08x ----> resultpix = %08x", x, y, sqc, out.image[y][x]);
                //$display("IN: %b | KERN: %b | OUT: %b", im.image[y][x], temp_k, out.image[y][x]);
            end
        end


        return out;
    endfunction

    task automatic run();
        forever begin
            DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_in;
            DigitalImage#(FP_M_IMAGE_OUT + FP_N_IMAGE_OUT + FP_S_IMAGE_OUT) im_out;
            this.input_queue.pop(im_in);

            im_out = this.convolve(im_in);

            this.output_queue.push(im_out);
        end
    endtask
endclass
