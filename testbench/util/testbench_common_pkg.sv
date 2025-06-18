`timescale 1ns/10ps

/**
 * This file contains some common utilities for testbenches
 */

package testbench_common_pkg;
    import triggerable_queue_pkg::*;

    typedef enum { ERROR_SEVERITY_INFO, ERROR_SEVERITY_ERROR } error_severity_e;

    typedef struct {
        error_severity_e severity;
        string message;
        time t;
    } error_info_t;

    /**
     * This task prints all of the errors in the error queue.
     * If there are any errors, it prints a failure message and exits with a non-zero return code.
     */
    task automatic print_errors_and_finish(TriggerableQueue#(error_info_t) errors);
        logic error_happened = 0;

        while (errors.queue.size() > 0) begin
            error_info_t error;
            errors.pop(error);
            if (error.severity == ERROR_SEVERITY_INFO) begin
                $display("\033[1;35mINFO: \033[0m %s at time %t", error.message, error.t);
            end else if (error.severity == ERROR_SEVERITY_ERROR)  begin
                error_happened = 1;
                $display("\033[1;31mERROR:\033[0m %s at time %t", error.message, error.t);
            end
        end

        if (error_happened) begin
            $fatal(1, "\033[1;31mFAILED\033[0m");
        end else begin
            $display("\033[1;32mPASSED\033[0m");
            $finish;
        end
    endtask
endpackage
