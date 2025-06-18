/**
 * Example testbench showing basic usage of a producer and consumer that use queues for inter-task
 * communication.
 *
 * The consumer also drives a virtual interface.
 */

import triggerable_queue_pkg::*;

interface data_strobe_interface #(
    int WIDTH=8
)  (
    input clk
);
    logic [WIDTH-1:0] data;
    logic valid;
endinterface

class Producer;
    /// Holds the items produced by the producer. Should be hooked up to any consumer queues.
    TriggerableQueueBroadcaster#(logic[7:0]) data_output;

    localparam int EXP_SEED = 1;

    function new();
        data_output = new();
    endfunction

    task automatic run();
        #10;
        forever begin
            real delay;
            logic [7:0] data;
            data = $urandom;
            this.data_output.push(data);

            // wait a poission-distributed amount of time
            $display("Producer: sending data %x at time %t", data, $time);
            delay = $dist_exponential(EXP_SEED, 1.4);
            #(delay);
        end
    endtask
endclass

/**
 * This class recieves items from the producer and drives them onto its given bus
 */
class Consumer;
    /// Recieves items from the producer
    TriggerableQueue#(logic[7:0]) input_queue;

    /// Interface that recieved data should be driven onto
    virtual data_strobe_interface#(8) vif;

    /// This function takes the QueueBroadcaster that we should plug into our input queue, as
    /// well as a handle to the interface that data should be driven onto.
    function new(TriggerableQueueBroadcaster#(logic[7:0]) data_source,
                 virtual data_strobe_interface#(8) vif);
        // Need to construct a new data input queue and register it with the producer.
        this.input_queue = new();
        data_source.add_queue(this.input_queue);

        // Store handle to virtual interface.
        this.vif = vif;
    endfunction

    task automatic run();
        // initialze interface signals to sane values.
        this.vif.valid <= '0;
        this.vif.data <= 'x;

        forever begin
            logic [7:0] data;

            // wait for new data in queue
            @(this.input_queue.element_added_event);
            while (this.input_queue.queue.size() > 0) begin
                this.input_queue.pop(data);

                $display("Consumer: recieved data %x at time %t", data, $time);

                // Drive it onto the bus
                @(posedge this.vif.clk);
                this.vif.valid <= 1;
                this.vif.data <= data;
            end
            @(posedge this.vif.clk);
            this.vif.valid <= '0;
            this.vif.data <= 'x;
        end
    endtask
endclass

module example_tb;
    ////////////////////////////////////////////////////////////////
    // clock generation
    localparam real PERIOD = 5;
    logic clk = 0;
    always begin #(PERIOD/2); clk = ~clk; end

    ////////////////////////////////////////////////////////////////
    // interface connection and instantiation
    data_strobe_interface#(.WIDTH(8)) data_iface(clk);
    logic [7:0] data;
    logic valid;
    assign data = data_iface.data;
    assign valid = data_iface.valid;

    ////////////////////////////////////////////////////////////////
    // producer and consumer classes
    Producer p = new();
    Consumer c = new(p.data_output, data_iface);

    ////////////////////////////////////////////////////////////////
    // execution entry point
    initial begin
        // setup dumpfiles
        $dumpfile("waves.vcd");
        $dumpvars(0, example_tb);

        // Start producer and consumer tasks
        fork
            p.run();
            c.run();
        join_none

        // wait for a while
        #1000;

        $finish;
    end
endmodule
