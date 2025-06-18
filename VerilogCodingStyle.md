# Verilog style guide

Except for the below exceptions, we follow the lowRISC style guide, which can be found [here]
(https://github.com/lowRISC/style-guides/blob/master/VerilogCodingStyle.md).

## Exceptions to lowRISC guide
#### Indents are 4 spaces, not 2.
Also, a reminder: all indents should be spaces, not tabs.

#### Parameters should be `ALL_CAPS`
Localparams too.

#### `defparam`
`defparam` isn't forbidden, and is in fact encouraged for long lists of parameters.

#### Code fences
Code fences are encouraged to seperate out large modules. Code fences consist of 64 '/' followed by
a multi-line comment. For instance:
``` systemverilog
module my_module;
    ////////////////////////////////////////////////////////////////
    // Instruction fetch and decode
    // This part of the code controls the datapath
    ...

    ////////////////////////////////////////////////////////////////
    // ALU
    // This part of the code does the actual processing.
    ...
endmodule
```

#### Resets
All resets are active-high and must be synchronous to a clock. `reset` is the typical reset signal
name.

#### Clocking blocks
Clocked blocks should typically be sensitive to only a clock signal.

#### Port declarations
`.*` is acceptable in testbenches.

#### 'x' assignments
The use of 'x' assignments in RTL is encouraged, both to showcase designer intent and to identify
propagation of invalid values.

#### one module per file?
Nominally, we should only have one module per file, but exceptions are ok, especially when:

 - We have a file with a few very small related modules.
 - The main module in a file would be made more readable by a helper module that's not used outside
   of that file.

## Typical code example
This module showcases correct style for most common constructs, as well as some comments.

``` systemverilog
/**
 * Every module should have a c-style block comment at the top describing what it is at a high level.
 *
 * This module is an example module and might have some stuff that doesn't make a lot of sense, but
 * it showcases our preferred coding style.
 */
module simple #(
    // Comments for parameters should be inline with the parameters
    parameter     PIXEL_BIT_DEPTH = 8,
    parameter     WINDOW_LENGTH = 8,

    // localparams can be declared in the parameter list or in the body of the module.
    // They can be necessary in the parameter list if they're later used as the default value for
    // a parameter or in a port declaration.
    localparam    OUTPUT_WIDTH = PIXEL_BIT_DEPTH + $clog2(WINDOW_LENGTH),

    // Reset value for delay line
    parameter logic [(PIXEL_BIT_DEPTH-1):0] RESET_VALUE = 0;
)  (
    // Comments in the port list are encouraged, but for obvious signals (e.g. clk, reset), comments
    // can be omitted
    input clk_i,
    input reset_i,

    // Related signals should be grouped together.
    // Pixel data input. It is valid whenever valid_i is high and must be consumed on that same
    // cycle.
    input [7:0] pixel_i,

    // Valid signal for pixel input
    input        valid_i,

    // Average of last WINDOW_LENGTH pixel values
    output logic [(OUTPUT_WIDTH-1):0] data_o
);
    ////////////////////////////////////////////////////////////////
    // Accumulator
    // This part of the hardware accumulates pixels. Signals and registers internal to the module
    // are declared as close to their associated hardware as possible. Sometimes comments describing
    // them are nice to have, but don't be too verbose if you can help it.
    logic [7:0] line_buffer [WINDOW_LENGTH];
    logic [OUTPUT_WIDTH:0] accumulator;
    always_ff @(posedge clk_i) begin
        if (valid_i) begin
            // sometimes, we might want to use local variables to make calculations more readable.
            // systemverilog semantics requires us to put these at the start of a begin/end block.
            logic [7:0] incoming_pixval;
            logic [7:0] outgoing_pixval;

            // advance line buffer
            line_buffer[0] <= pixel_i;
            for (int i = 1; i < WINDOW_LENGTH; i++) begin
                line_buffer[i] <= line_buffer[i - 1];
            end

            // add incoming pixel and subtract outgoing pixel from accumulator
            incoming_pixval = pixel_i;
            outgoing_pixval = line_buffer[WINDOW_LENGTH - 1];
            accumulator <= (accumulator + pixel_i) - outgoing_pixval;
        end

        // default reset values are at the bottom of the always block - if there are multiple
        // nonblocking assignments to a reg, the final one wins.
        if (reset_i) begin
            accumulator <= (RESET_VALUE * WINDOW_LENGTH);

            for (int i = 0; i < WINDOW_LENGTH; i++) begin
                line_buffer[i] <= RESET_VALUE;
            end
        end
    end

    always_comb data_o = accumulator[0 +: OUTPUT_WIDTH];

    ////////////////////////////////////////////////////////////////
    // State machine
    typedef enum logic [2:0] {
        STATE_IDLE = 0,
        STATE_NOT_IDLE = 1,
        STATE_GOING_TO_IDLE = 2
    } my_state_e;

    my_state_e state, state_next;

    always_comb begin
        // default value
        state_next = state;

        case (state)
            STATE_IDLE: begin
                if (...) state_next = STATE_IDLE;
                else state_next = STATE_NOT_IDLE;
            end

            STATE_NOT_IDLE: begin
                if (...) begin
                    if (... && ...) begin
                        state_next = STATE_NOT_IDLE;
                    end
                end else begin
                    state_next = STATE_GOING_TO_IDLE
                end
            end

            STATE_GOING_TO_IDLE: state_next = STATE_IDLE;
        endcase
    end

    always_ff @(posedge clk_i) begin
        state <= state_next;

        if (reset_i) state <= STATE_IDLE;
    end

    ////////////////////////////////////////////////////////////////
    // Other module
    // This other module doesn't do anything, it's just here for the code style example.
    // Declare connections to 'other module' as close to it as possible.
    logic [7:0] sig_to_check;
    logic check_result;
    always_comb sig_to_check = valid_i ? pixel_i : 8'h0;

    // All connections must be named. There should be no whitespace around the parenths, e.g.
    // .connection(my_signal), .other_connection(other_signal).
    // Related signals can be grouped together on the same line.
    my_other_module other_module (
        .clk_i, .reset_i,
        .signal_to_check_i(sig_to_check), .check_result_o(check_result)
    );
    defparam other_module.CHECK_LEN = 10;
    defparam other_module.PARITY = 1;
endmodule
```

## Condensed Style Guide

This is a short summary of the Comportable style guide. Refer to the lowRISC style guide
for further explanations.

### Basic Style Elements

* Use SystemVerilog-2012 conventions, files named as module.sv, one file
  per module
* Only ASCII, **100** chars per line, **no** tabs, **four** spaces per
  indent for all paired keywords.
* Include **whitespace** around keywords and binary operators
* **No** space between case item and colon, function/task/macro call
  and open parenthesis
* `begin` must be on the same line as the preceding keyword and end
  the line
* `end` must start a new line

### Construct Naming

* Use **lower\_snake\_case** for instance names, signals, declarations,
  variables, types
* Use **ALL\_CAPS** for tunable parameters, enumerated value names
* Use **ALL\_CAPS** for constants and define macros
* Main clock signal is named `clk`. All clock signals must start with `clk_`
* Reset signals are **active-high** and **synchronous**. The all must start with `reset`.
* Signal names should be descriptive and be consistent throughout the
  hierarchy

### Suffixes for signals and types

* Add `_i` to module inputs, `_o` to module outputs or `_io` for
  bi-directional module signals
* The input (next state) of a registered signal should have `_next` as a postfix.
* Pipelined versions of signals should be named `_q2`, `_q3`, etc. to
  reflect their latency
* Active low signals should use `_n`. When using differential signals use
  `_p` for active high
* Enumerated types should be suffixed with `_e`
* Multiple suffixes will not be separated with `_`. `n` should come first
  `i`, `o`, or `io` last

### Language features

* Use **full port declaration style** for modules, any clock and reset
  declared first
* Use **named parameters** for instantiation, all declared ports must
  be present, no `.*` (except in testbenches. `.*` is allowed there for the DUT).
* Top-level parameters is preferred over `` `define`` globals
* Use **symbolically named constants** instead of raw numbers
* Local constants should be declared `localparam`, globals in a separate
  **.svh** file.
* `logic` is preferred over `reg` and `wire`, declare all signals
  explicitly
* `always_comb`, `always_ff` and `always_latch` are preferred over `always`
* Interfaces are discouraged
* Sequential logic must use **non-blocking** assignments
* Combinational blocks must use **blocking** assignments
* Use of latches is discouraged, use flip-flops when possible
* The use of 'x' in RTL is encouraged to show designer intent and highlight illegal states.
* Use available signed arithmetic constructs wherever signed arithmetic
  is used
* When printing use `0b` and `0x` as a prefix for binary and hex. Use
  `_` for clarity
* Use logical constructs (i.e `||`) for logical comparison, bit-wise
  (i.e `|`) for data comparison
* Bit vectors and packed arrays must be little-endian, unpacked arrays
  must be big-endian
* A combinational process should first define **default value** of all
  outputs in the process
* Default value for next state variable should be the current state
