`timescale 1ns/10ps

/**
 * Tests for Delay Line
 *
 */

////////////////////////////////////////////////////////////////
// Includes
`include "common/pixel_data_interface.svh"
`include "testbench_util_pkg.svh"
`include "delay_line.sv"
`include "afifo.v"

////////////////////////////////////////////////////////////////
// imports
import testbench_common_pkg::*;
import testbench_util_pkg::*;
import triggerable_queue_pkg::*;
import camera_simulation_pkg::*;
import pixel_data_interface_utils_pkg::*;

////////////////////////////////////////////////////////////////
// local class / typedef declarations
/**
 * This class takes in images from a queue of DigitlaImages, performs a convolution on them, and
 * then outputs the resulting convolved images to an output queue.
 */
class DelayLineModel #(
    // Input image dimensions
    parameter IMAGE_WIDTH = 640,
    parameter IMAGE_HEIGHT = 480,
    parameter IMAGE_BIT_DEPTH = 8
);

    TriggerableQueue#(DigitalImage#(IMAGE_BIT_DEPTH)) input_queue;
    TriggerableQueueBroadcaster#(DigitalImage#(IMAGE_BIT_DEPTH)) output_queue;
    TriggerableQueue#(error_info_t) errors;


    function new(TriggerableQueueBroadcaster#(DigitalImage#(IMAGE_BIT_DEPTH)) image_source,
                 TriggerableQueue#(error_info_t) errors);
        this.input_queue = new();
        this.output_queue = new();

        image_source.add_queue(this.input_queue);

        this.errors = errors;
    endfunction

    function automatic DigitalImage#(IMAGE_BIT_DEPTH) passthrough (DigitalImage#(IMAGE_BIT_DEPTH) im);

        DigitalImage#(IMAGE_BIT_DEPTH) out;

        out = new(im.width, im.height); 

        // Iterate over each pixel in the input image
        for (int y = 0; y < im.height; y++) begin
            for (int x = 0; x < im.width; x++) begin
                out.image[y][x] = im.image[y][x];
            end
        end
        
        return out;
    endfunction

    task automatic run();
        forever begin
            DigitalImage#(IMAGE_BIT_DEPTH) im_in;
            DigitalImage#(IMAGE_BIT_DEPTH) im_out;
            this.input_queue.pop(im_in);

            im_out = this.passthrough(im_in);

            this.output_queue.push(im_out);
        end
    endtask
endclass


module delay_line_tb;
    ////////////////////////////////////////////////////////////////
    // shared localparams
    localparam real PIXCLK_PERIOD = 5;

    // Input image dimensions
    localparam IMAGE_WIDTH = 100;
    localparam IMAGE_HEIGHT = 100;

    localparam FP_M_IMAGE = 8;
    localparam FP_N_IMAGE = 0;
    localparam FP_S_IMAGE = 0;

    localparam N_IMAGES = 2;

    localparam CLKS_PER_PIXEL = 7;

    // delay params
    localparam DELAY = 57;
    localparam IMAGE_BIT_DEPTH = FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE;

    localparam PIXEL_CADENCE = 3;

    localparam INTER_IMAGE_TIME = ((IMAGE_WIDTH * IMAGE_HEIGHT)) * (PIXCLK_PERIOD * PIXEL_CADENCE);

    ////////////////////////////////////////////////////////////////
    // clock generation
    logic pixclk = 0;
    always begin #(PIXCLK_PERIOD/2); pixclk = ~pixclk; end

    ////////////////////////////////////////////////////////////////
    // common variables
    TriggerableQueue#(error_info_t) errors = new();

    ////////////////////////////////////////////////////////////////
    // interface instantiation and connection
    // we need some logic connected to interfaces so that vcd file captures them for gtkwave.
    pixel_data_interface #(
        .FP_M(FP_M_IMAGE),
        .FP_N(FP_N_IMAGE),
        .FP_S(FP_S_IMAGE)
    ) pixel_data_to_dut_iface(pixclk);

    pixel_data_interface #(
        .FP_M(FP_M_IMAGE),
        .FP_N(FP_N_IMAGE),
        .FP_S(FP_S_IMAGE)
    ) pixel_data_from_dut_iface(pixclk);
    
    
    ////////////////////////////////////////////////////////////////
    // DUT setup
    logic rst_n_i;

    delay_line #(
        .WIDTH(IMAGE_WIDTH),
        .HEIGHT(IMAGE_HEIGHT),
        .DELAY(DELAY),
        .CLKS_PER_PIXEL(CLKS_PER_PIXEL)
    ) dut (
        .in(pixel_data_to_dut_iface),
        .out(pixel_data_from_dut_iface),

        // external wires
        .rst_n_i(rst_n_i)
    );

    ////////////////////////////////////////////////////////////////
    // simulation environment
    // image generator, bus drivers, golden model, bus monitor, and scoreboard classes
    DigitalImageGenerator#(IMAGE_BIT_DEPTH) image_generator = new();
    initial begin
        image_generator.width = IMAGE_WIDTH; image_generator.height = IMAGE_HEIGHT;
        image_generator.period = INTER_IMAGE_TIME;
        image_generator.image_name = "../test_images/princess_mononoke_640_480.ppm";
    end

    DigitalImageDriver #(FP_M_IMAGE, FP_N_IMAGE, FP_S_IMAGE) 
        image_driver = new(image_generator.output_queue, pixel_data_to_dut_iface);

    initial begin image_driver.pixel_cadence = PIXEL_CADENCE; end

    DelayLineModel#(
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .IMAGE_BIT_DEPTH(IMAGE_BIT_DEPTH)    
    )  golden = new(image_generator.output_queue, errors);

    PixelDataInterfaceMonitor #(FP_M_IMAGE, FP_N_IMAGE, FP_S_IMAGE)
        dut_monitor = new(pixel_data_from_dut_iface);

    // scoreboard
    DigitalImageScoreboard#(IMAGE_BIT_DEPTH) scoreboard = new(dut_monitor.output_queue,
                                                                       golden.output_queue,
                                                                       errors);
    initial scoreboard.finish_after = N_IMAGES;

    // watchdog that kills simulation when the DUT doesn't respond in a timely fashion.
    clocked_valid_interface dut_requester_interface(pixclk, pixel_data_to_dut_iface.valid);
    clocked_valid_interface dut_responder_interface(pixclk, pixel_data_from_dut_iface.valid);
    DataValidTimeoutWatchdog timeout_watchdog = new(dut_requester_interface,
                                                    dut_responder_interface,
                                                    errors);
    initial timeout_watchdog.timeout = (IMAGE_WIDTH * IMAGE_HEIGHT * PIXCLK_PERIOD * PIXEL_CADENCE);

    // record images from image generator, from DUT and from model
    DigitalImageFileDumper#(IMAGE_BIT_DEPTH) gen_image_dumper = new(image_generator.output_queue);
    DigitalImageFileDumper#(IMAGE_BIT_DEPTH) dut_image_dumper = new(dut_monitor.output_queue);
    DigitalImageFileDumper#(IMAGE_BIT_DEPTH) golden_image_dumper = new(golden.output_queue);
    initial gen_image_dumper.basename = "gen_image";
    initial dut_image_dumper.basename = "dut_image";
    initial golden_image_dumper.basename = "mdl_image";


    ////////////////////////////////////////////////////////////////
    // execution entry point
    initial begin
        // setup dumpfiles
        $dumpfile("waves.vcd");
        $dumpvars(0, delay_line_tb);

        rst_n_i <= 1;
        repeat(5) @(posedge pixclk)
        rst_n_i <= 0;
        repeat(7) @(posedge pixclk)
        rst_n_i <= 1;

        // start all tasks for simulation components
        fork
            // tasks for main generation and testing pipeline
            image_generator.run();
            image_driver.run();
            golden.run();
            dut_monitor.run();
            scoreboard.run();

            // watchdog
            timeout_watchdog.run();

            // record images
            dut_image_dumper.run();
            golden_image_dumper.run();
            gen_image_dumper.run();
        join_none

        // wait for a while. Scoreboard should automatically stop us before this.
        #1000000000;

        begin
            error_info_t err
              = error_info_t'{ERROR_SEVERITY_ERROR, "delay_line_tb: scoreboard failed to stop", $time};
            errors.push(err);
        end
        print_errors_and_finish(errors);
    end
endmodule