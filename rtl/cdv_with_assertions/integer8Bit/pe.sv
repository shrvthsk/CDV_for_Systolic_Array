`timescale 1ns / 1ps

module pe #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    input  logic                  clr_acc,
    input  logic [DATA_WIDTH-1:0] west_in,
    input  logic [DATA_WIDTH-1:0] north_in,
    output logic [DATA_WIDTH-1:0] east_out,
    output logic [DATA_WIDTH-1:0] south_out,
    output logic [ACC_WIDTH-1:0]  acc_out
);

    logic [ACC_WIDTH-1:0] accum_reg;

    // Boundary Pipeline Delay Registers
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            east_out  <= '0;
            south_out <= '0;
        end else if (en) begin
            east_out  <= west_in;
            south_out <= north_in;
        end
    end

    // Multiply-Accumulate Execution Core
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_reg <= '0;
        end else if (en) begin
            if (clr_acc) begin
                accum_reg <= $unsigned(west_in * north_in);
            end else begin
                accum_reg <= accum_reg + $unsigned(west_in * north_in);
            end
        end
    end

    assign acc_out = accum_reg;

    // =========================================================================
    // SVA ASSERTIONS - 8-Bit Integer PE
    // NOTE: Vivado XSim requires explicit clocking event for $past()/$stable().
    //       All $past() calls use the form: $past(expr, 1, , @(posedge clk))
    //       All $stable() replaced with:    (x == $past(x, 1, , @(posedge clk)))
    // =========================================================================

    // -------------------------------------------------------------------------
    // A1. Reset must clear pipeline registers within one cycle
    // -------------------------------------------------------------------------
    property p_rst_clears_pipeline;
        @(posedge clk) rst |=> (east_out == '0 && south_out == '0);
    endproperty
    a_rst_clears_pipeline: assert property (p_rst_clears_pipeline)
        else $error("[ASSERT FAIL] a_rst_clears_pipeline: east_out or south_out not 0 after rst");

    // -------------------------------------------------------------------------
    // A2. Reset must clear accumulator within one cycle
    // -------------------------------------------------------------------------
    property p_rst_clears_acc;
        @(posedge clk) rst |=> (acc_out == '0);
    endproperty
    a_rst_clears_acc: assert property (p_rst_clears_acc)
        else $error("[ASSERT FAIL] a_rst_clears_acc: acc_out not 0 after rst");

    // -------------------------------------------------------------------------
    // A3. East passthrough: east_out must mirror west_in after one en=1 cycle
    //     $past with explicit clocking event - workaround for Vivado XSim
    // -------------------------------------------------------------------------
    property p_east_passthrough;
        @(posedge clk) disable iff (rst)
        en |=> (east_out == $past(west_in, 1, , @(posedge clk)));
    endproperty
    a_east_passthrough: assert property (p_east_passthrough)
        else $error("[ASSERT FAIL] a_east_passthrough: east_out=%h, expected west_in_prev=%h",
                    east_out, $past(west_in, 1, , @(posedge clk)));

    // -------------------------------------------------------------------------
    // A4. South passthrough: south_out must mirror north_in after one en=1 cycle
    // -------------------------------------------------------------------------
    property p_south_passthrough;
        @(posedge clk) disable iff (rst)
        en |=> (south_out == $past(north_in, 1, , @(posedge clk)));
    endproperty
    a_south_passthrough: assert property (p_south_passthrough)
        else $error("[ASSERT FAIL] a_south_passthrough: south_out=%h, expected north_in_prev=%h",
                    south_out, $past(north_in, 1, , @(posedge clk)));

    // -------------------------------------------------------------------------
    // A5. Hold when disabled: east_out must not change when en=0
    //     $stable replaced with explicit $past comparison for Vivado XSim
    // -------------------------------------------------------------------------
    property p_east_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (east_out == $past(east_out, 1, , @(posedge clk)));
    endproperty
    a_east_hold: assert property (p_east_hold)
        else $error("[ASSERT FAIL] a_east_hold: east_out changed while en=0");

    // -------------------------------------------------------------------------
    // A6. Hold when disabled: south_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_south_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (south_out == $past(south_out, 1, , @(posedge clk)));
    endproperty
    a_south_hold: assert property (p_south_hold)
        else $error("[ASSERT FAIL] a_south_hold: south_out changed while en=0");

    // -------------------------------------------------------------------------
    // A7. Hold when disabled: acc_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_acc_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (acc_out == $past(acc_out, 1, , @(posedge clk)));
    endproperty
    a_acc_hold: assert property (p_acc_hold)
        else $error("[ASSERT FAIL] a_acc_hold: acc_out changed while en=0");

    // -------------------------------------------------------------------------
    // A8. No unknown (X/Z) values on acc_out after reset is deasserted
    // -------------------------------------------------------------------------
    property p_no_x_acc;
        @(posedge clk) disable iff (rst)
        !$isunknown(acc_out);
    endproperty
    a_no_x_acc: assert property (p_no_x_acc)
        else $error("[ASSERT FAIL] a_no_x_acc: X/Z detected on acc_out");

    // -------------------------------------------------------------------------
    // A9. No unknown (X/Z) values on east_out after reset is deasserted
    // -------------------------------------------------------------------------
    property p_no_x_east;
        @(posedge clk) disable iff (rst)
        !$isunknown(east_out);
    endproperty
    a_no_x_east: assert property (p_no_x_east)
        else $error("[ASSERT FAIL] a_no_x_east: X/Z detected on east_out");

    // -------------------------------------------------------------------------
    // A10. No unknown (X/Z) values on south_out after reset is deasserted
    // -------------------------------------------------------------------------
    property p_no_x_south;
        @(posedge clk) disable iff (rst)
        !$isunknown(south_out);
    endproperty
    a_no_x_south: assert property (p_no_x_south)
        else $error("[ASSERT FAIL] a_no_x_south: X/Z detected on south_out");

    // -------------------------------------------------------------------------
    // A11. Clear behavior: when en=1 and clr_acc=1, acc_out next cycle must
    //      equal the unsigned product of the inputs captured at that cycle.
    //      Uses overlapping implication (|->) with $past to read back the
    //      triggering cycle's values - explicit clock required for Vivado XSim.
    // -------------------------------------------------------------------------
    property p_acc_clr_loads_product;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) && $past(clr_acc, 1, , @(posedge clk))) |->
        (acc_out == (ACC_WIDTH'($past(west_in, 1, , @(posedge clk))) *
                     ACC_WIDTH'($past(north_in, 1, , @(posedge clk)))));
    endproperty
    a_acc_clr_loads_product: assert property (p_acc_clr_loads_product)
        else $error("[ASSERT FAIL] a_acc_clr_loads_product: acc_out=%h", acc_out);

    // -------------------------------------------------------------------------
    // A12. Accumulate behavior: when en=1 and clr_acc=0, acc_out next cycle
    //      must equal previous acc_out + product of inputs at that cycle.
    // -------------------------------------------------------------------------
    property p_acc_accumulate;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) && !$past(clr_acc, 1, , @(posedge clk))) |->
        (acc_out == ($past(acc_out, 1, , @(posedge clk)) +
                     (ACC_WIDTH'($past(west_in,  1, , @(posedge clk))) *
                      ACC_WIDTH'($past(north_in, 1, , @(posedge clk))))));
    endproperty
    a_acc_accumulate: assert property (p_acc_accumulate)
        else $error("[ASSERT FAIL] a_acc_accumulate: acc_out=%h", acc_out);

endmodule
