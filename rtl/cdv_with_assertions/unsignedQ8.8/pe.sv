`timescale 1ns/1ps

module pe #(
    parameter int DATA_WIDTH = 16,
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
    logic [31:0] intermediate_product;

    // Horizontal and Vertical Pipeline Channels
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            east_out  <= '0;
            south_out <= '0;
        end else if (en) begin
            east_out  <= west_in;
            south_out <= north_in;
        end
    end

    // Unsigned Product Multiplication Core (Q8.8 x Q8.8 = Q16.16 Intermediate State)
    assign intermediate_product = $unsigned(west_in * north_in);

    // Q16.16 to Q24.8 Truncation/Realignment Arithmetic State Engine
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_reg <= '0;
        end else if (en) begin
            if (clr_acc) begin
                accum_reg <= intermediate_product >> 8;
            end else begin
                accum_reg <= accum_reg + (intermediate_product >> 8);
            end
        end
    end

    assign acc_out = accum_reg;

    // =========================================================================
    // SVA ASSERTIONS - Q8.8 Unsigned Fixed-Point PE
    // NOTE: All $past() use explicit clocking event for Vivado XSim compatibility:
    //       $past(expr, 1, , @(posedge clk))
    //       $stable() replaced with (x == $past(x, 1, , @(posedge clk)))
    // =========================================================================

    // -------------------------------------------------------------------------
    // A1. Reset must clear pipeline registers within one cycle
    // -------------------------------------------------------------------------
    property p_rst_clears_pipeline;
        @(posedge clk) rst |=> (east_out == '0 && south_out == '0);
    endproperty
    a_rst_clears_pipeline: assert property (p_rst_clears_pipeline)
        else $error("[ASSERT FAIL] a_rst_clears_pipeline [Q8.8]: pipeline regs not zeroed after rst");

    // -------------------------------------------------------------------------
    // A2. Reset must clear accumulator within one cycle
    // -------------------------------------------------------------------------
    property p_rst_clears_acc;
        @(posedge clk) rst |=> (acc_out == '0);
    endproperty
    a_rst_clears_acc: assert property (p_rst_clears_acc)
        else $error("[ASSERT FAIL] a_rst_clears_acc [Q8.8]: acc_out not zeroed after rst");

    // -------------------------------------------------------------------------
    // A3. East passthrough: east_out must mirror west_in after one en=1 cycle
    // -------------------------------------------------------------------------
    property p_east_passthrough;
        @(posedge clk) disable iff (rst)
        en |=> (east_out == $past(west_in, 1, , @(posedge clk)));
    endproperty
    a_east_passthrough: assert property (p_east_passthrough)
        else $error("[ASSERT FAIL] a_east_passthrough [Q8.8]: east_out=%h, expected=%h",
                    east_out, $past(west_in, 1, , @(posedge clk)));

    // -------------------------------------------------------------------------
    // A4. South passthrough: south_out must mirror north_in after one en=1 cycle
    // -------------------------------------------------------------------------
    property p_south_passthrough;
        @(posedge clk) disable iff (rst)
        en |=> (south_out == $past(north_in, 1, , @(posedge clk)));
    endproperty
    a_south_passthrough: assert property (p_south_passthrough)
        else $error("[ASSERT FAIL] a_south_passthrough [Q8.8]: south_out=%h, expected=%h",
                    south_out, $past(north_in, 1, , @(posedge clk)));

    // -------------------------------------------------------------------------
    // A5. Hold when disabled: east_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_east_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (east_out == $past(east_out, 1, , @(posedge clk)));
    endproperty
    a_east_hold: assert property (p_east_hold)
        else $error("[ASSERT FAIL] a_east_hold [Q8.8]: east_out changed while en=0");

    // -------------------------------------------------------------------------
    // A6. Hold when disabled: south_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_south_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (south_out == $past(south_out, 1, , @(posedge clk)));
    endproperty
    a_south_hold: assert property (p_south_hold)
        else $error("[ASSERT FAIL] a_south_hold [Q8.8]: south_out changed while en=0");

    // -------------------------------------------------------------------------
    // A7. Hold when disabled: acc_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_acc_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (acc_out == $past(acc_out, 1, , @(posedge clk)));
    endproperty
    a_acc_hold: assert property (p_acc_hold)
        else $error("[ASSERT FAIL] a_acc_hold [Q8.8]: acc_out changed while en=0");

    // -------------------------------------------------------------------------
    // A8. No unknown (X/Z) values on acc_out
    // -------------------------------------------------------------------------
    property p_no_x_acc;
        @(posedge clk) disable iff (rst)
        !$isunknown(acc_out);
    endproperty
    a_no_x_acc: assert property (p_no_x_acc)
        else $error("[ASSERT FAIL] a_no_x_acc [Q8.8]: X/Z on acc_out");

    // -------------------------------------------------------------------------
    // A9. No unknown (X/Z) values on east_out
    // -------------------------------------------------------------------------
    property p_no_x_east;
        @(posedge clk) disable iff (rst)
        !$isunknown(east_out);
    endproperty
    a_no_x_east: assert property (p_no_x_east)
        else $error("[ASSERT FAIL] a_no_x_east [Q8.8]: X/Z on east_out");

    // -------------------------------------------------------------------------
    // A10. No unknown (X/Z) values on south_out
    // -------------------------------------------------------------------------
    property p_no_x_south;
        @(posedge clk) disable iff (rst)
        !$isunknown(south_out);
    endproperty
    a_no_x_south: assert property (p_no_x_south)
        else $error("[ASSERT FAIL] a_no_x_south [Q8.8]: X/Z on south_out");

    // -------------------------------------------------------------------------
    // A11. Q8.8 Clear behavior: acc_out = (west_in * north_in) >> 8
    // -------------------------------------------------------------------------
    property p_acc_clr_loads_product;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) && $past(clr_acc, 1, , @(posedge clk))) |->
        (acc_out == ((ACC_WIDTH'($past(west_in,  1, , @(posedge clk))) *
                      ACC_WIDTH'($past(north_in, 1, , @(posedge clk)))) >> 8));
    endproperty
    a_acc_clr_loads_product: assert property (p_acc_clr_loads_product)
        else $error("[ASSERT FAIL] a_acc_clr_loads_product [Q8.8]: acc_out=%h", acc_out);

    // -------------------------------------------------------------------------
    // A12. Q8.8 Accumulate behavior: acc_out = prev_acc + (product >> 8)
    // -------------------------------------------------------------------------
    property p_acc_accumulate;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) && !$past(clr_acc, 1, , @(posedge clk))) |->
        (acc_out == ($past(acc_out, 1, , @(posedge clk)) +
                     ((ACC_WIDTH'($past(west_in,  1, , @(posedge clk))) *
                       ACC_WIDTH'($past(north_in, 1, , @(posedge clk)))) >> 8)));
    endproperty
    a_acc_accumulate: assert property (p_acc_accumulate)
        else $error("[ASSERT FAIL] a_acc_accumulate [Q8.8]: acc_out=%h", acc_out);

    // -------------------------------------------------------------------------
    // A13. Intermediate product wire integrity check
    // -------------------------------------------------------------------------
    property p_intermediate_product_correct;
        @(posedge clk) disable iff (rst)
        (intermediate_product == $unsigned(west_in * north_in));
    endproperty
    a_intermediate_product_correct: assert property (p_intermediate_product_correct)
        else $error("[ASSERT FAIL] a_intermediate_product_correct [Q8.8]: product=%h", intermediate_product);

endmodule
