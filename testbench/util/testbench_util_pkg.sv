`timescale 1ns/10ps

/**
 * This package contains some common testbench utility classes
 */
package testbench_util_pkg;
    import triggerable_queue_pkg::*;
    import testbench_common_pkg::*;

    /**
     * This class accepts 2 clock signals and data valid signals from a "requester" and "responder".
     *
     * If the responder's data valid signal doesn't strobe within a certain number of clock cycles
     * after the requester's strobe goes high, the responder is considered to have timed out.
     *
     * When the responder times out, the DataValidTimeoutWatchdog will terminate the simulation.
     */
    class DataValidTimeoutWatchdog;
        virtual clocked_valid_interface requester;
        virtual clocked_valid_interface responder;

        TriggerableQueue#(error_info_t) errors;

        /// internal signal for monitoring requester / responder state
        bit requester_pending = 0;

        // Once requester_valid is registered high, what's the maximum number of responder clks that
        // may pass before the responder is considered to have timed out
        // should be directly set by user code.
        int timeout = '1;
        int timeout_count = 0;

        function new(virtual clocked_valid_interface requester,
                     virtual clocked_valid_interface responder,
                     TriggerableQueue#(error_info_t) errors);
            this.requester = requester;
            this.responder = responder;

            this.errors = errors;
        endfunction

        task automatic run();
            fork
                forever begin
                    // Anytime the requester has valid data, we mark the requester as pending,
                    // meaning that the monitor starts counting.
                    @(posedge this.requester.clk);
                    if (this.requester.valid) requester_pending = 1;
                end

                forever begin
                    @(posedge this.responder.clk);

                    // If the responder has responded, clear the requester pending signal and
                    // reset the timeout count.
                    if (this.responder.valid) begin
                        requester_pending = 0;
                        this.timeout_count = 0;
                    end

                    // As long as there's an un-ack'd request, we increment the timeout count
                    if (requester_pending) this.timeout_count++;

                    // If we exceeded our allowed timeout, terminate the simulation
                    if (this.timeout_count > this.timeout) begin
                        error_info_t err = error_info_t'{ERROR_SEVERITY_ERROR,
                                           "DataValidTimeoutWatchdog: responder timed out",
                                           $time};
                        this.errors.push(err);
                        print_errors_and_finish(this.errors);
                    end
                end
            join
        endtask
    endclass
endpackage
