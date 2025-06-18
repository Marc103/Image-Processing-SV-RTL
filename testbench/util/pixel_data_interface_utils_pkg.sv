`timescale 1ns/10ps

`include "common/pixel_data_interface.svh"

package pixel_data_interface_utils_pkg;
    import triggerable_queue_pkg::*;
    import testbench_common_pkg::*;
    import testbench_util_pkg::*;
    import camera_simulation_pkg::*;

    /**
     * Given items from a DigitalImage queue, drives a pixel_data_interface according to the
     * items in the queue
     */

    // for all parameter descriptions, see pixel_data_interface.svh

    class DigitalImageDriver #(parameter FP_M = 8, parameter FP_N = 0, parameter FP_S = 0);
        localparam BIT_DEPTH = FP_M + FP_N + FP_S;

        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) input_queue;
        virtual pixel_data_interface #(
            .FP_M(FP_M),
            .FP_N(FP_N),
            .FP_S(FP_S)
        ) vif_out;

        // Once every how many cycles should a pixel arrive?
        // can be manually adjusted by user code.
        int pixel_cadence = 1;

        // Minimum delay between images
        int minimum_inter_image_delay = 500;

        function new(TriggerableQueueBroadcaster #(DigitalImage#(BIT_DEPTH)) image_source, 
                     virtual pixel_data_interface #(
                        .FP_M(FP_M),
                        .FP_N(FP_N),
                        .FP_S(FP_S)
                     ) vif_out);

            // Initialize the input queue and register it with the image source
            this.input_queue = new();
            image_source.add_queue(this.input_queue);

            // Store the virtual interface
            this.vif_out = vif_out;
        endfunction

        task automatic invalidate_vif_out();
            this.vif_out.pixel <= 'x;
            this.vif_out.row <= 'x;
            this.vif_out.col <= 'x;
            this.vif_out.valid <= 0;
        endtask

        task automatic run();
            DigitalImage#(BIT_DEPTH) im;
            this.invalidate_vif_out();


            forever begin
                // Wait for an image to be popped from the input queue
                this.input_queue.pop(im);

                // Drive the pixel data onto the interface
                for (int y = 0; y < im.height; y++) begin
                    for (int x = 0; x < im.width; x++) begin
                        
                        // Drive pixel data onto the interface
                        @(posedge this.vif_out.clk);

                        this.vif_out.pixel <= im.image[y][x];
                        this.vif_out.row   <= y;
                        this.vif_out.col   <= x;
                        this.vif_out.valid <= 1;

                        // wait for inter-pixel spacing
                        for (int i = 1; i < this.pixel_cadence; i++) begin
                            @(posedge vif_out.clk);
                            this.invalidate_vif_out();
                        end
                    end
                end

                // Mark the data as invalid when the image is fully sent
                @(posedge this.vif_out.clk);
                this.invalidate_vif_out();

                repeat (this.minimum_inter_image_delay) @(posedge vif_out.clk);
            end
        endtask
    endclass
    
    /*
     * Same as DigitalDriver, accepts a fixed size array of image sources and interfaces.
     * Drives the interfaces synchronously. 
     * Assumed that all image dimensions and FP params are equal. Number of sources/infs
     * is determined by 'SIZE' parameter
     */
    class DigitalImageDriverMany #(parameter FP_M = 8, parameter FP_N = 0, parameter FP_S = 0, parameter SIZE = 1);
        localparam BIT_DEPTH = FP_M + FP_N + FP_S;

        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) input_queues [SIZE];

        virtual pixel_data_interface #(
            .FP_M(FP_M),
            .FP_N(FP_N),
            .FP_S(FP_S)
        ) vif_outs [SIZE];

        // Once every how many cycles should a pixel arrive?
        // can be manually adjusted by user code.
        int pixel_cadence = 1;

        // Minimum delay between images
        int minimum_inter_image_delay = 500;

        function new(TriggerableQueueBroadcaster #(DigitalImage#(BIT_DEPTH)) image_sources [SIZE],
                     virtual pixel_data_interface #(
                        .FP_M(FP_M),
                        .FP_N(FP_N),
                        .FP_S(FP_S)
                     ) vif_outs [SIZE]);


            // Initialize input queues 
            for(int i = 0; i < SIZE; i += 1) begin
                this.input_queues[i] = new();  
            end
            
            // register image source to input queues
            for(int i = 0; i < SIZE; i += 1) begin
                image_sources[i].add_queue(this.input_queues[i]);
            end

            // store vinf handles
            for(int i = 0; i < SIZE; i += 1) begin
                this.vif_outs[i] = vif_outs[i];
            end

        endfunction

        task automatic invalidate_vif_outs();
            for(int i = 0; i < SIZE; i += 1) begin
                this.vif_outs[i].pixel <= 'x;
                this.vif_outs[i].row <= 'x;
                this.vif_outs[i].col <= 'x;
                this.vif_outs[i].valid <= 0;
            end
        endtask

    
        task automatic run();
            DigitalImage#(BIT_DEPTH) im [SIZE];

            this.invalidate_vif_outs;

            forever begin
                // Wait for all images to be popped from all queues
                for(int i = 0; i < SIZE; i += 1) begin
                    this.input_queues[i].pop(im[i]);
                end

                // Drive the pixel data onto the interface
                for (int y = 0; y < im[0].height; y++) begin
                    for (int x = 0; x < im[0].width; x++) begin
                        
                        // Drive pixel data onto the interface
                        @(posedge this.vif_outs[0].clk);
                        for(int k = 0; k < SIZE; k += 1) begin
                            this.vif_outs[k].pixel <= im[k].image[y][x];
                            this.vif_outs[k].row   <= y;
                            this.vif_outs[k].col   <= x;
                            this.vif_outs[k].valid <= 1;
                        end

                        // wait for inter-pixel spacing
                        for (int i = 1; i < this.pixel_cadence; i++) begin
                            @(posedge vif_outs[0].clk);
                            this.invalidate_vif_outs();
                        end
                    end
                end

                // Mark the data as invalid when the image is fully sent
                @(posedge this.vif_outs[0].clk);
                this.invalidate_vif_outs();

                repeat (this.minimum_inter_image_delay) @(posedge vif_outs[0].clk);
            end
        endtask
    endclass

    /*
     * Same as DigitalDriver, except it accepts two image sources and drives two interfaces
     * synchronously. Assumed that all image dimensions between the two image sources are equal.
     */
    class DigitalImageDriverDual #(parameter FP_M = 8, parameter FP_N = 0, parameter FP_S = 0);
        localparam BIT_DEPTH = FP_M + FP_N + FP_S;

        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) input_queue_0;
        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) input_queue_1;

        virtual pixel_data_interface #(
            .FP_M(FP_M),
            .FP_N(FP_N),
            .FP_S(FP_S)
        ) vif_out_0;

        virtual pixel_data_interface #(
            .FP_M(FP_M),
            .FP_N(FP_N),
            .FP_S(FP_S)
        ) vif_out_1;

        // Once every how many cycles should a pixel arrive?
        // can be manually adjusted by user code.
        int pixel_cadence = 1;

        // Minimum delay between images
        int minimum_inter_image_delay = 500;

        function new(TriggerableQueueBroadcaster #(DigitalImage#(BIT_DEPTH)) image_source_0, 
                     TriggerableQueueBroadcaster #(DigitalImage#(BIT_DEPTH)) image_source_1,
                     virtual pixel_data_interface #(
                        .FP_M(FP_M),
                        .FP_N(FP_N),
                        .FP_S(FP_S)
                     ) vif_out_0,
                     virtual pixel_data_interface #(
                        .FP_M(FP_M),
                        .FP_N(FP_N),
                        .FP_S(FP_S)
                     ) vif_out_1);

            // Initialize the input queue and register it with the image source
            this.input_queue_0 = new();
            image_source_0.add_queue(this.input_queue_0);

            this.input_queue_1 = new();
            image_source_1.add_queue(this.input_queue_1);

            // Store the virtual interface
            this.vif_out_0 = vif_out_0;
            this.vif_out_1 = vif_out_1;
        endfunction

        task automatic invalidate_vif_out_0();
            this.vif_out_0.pixel <= 'x;
            this.vif_out_0.row <= 'x;
            this.vif_out_0.col <= 'x;
            this.vif_out_0.valid <= 0;
        endtask

        task automatic invalidate_vif_out_1();
            this.vif_out_1.pixel <= 'x;
            this.vif_out_1.row <= 'x;
            this.vif_out_1.col <= 'x;
            this.vif_out_1.valid <= 0;
        endtask

        task automatic run();
            DigitalImage#(BIT_DEPTH) im_0;
            DigitalImage#(BIT_DEPTH) im_1;
            this.invalidate_vif_out_0();
            this.invalidate_vif_out_1();


            forever begin
                // Wait for an image to be popped from both input queues
                this.input_queue_0.pop(im_0);
                this.input_queue_1.pop(im_1);

                // Drive the pixel data onto the interface
                for (int y = 0; y < im_0.height; y++) begin
                    for (int x = 0; x < im_0.width; x++) begin
                        
                        // Drive pixel data onto the interface
                        @(posedge this.vif_out_0.clk);

                        this.vif_out_0.pixel <= im_0.image[y][x];
                        this.vif_out_0.row   <= y;
                        this.vif_out_0.col   <= x;
                        this.vif_out_0.valid <= 1;

                        this.vif_out_1.pixel <= im_1.image[y][x];
                        this.vif_out_1.row   <= y;
                        this.vif_out_1.col   <= x;
                        this.vif_out_1.valid <= 1;

                        // wait for inter-pixel spacing
                        for (int i = 1; i < this.pixel_cadence; i++) begin
                            @(posedge vif_out_0.clk);
                            this.invalidate_vif_out_0();
                            this.invalidate_vif_out_1();
                        end
                    end
                end

                // Mark the data as invalid when the image is fully sent
                @(posedge this.vif_out_0.clk);
                this.invalidate_vif_out_0();
                this.invalidate_vif_out_1();

                repeat (this.minimum_inter_image_delay) @(posedge vif_out_0.clk);
            end
        endtask
    endclass

    /**
     * Monitors a pixel_data_interface and puts resulting images into a queue.
     */
    class PixelDataInterfaceMonitor #(parameter FP_M = 8, parameter FP_N = 0, parameter FP_S = 0);
        localparam BIT_DEPTH = FP_M + FP_N + FP_S;
        
        TriggerableQueueBroadcaster#(DigitalImage#(BIT_DEPTH)) output_queue;
        virtual pixel_data_interface #(
            .FP_M(FP_M),
            .FP_N(FP_N),
            .FP_S(FP_S)
        ) vif;

        // Pre-allocated storage for a maximum-sized image (2048 x 2048)
        logic [BIT_DEPTH-1:0] image_storage[2048][2048];
        int max_width = 0;
        int max_height = 0;

        function new(virtual pixel_data_interface #(
            .FP_M(FP_M),
            .FP_N(FP_N),
            .FP_S(FP_S)
        ) vif);

            // Initialize the output queue
            this.output_queue = new();
            // Store the virtual interface
            this.vif = vif;
        endfunction

        task automatic run();
            DigitalImage#(BIT_DEPTH) im = null;
            int current_row = 0;

            int prev_detect = 0;
            int prev_row = 0;
            int prev_col = 0;

            forever begin
                // Wait for valid data on the interface
                @(posedge vif.clk);
                if (vif.valid) begin
                    // Track the maximum row and column encountered
                    if (vif.row >= max_height) max_height = vif.row + 1;
                    if (vif.col >= max_width) max_width = vif.col + 1;

                    // Warn for repeated data
                    if(prev_detect == 0) begin
                        prev_detect = 1;
                        prev_row = vif.row;
                        prev_col = vif.col;
                    end else begin
                        if((prev_row == vif.row) && (prev_col == vif.col)) begin
                            $display("WARNING: repeated data at index (%d, %d)", prev_row, prev_col);
                        end
                        prev_row = vif.row;
                        prev_col = vif.col;
                    end
                    

                    // Check for row rollover (new frame detection)
                    if (vif.row < current_row) begin
                        // We've rolled over to a new frame, so construct the image
                        im = new(max_width, max_height);
                        for (int y = 0; y < max_height; y++) begin
                            for (int x = 0; x < max_width; x++) begin
                                im.image[y][x] = image_storage[y][x];
                            end
                        end

                        // Push the completed image to the output queue
                        this.output_queue.push(im);

                        // Reset max dimensions for the next frame
                        max_width = 0;
                        max_height = 0;
                    end

                    

                    // Capture the pixel data into the pre-allocated storage
                    image_storage[vif.row][vif.col] = vif.pixel;

                    current_row = vif.row;
                end
            end
        endtask
    endclass // PixelDataInterfaceMonitor

endpackage
