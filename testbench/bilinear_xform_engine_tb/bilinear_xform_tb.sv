`timescale 1ns/10ps

/**
 * Tests the bilinear transformer
 *
 * DigitalImages are generated by a DigitalImageGenerator and are fed to both a DigitalImageDriver
 * and a ConvolutionModel
 *
 * The DigitalImageDriver is used to stimulate the DUT with the images produced by the
 * DigitalImageGenerator.
 *
 * The ConvolutionModel consumes images produced by the DigitalImageGenerator and produces convolved
 * images.
 *
 * The DUT Montior watches the DUT's output bus and converts the bus traffic to DigitalImages
 *
 * The Scoreboard compares results
 */

////////////////////////////////////////////////////////////////
// imports
import testbench_common_pkg::*;
import testbench_util_pkg::*;
import triggerable_queue_pkg::*;
import camera_simulation_pkg::*;
import pixel_data_interface_utils_pkg::*;
import golden_models_pkg::*;
`include "testbench_util_pkg.svh"

////////////////////////////////////////////////////////////////
// Includes
`include "bilinear_xform.sv"
`include "RAM_2Port.v"

module bilinear_xform_tb;
    ////////////////////////////////////////////////////////////////
    // shared localparams
    localparam real PIXCLK_PERIOD = 5;

    localparam IMAGE_WIDTH = 100;
    localparam IMAGE_HEIGHT = 100;

    // Fixed Point Arithmetic params
    localparam FP_M_IMAGE = 8;
    localparam FP_N_IMAGE = 0;
    localparam FP_S_IMAGE = 0;

    // no.bits for fractional part 
    localparam PRECISION = 8;

    // How many lines in buffer ** 2
    // i.e 3 is 2^3 = 8
    localparam N_LINES_POW2 = 5;

    // Turns out, the optimal condition to decide where
    // the pipe (buffer) is full and output pixels should
    // being driven is entirely dependant on the transformations
    // done for the reverse mapping. So, it too will be parameterized
    // note that you have to buffer at least 1 line and 1 column pixel
    localparam PIPE_ROW = 16;
    localparam PIPE_COL = 0;
    
    localparam N_IMAGES = 2;

    localparam IMAGE_BIT_DEPTH = FP_M_IMAGE + FP_N_IMAGE + FP_S_IMAGE;

    localparam CLKS_PER_PIXEL = 1;

    // to work, must be >= CLKS_PER_PIXEL
    localparam PIXEL_CADENCE = 1;

    localparam INTER_IMAGE_TIME = ((IMAGE_WIDTH * IMAGE_HEIGHT) + (IMAGE_WIDTH * ((2 ** N_LINES_POW2) + 300))) * (CLKS_PER_PIXEL * PIXCLK_PERIOD * PIXEL_CADENCE);

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
    logic signed [11+PRECISION-1:0] matrix_linear [9];
    logic signed [11+PRECISION-1:0] matrix [3][3];

    bilinear_xform #(
        .WIDTH(IMAGE_WIDTH),
        .HEIGHT(IMAGE_HEIGHT),
        .N_LINES_POW2(N_LINES_POW2),
        .PIPE_ROW(PIPE_ROW),
        .PIPE_COL(PIPE_COL),
        .PRECISION(PRECISION),
        .CLKS_PER_PIXEL(CLKS_PER_PIXEL)
    ) dut (
        .in(pixel_data_to_dut_iface),
        .out(pixel_data_from_dut_iface),

        // external wires
        .matrix_i(matrix),
        .rst_n_i(rst_n_i)
    );

    ////////////////////////////////////////////////////////////////
    // simulation environment
    // image generator, bus drivers, golden model, bus monitor, and scoreboard classes
    DigitalImageGenerator#(IMAGE_BIT_DEPTH) image_generator = new();
    initial begin
        image_generator.width = IMAGE_WIDTH; image_generator.height = IMAGE_HEIGHT;
        image_generator.period = INTER_IMAGE_TIME;
        image_generator.image_name = "../test_images/shikamaru_100_100.ppm";
    end

    DigitalImageDriver #(FP_M_IMAGE, FP_N_IMAGE, FP_S_IMAGE) 
        image_driver = new(image_generator.output_queue, pixel_data_to_dut_iface);

    initial begin image_driver.pixel_cadence = PIXEL_CADENCE; end

    BilinearXformModel#(
        // fp parms
        .FP_M_IMAGE(FP_M_IMAGE),
        .FP_N_IMAGE(FP_N_IMAGE),
        .FP_S_IMAGE(FP_S_IMAGE),

        .PRECISION(PRECISION),

        .WIDTH(IMAGE_WIDTH),
        .HEIGHT(IMAGE_HEIGHT)
        
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
    initial timeout_watchdog.timeout = (IMAGE_WIDTH * IMAGE_HEIGHT * CLKS_PER_PIXEL * PIXCLK_PERIOD);

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
        $dumpvars(0, bilinear_xform_tb);

        // set up matrix, read in linear -> 2d matrix
        $readmemb("../test_transformations/general_matrix.txt",matrix_linear);
        for(int y = 0; y < 3; y += 1) begin
            for(int x = 0; x < 3; x += 1) begin
                matrix[y][x] = matrix_linear[(y*3) + x];
            end
        end

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
              = error_info_t'{ERROR_SEVERITY_ERROR, "bilinear_xform_tb: scoreboard failed to stop", $time};
            errors.push(err);
        end
        print_errors_and_finish(errors);
    end
endmodule