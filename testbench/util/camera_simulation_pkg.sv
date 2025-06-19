`timescale 1ns/10ps

/**
 * This file contains some classes for generating and working with images
 */

package camera_simulation_pkg;
    import testbench_common_pkg::*;
    import triggerable_queue_pkg::*;

    /**
     * This class represents a single frame of a digital image.
     * Users of this class may just directly access the 'image' member to read and write data.
     * The class is primarily a container.
     */
    class DigitalImage#(parameter BIT_DEPTH=8);
        int width, height;
        logic [BIT_DEPTH-1:0] image [][];

        // New function just allocates image storage
        function new(int width, int height);
            this.width = width;
            this.height = height;

            this.image = new[height];
            foreach(this.image[i]) this.image[i] = new[width];
        endfunction

        /**
         * Compares two images, returns 0 if they're the same, nonzero if they differ
         */
        static function int compare(DigitalImage#(BIT_DEPTH) a, DigitalImage#(BIT_DEPTH) b);
            // Check if dimensions are the same
            if ((a.width != b.width) || (a.height != b.height)) begin
                return 1;
            end

            // Compare pixel values
            for (int y = 0; y < a.height; y++) begin
                for (int x = 0; x < a.width; x++) begin
                    if (a.image[y][x] !== b.image[y][x]) begin
                        return 1;
                    end
                end
            end

            // Images made it through the check, so they're the same
            return 0;
        endfunction

        function void print_image();
            for(int y = 0; y < this.height; y++) begin
                for(int x = 0; x < this.width; x++) begin
                    reg signed [BIT_DEPTH-1:0] pix = this.image[y][x];
                    $write("%h ", pix);
                end
                $display();
            end
            $display();
        endfunction

        /// Writes the given image to an ascii PPM file with the given filename
        /// Returns 0 on success, nonzero on failure
        function automatic int write_to_file(string filename);
            // Try to open the given filename for writing.
            int file = $fopen(filename, "w");
            if (file == 0) begin
                $display("Error: Could not open file %s for writing.", filename);
                return -1;
            end

            // Write ppm header
            $fdisplay(file, "P3");
            $fdisplay(file, "%0d %0d", width, height);
            $fdisplay(file, "%0d", (1 << BIT_DEPTH) - 1);

            // Write pixel data
            foreach (image[y]) begin
                foreach (image[y][x]) begin
                    // Since the image is monochrome, we repeat the value for R, G, B channels
                    int pixel_value = image[y][x];
                    $fdisplay(file, "%0d %0d %0d", pixel_value, pixel_value, pixel_value);
                end
            end

            // Close the file and return
            $fclose(file);
            return 0;
        endfunction
    endclass

    /**
     * This class generates random digital images and puts them on an output queue at a fixed rate.
     */
    class DigitalImageGenerator#(parameter BIT_DEPTH=8);
        TriggerableQueueBroadcaster#(DigitalImage#(BIT_DEPTH)) output_queue;

        // These should be set manually by user code before run() is started.
        int width = 100;
        int height = 100;
        real period = 10000;
        string image_name = "";
        string base_image_name = "";
        int n_images_gen = 5;
        int unique_images = 0;
        int unique_images_count = 0;

        function new();
            output_queue = new();
        endfunction

        function DigitalImage#(BIT_DEPTH) generate_image_random();
            DigitalImage#(BIT_DEPTH) im = new(this.width, this.height);

            for (int y = 0; y < im.height; y++) begin
                for (int x = 0; x < im.width; x++) begin
                    im.image[y][x] = $urandom();
                end
            end

            return im;
        endfunction

        function DigitalImage#(BIT_DEPTH) generate_image_gradient();
            DigitalImage#(BIT_DEPTH) im = new(this.width, this.height);

            for (int y = 0; y < im.height; y++) begin
                for (int x = 0; x < im.width; x++) begin
                    im.image[y][x] = x + y;
                end
            end

            return im;
        endfunction

        function DigitalImage#(BIT_DEPTH) generate_image_gradient_checkerboard();
            DigitalImage#(BIT_DEPTH) im = new(this.width, this.height);

            for (int y = 0; y < im.height; y++) begin
                for (int x = 0; x < im.width; x++) begin
                    int shift_amt = BIT_DEPTH - 4;
                    im.image[y][x] = (((x + y) >> shift_amt) << shift_amt);
                end
            end

            return im;
        endfunction

        function DigitalImage#(BIT_DEPTH) generate_image_simple_sequence();
            DigitalImage#(BIT_DEPTH) im = new(this.width, this.height);
            int counter = 0;
            for (int y = 0; y < im.height; y++) begin
                for (int x = 0; x < im.width; x++) begin
                    im.image[y][x] = counter;
                    counter += 1;
                end
            end

            return im;
        endfunction

        function DigitalImage#(BIT_DEPTH) generate_image_from_ppm(string filename);
            DigitalImage#(BIT_DEPTH) im = new(this.width, this.height);
            int file, r, g, b, width, height, maxval;
            string magic_num;
            string unique_filename;
            string num;

            // open the file
            if(this.unique_images > 0) begin
                if(this.unique_images_count < this.unique_images) begin
                    num.itoa(this.unique_images_count);
                    unique_filename = {this.base_image_name, "_", num ,".ppm"};
                    this.unique_images_count++;
                end else begin
                    unique_filename = {this.base_image_name, "_0.ppm"};
                end
                
                file = $fopen(unique_filename, "r");
                if(file == 0) begin
                    $display("ERROR: Failed to open file %s", unique_filename);
                    return null;
                end
                
            end else begin 
                file = $fopen(filename, "r");
                if(file == 0) begin
                    $display("ERROR: Failed to open file %s", filename);
                    return null;
                end
            end

            

            // Read PPM header (magic number, width, height, maxval)
            // %s reads the string (P3)
            // %d reads integers (width, height, max color value)
            $fscanf(file, "%s\n%d %d\n%d\n", magic_num, width, height, maxval);

            if (magic_num != "P3") begin
                $display("ERROR: Unsupported PPM format (only ASCII P3 supported).");
                $fclose(file);
                return null;
            end

            for (int y = 0; y < im.height; y++) begin
                for (int x = 0; x < im.width; x++) begin
                    // Read the red, green and the blue values
                    $fscanf(file, "%d\n %d\n %d\n", r, g, b);
                    // just use green for monochrome
                    im.image[y][x] = g >>> ($clog2(maxval + 1) - BIT_DEPTH);
                end
            end
            $fclose(file);
            return im;

        endfunction

        task automatic run();
            #1000;
            forever begin
                DigitalImage#(BIT_DEPTH) im;

                // generate and send a new image
                if(this.n_images_gen > 0) begin
                    //im = this.generate_image_gradient_checkerboard();
                    //im = this.generate_image_gradient();
                    //im = this.generate_image_simple_sequence();
                    im = this.generate_image_from_ppm(this.image_name);
                    //im = this.generate_image_random();

                    this.output_queue.push(im);
                    this.n_images_gen -= 1;
                end

                // wait
                #(this.period);
            end
        endtask
    endclass

    /**
     * This class recieves images from 2 seperate queues and compares them.
     * Errors are added to the errors queue when incorrect images arrive.
     */
    class DigitalImageScoreboard #(parameter BIT_DEPTH=8);
        /// Queue for images coming from DUT
        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) dut_queue;

        /// Queue for images coming from the correct model
        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) golden_queue;

        /// This task puts errors in this queue
        TriggerableQueue#(error_info_t) errors;

        /// This user-editable parameter will end the simulation after a certain number of images
        /// have been checked.
        /// If this parameter is left at -1, then the scoreboard will not halt the simulation.
        int finish_after = -1;

        int image_count = 0;

        function new(TriggerableQueueBroadcaster#(DigitalImage#(BIT_DEPTH)) dut_source,
                     TriggerableQueueBroadcaster#(DigitalImage#(BIT_DEPTH)) golden_source,
                     TriggerableQueue#(error_info_t) errors);
            this.dut_queue = new();
            this.golden_queue = new();

            dut_source.add_queue(this.dut_queue);
            golden_source.add_queue(this.golden_queue);

            this.errors = errors;
        endfunction

        task automatic run();
            forever begin
                DigitalImage#(BIT_DEPTH) dut_im;
                DigitalImage#(BIT_DEPTH) golden_im;

                this.dut_queue.pop(dut_im);
                $display("Image %d DUT model fetched", this.image_count);
                
                this.golden_queue.pop(golden_im);
                $display("Image %d Golden model fetched", this.image_count);


                $display("Image %d DUT model and Golden Model being compared..", this.image_count);
                if (DigitalImage#(BIT_DEPTH)::compare(dut_im, golden_im)) begin
                    error_info_t err = error_info_t'{ERROR_SEVERITY_ERROR,
                                        $sformatf("DigitalImageScoreboard: image %0d differ", this.image_count),
                                        $time};
                    this.errors.push(err);
                end

                $display();

                this.image_count++;
                // Unfortunately, this means that if the scoreboard finishes before file dumps,
                // (which it often does), we lose them. 
                if ((this.finish_after > 0) && (this.image_count >= this.finish_after)) begin
                    print_errors_and_finish(this.errors);
                end
            end
        endtask
    endclass

    /**
     * This utility class recieves images over a queue and writes them to files.
     * The images will be written to seperate ppm files
     *
     * TODO: add numpy writing capability
     */
    class DigitalImageFileDumper#(parameter BIT_DEPTH=8);
        TriggerableQueue#(DigitalImage#(BIT_DEPTH)) input_queue;

        // basename for files. Files will be saved as basename_0.ppm, basename_1.ppm
        // Should be directly set by user code.
        string basename = "image";

        // In case a runaway simulation fails to stop, what's the maximum number of images to save?
        // Should be directly set by user code.
        int max_images = 100;

        function new(TriggerableQueueBroadcaster#(DigitalImage#(BIT_DEPTH)) image_source);
            this.input_queue = new();
            image_source.add_queue(this.input_queue);
        endfunction
        

        task automatic run();
            int img_count = 0;

            forever begin
                DigitalImage#(BIT_DEPTH) im;
                string filename, filenum;

                input_queue.pop(im);

                filenum.itoa(img_count++);
                filename = {this.basename, "_", filenum, ".ppm"};
                if (im.write_to_file(filename) != 0) begin
                    $display("Warning: DigitalImageFileDumper: failed to write to file %s", filename);
                end

                if ((this.max_images >= 0) && (img_count >= this.max_images)) break;
            end
        endtask
    endclass
endpackage
