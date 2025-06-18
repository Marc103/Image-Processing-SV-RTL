/**
 * Divisor Model
 */

 class DivisorModel #(
    // FP parameters 
    parameter FP_M_IMAGE = 8,
    parameter FP_N_IMAGE = 0,
    parameter FP_S_IMAGE = 1,

    parameter FP_M_OUT = 8,
    parameter FP_N_OUT = 0,
    parameter FP_S_OUT = 1
);
    localparam A_WIDTH = FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE;
    localparam B_WIDTH = A_WIDTH;
    localparam Q_LENGTH = FP_M_OUT + FP_N_OUT + FP_S_OUT - 1;
    localparam Q_M = Q_LENGTH - 1;

    TriggerableQueue#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) input_queue_0;
    TriggerableQueue#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) input_queue_1;
    TriggerableQueueBroadcaster#(DigitalImage#(FP_M_OUT + FP_N_OUT + FP_S_OUT)) output_queue;
    TriggerableQueue#(error_info_t) errors;

    function new(TriggerableQueueBroadcaster#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) image_source_0,
                 TriggerableQueueBroadcaster#(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)) image_source_1,
                 TriggerableQueue#(error_info_t) errors);
        this.input_queue_0 = new();
        this.input_queue_1 = new();
        this.output_queue = new();

        image_source_0.add_queue(this.input_queue_0);
        image_source_1.add_queue(this.input_queue_1);

        this.errors = errors;
    endfunction

    function automatic DigitalImage#(FP_M_OUT + FP_N_OUT + FP_S_OUT)
        divide(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_0,
                       DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_1);

        DigitalImage#(FP_M_OUT + FP_N_OUT + FP_S_OUT) out;

        out = new (im_0.width, im_0.height);
    
        for (int y = 0; y < im_0.height; y++) begin
            for (int x = 0; x < im_0.width; x++) begin
                reg        [A_WIDTH - 1+FP_N_OUT:0] a_unsigned = 0;
                reg        [B_WIDTH - 1:0] b_unsigned = im_1.image[y][x];
                reg        [Q_LENGTH:0] result;

                bit a_s = 0;
                bit b_s = 0;
                a_unsigned[A_WIDTH-1:0] = im_0.image[y][x];
                
                if((FP_S_IMAGE == 1) && (a_unsigned[A_WIDTH - 1] == 1)) begin
                    a_unsigned = ~a_unsigned + 1;
                    a_s = 1;
                end
                if((FP_S_IMAGE == 1) && (b_unsigned[B_WIDTH - 1] == 1)) begin
                    b_unsigned = ~b_unsigned + 1;
                    b_s = 1;
                end
                a_unsigned = a_unsigned << FP_N_OUT;
                result = a_unsigned / b_unsigned;
                if(((FP_S_IMAGE == 1) && a_s) ^ ((FP_S_IMAGE == 1) && b_s)) begin
                    result = ~result + 1;
                end
                out.image[y][x] = result;
                if(b_unsigned == 0) begin
                    if(a_s == 1) begin
                        out.image[y][x] = {{1'b1}, {Q_M{1'b0}}, {1'b1}};
                    end else begin
                        out.image[y][x] = {{1'b0}, {Q_LENGTH{1'b1}}};
                    end
                end
                 
            end
        end
        /*
        $display("Divided");
        $display(out.image);
        */
        return out;
    endfunction


    function automatic DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE)
        divide_passthrough(DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_0,
                                   DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_1);

        DigitalImage#(FP_M_OUT + FP_N_OUT + FP_S_OUT) out;
        out = new(im_0.width, im_0.height);

        // Iterate over each pixel in the input image
        for (int y = 0; y < im_0.height; y++) begin
            for (int x = 0; x < im_0.width; x++) begin
                out.image[y][x] = 0;
            end
        end
        
        return out;
    endfunction

    task automatic run();
        forever begin
            DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_0;
            DigitalImage#(FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE) im_1;
            DigitalImage#(FP_M_OUT + FP_N_OUT + FP_S_OUT) im_out;
            this.input_queue_0.pop(im_0);
            this.input_queue_1.pop(im_1);

            im_out = this.divide(im_0, im_1);

            this.output_queue.push(im_out);
        end
    endtask
    
endclass