/*
 * Bilinear Transform Model
 */

class BilinearXformModel #(
    // FP parameters 
    parameter FP_M_IMAGE = 8,
    parameter FP_N_IMAGE = 0,
    parameter FP_S_IMAGE = 0,

    parameter PRECISION = 8,

    parameter WIDTH = 100,
    parameter HEIGHT = 100
);

    TriggerableQueue#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) input_queue;
    TriggerableQueueBroadcaster#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) output_queue;
    TriggerableQueue#(error_info_t) errors;
    int unique_matrix = 0;
    string filename = "";


    function new(TriggerableQueueBroadcaster#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) image_source,
                 TriggerableQueue#(error_info_t) errors);
        this.input_queue = new();
        this.output_queue = new();

        image_source.add_queue(this.input_queue);

        this.errors = errors;
    endfunction

    function automatic DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)
        bilinear_xform_passthrough(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im);

        DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) out;

        out = new(im.width, im.height); 

        // Iterate over each pixel in the input image
        for (int y = 0; y < im.height; y++) begin
            for (int x = 0; x < im.width; x++) begin
                out.image[y][x] = im.image[y][x];
            end
        end
        

        return out;
    endfunction

    function automatic DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)
        bilinear_xform_lookup(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im);

        DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) out;

        localparam PRECISION_S = PRECISION + 1;

        // setup look up table here to perform reverse mapping
        logic [15:0] r_row_int_xform_mem [WIDTH * HEIGHT];
        logic [15:0] r_col_int_xform_mem [WIDTH * HEIGHT];
        logic [15:0] r_row_frac_xform_mem [WIDTH * HEIGHT];
        logic [15:0] r_col_frac_xform_mem [WIDTH * HEIGHT];

        logic [15:0] row_int_xform;
        logic [15:0] row_frac_xform;
        logic [15:0] col_int_xform;
        logic [15:0] col_frac_xform;
        
        ////////////////////////////////////////////////////////////////
        // variables to perform calculations and intermediates
        // description of variables can be found in the bilinear_interpolator
        // module
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q11;
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q21;
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q12;
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q22;

        // assumed to be signed
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q11_;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q21_;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q12_;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q22_;

        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qtop;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qbot;

        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE -1:0] Qfinal;

        // signed fractional parts (by appending 0)
        logic signed [PRECISION_S-1:0] row_frac_xform_pipe_2_im_0;
        logic signed [PRECISION_S-1:0] col_frac_xform_pipe_1_im_0;

        // logic for calculations and intermediate values
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]                   Qtop_im_0;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]     Qtop_im_1;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 + 1 -1:0] Qtop_im_2;
        logic signed [PRECISION + FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qtop_im_pad;

        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]                   Qbot_im_0;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]     Qbot_im_1;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 + 1 -1:0] Qbot_im_2;
        logic signed [PRECISION + FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qbot_im_pad;

        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]                   Qfinal_im_0;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]     Qfinal_im_1;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 + 1 -1:0] Qfinal_im_2;
        logic signed [PRECISION + FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qfinal_im_pad;

        out = new(im.width, im.height);

        // reading in transformed coordinates
        $readmemb("../test_transformations/general_100_100_row_int.txt", r_row_int_xform_mem);
        $readmemb("../test_transformations/general_100_100_row_frac.txt", r_row_frac_xform_mem);
        $readmemb("../test_transformations/general_100_100_col_int.txt", r_col_int_xform_mem);
        $readmemb("../test_transformations/general_100_100_col_frac.txt", r_col_frac_xform_mem);
        

        // Iterate over each pixel in the input image
        for (int y = 0; y < im.height; y++) begin
            for (int x = 0; x < im.width; x++) begin
                // reverse map 
                row_int_xform = r_row_int_xform_mem[(y * im.width) + x];
                row_frac_xform = r_row_frac_xform_mem[(y * im.width) + x];
                col_int_xform = r_col_int_xform_mem[(y * im.width) + x];
                col_frac_xform = r_col_frac_xform_mem[(y * im.width) + x];

                // grab Q** values
                Q11 = 0;
                Q21 = 0;
                Q12 = 0;
                Q22 = 0;

                if((row_int_xform >= 0) && (row_int_xform < im.height) && (col_int_xform >= 0) && (col_int_xform < im.width)) begin
                    Q11 = im.image[row_int_xform][col_int_xform];
                    if((row_int_xform >= 0) && (row_int_xform < im.height) && ((col_int_xform+1) >= 0) && ((col_int_xform+1) < im.width)) begin
                        Q21 = im.image[row_int_xform][col_int_xform+1];
                    end
                    if(((row_int_xform+1) >= 0) && ((row_int_xform+1) < im.height) && (col_int_xform >= 0) && (col_int_xform < im.width)) begin
                        Q12 = im.image[row_int_xform+1][col_int_xform];
                    end
                    if(((row_int_xform+1) >= 0) && ((row_int_xform+1) < im.height) && ((col_int_xform+1) >= 0) && ((col_int_xform+1) < im.width)) begin
                        Q22 = im.image[row_int_xform+1][col_int_xform+1];
                    end
                end

                if(FP_S_IMAGE == 0) begin
                    Q11_ = {{1'b0}, Q11};
                    Q21_ = {{1'b0}, Q21};
                    Q12_ = {{1'b0}, Q12};
                    Q22_ = {{1'b0}, Q22};
                end 

                // bilinear interpolate
                ////////////////////////////////////////////////////////////////
                // In STAGE 1 calculations
                // Qtop = Q11 + xf * (Q21 - Q11)
                col_frac_xform_pipe_1_im_0 = {{1'b0},col_frac_xform};

                Qtop_im_0 = Q21_ - Q11_;
                Qtop_im_1 = col_frac_xform_pipe_1_im_0 * Qtop_im_0;
                Qtop_im_pad = {Q11_, {PRECISION{1'b0}}};
                Qtop_im_2 = Qtop_im_pad + Qtop_im_1;
                Qtop = Qtop_im_2[FP_M_IMAGE + FP_N_IMAGE + 1 - 1 + PRECISION: PRECISION];

                // Qbot = Q12 + xf * (Q22 - Q12)
                Qbot_im_0 = Q22_ - Q12_;
                Qbot_im_1 = col_frac_xform_pipe_1_im_0 * Qbot_im_0;
                Qbot_im_pad = {Q12_, {PRECISION{1'b0}}};
                Qbot_im_2 = Qbot_im_pad + Qbot_im_1;
                Qbot = Qbot_im_2[FP_M_IMAGE + FP_N_IMAGE + 1 - 1 + PRECISION: PRECISION];

                ////////////////////////////////////////////////////////////////
                // STAGE 2 calculations
                // Qfinal = Qtop + yf(Qbot - Qtop)
                row_frac_xform_pipe_2_im_0 = {{1'b0},row_frac_xform};

                Qfinal_im_0 = Qbot - Qtop;
                Qfinal_im_1 = row_frac_xform_pipe_2_im_0 * Qfinal_im_0;
                Qfinal_im_pad = {Qtop, {PRECISION{1'b0}}};
                Qfinal_im_2 = Qfinal_im_pad + Qfinal_im_1;
                Qfinal = Qfinal_im_2[FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE - 1 + PRECISION: PRECISION];
                
                // set result
                out.image[y][x] = Qfinal;
            end
        end
        

        return out;
    endfunction

    function automatic DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)
        bilinear_xform_true(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im);

        DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) out;

        localparam PRECISION_S = PRECISION + 1;

        // input data
        logic [15:0] row_int_xform;
        logic [15:0] row_frac_xform;
        logic [15:0] col_int_xform;
        logic [15:0] col_frac_xform;

        ////////////////////////////////////////////////////////////////
        // variables to perform reverse mapping,
        // description of variables can be found in the reverse_mapper
        // module
        
        // accumulator
        logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_row;
        logic signed [4 + 11 + 11 + PRECISION - 1:0] acc_col;

        // eplicitly stating subscripts as signed
        logic [15:0] r_row;
        logic [15:0] r_col;
        logic signed [10:0] r_row_11bit;
        logic signed [10:0] r_col_11bit;

        // matrix, read matrix values then linear -> 2D
        logic signed [11+PRECISION-1:0] matrix_linear [9];
        logic signed [11+PRECISION-1:0] matrix [3][3];

        ////////////////////////////////////////////////////////////////
        // variables to perform calculations and intermediates
        // description of variables can be found in the bilinear_interpolator
        // module
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q11;
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q21;
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q12;
        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE-1:0] Q22;

        // assumed to be signed
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q11_;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q21_;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q12_;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1-1:0] Q22_;

        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qtop;
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 -1:0] Qbot;

        logic [FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE -1:0] Qfinal;

        // signed fractional parts (by appending 0)
        logic signed [PRECISION_S-1:0] row_frac_xform_pipe_2_im_0;
        logic signed [PRECISION_S-1:0] col_frac_xform_pipe_1_im_0;

        // logic for calculations and intermediate values
        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]                   Qtop_im_0;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]     Qtop_im_1;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 + 1 -1:0] Qtop_im_2;

        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]                   Qbot_im_0;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]     Qbot_im_1;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 + 1 -1:0] Qbot_im_2;

        logic signed [FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]                   Qfinal_im_0;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 -1:0]     Qfinal_im_1;
        logic signed [PRECISION_S + FP_M_IMAGE + FP_N_IMAGE + 1 + 1 + 1 -1:0] Qfinal_im_2;

        out = new(im.width, im.height);

        // read matrix values
        if(this.unique_matrix == 0) begin
            $readmemb("../test_transformations/general_matrix.txt", matrix_linear);
        end else begin
            $readmemb(this.filename, matrix_linear);
        end

        // linear -> 2D
        for(int y = 0; y < 3; y++) begin
            for(int x = 0; x < 3; x++) begin
                matrix[y][x] = matrix_linear[(y*3) + x];
            end
        end

        // Iterate over each pixel in the input image
        for (int y = 0; y < im.height; y++) begin
            for (int x = 0; x < im.width; x++) begin
                
                // grab data
                r_row = y;
                r_col = x;
                r_row_11bit = r_row[10:0];
                r_col_11bit = r_col[10:0];

                // reverse map
                acc_col = 0;
                acc_row = 0;
                acc_col += (matrix[0][0] * r_col_11bit);
                acc_col += (matrix[0][1] * r_row_11bit);
                acc_col += {{15{matrix[0][2][11+PRECISION-1]}}, matrix[0][2]};
                acc_row += (matrix[1][0] * r_col_11bit);
                acc_row += (matrix[1][1] * r_row_11bit);
                acc_row += {{15{matrix[1][2][11+PRECISION-1]}}, matrix[1][2]};

                row_int_xform = acc_row[16 + PRECISION-1:PRECISION];
                row_frac_xform = acc_row[PRECISION-1:0];
                col_int_xform = acc_col[16 + PRECISION-1:PRECISION];
                col_frac_xform = acc_col[PRECISION-1:0];
                
                // grab Q** values
                Q11 = 0;
                Q21 = 0;
                Q12 = 0;
                Q22 = 0;

                if((row_int_xform >= 0) && (row_int_xform < im.height) && (col_int_xform >= 0) && (col_int_xform < im.width)) begin
                    Q11 = im.image[row_int_xform][col_int_xform];
                    if((row_int_xform >= 0) && (row_int_xform < im.height) && ((col_int_xform+1) >= 0) && ((col_int_xform+1) < im.width)) begin
                        Q21 = im.image[row_int_xform][col_int_xform+1];
                    end
                    if(((row_int_xform+1) >= 0) && ((row_int_xform+1) < im.height) && (col_int_xform >= 0) && (col_int_xform < im.width)) begin
                        Q12 = im.image[row_int_xform+1][col_int_xform];
                    end
                    if(((row_int_xform+1) >= 0) && ((row_int_xform+1) < im.height) && ((col_int_xform+1) >= 0) && ((col_int_xform+1) < im.width)) begin
                        Q22 = im.image[row_int_xform+1][col_int_xform+1];
                    end
                end
                
                if(FP_S_IMAGE == 0) begin
                    Q11_ = {{1'b0}, Q11};
                    Q21_ = {{1'b0}, Q21};
                    Q12_ = {{1'b0}, Q12};
                    Q22_ = {{1'b0}, Q22};
                end else begin
                    Q11_ = Q11;
                    Q21_ = Q21;
                    Q12_ = Q12;
                    Q22_ = Q22;
                end
            
                // bilinear interpolate
                ////////////////////////////////////////////////////////////////
                // In STAGE 1 calculations
                // Qtop = Q11 + xf * (Q21 - Q11)
                col_frac_xform_pipe_1_im_0 = {{1'b0},col_frac_xform};

                Qtop_im_0 = Q21_ - Q11_;
                Qtop_im_1 = col_frac_xform_pipe_1_im_0 * Qtop_im_0;
                Qtop_im_2 = {Q11_, {PRECISION{1'b0}}} + Qtop_im_1;
                Qtop = Qtop_im_2[FP_M_IMAGE + FP_N_IMAGE + 1 - 1 + PRECISION: PRECISION];

                // Qbot = Q12 + xf * (Q22 - Q12)
                Qbot_im_0 = Q22_ - Q12_;
                Qbot_im_1 = col_frac_xform_pipe_1_im_0 * Qbot_im_0;
                Qbot_im_2 = {Q12_, {PRECISION{1'b0}}} + Qbot_im_1;
                Qbot = Qbot_im_2[FP_M_IMAGE + FP_N_IMAGE + 1 - 1 + PRECISION: PRECISION];

                ////////////////////////////////////////////////////////////////
                // STAGE 2 calculations
                // Qfinal = Qtop + yf(Qbot - Qtop)
                row_frac_xform_pipe_2_im_0 = {{1'b0},row_frac_xform};

                Qfinal_im_0 = Qbot - Qtop;
                Qfinal_im_1 = row_frac_xform_pipe_2_im_0 * Qfinal_im_0;
                Qfinal_im_2 = {Qtop, {PRECISION{1'b0}}} + Qfinal_im_1;
                Qfinal = Qfinal_im_2[FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE - 1 + PRECISION: PRECISION];
                
                // set result
                out.image[y][x] = Qfinal;
            end
        end

        return out;
    endfunction


    task automatic run();
        forever begin
            DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_in;
            DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_out;
            this.input_queue.pop(im_in);

            im_out = this.bilinear_xform_true(im_in);

            this.output_queue.push(im_out);
        end
    endtask
endclass