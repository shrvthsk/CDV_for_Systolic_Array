`timescale 1ns/1ps

//==================================
//CDV with Assertions
//Signed Q8.8 pe.sv
//==================================

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

    logic signed [ACC_WIDTH-1:0] accum_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            east_out  <= '0;
            south_out <= '0;
        end else if (en) begin
            east_out  <= west_in;
            south_out <= north_in;
        end
    end

    logic signed [ACC_WIDTH-1:0] intermediate_product;
    assign intermediate_product = ACC_WIDTH'($signed(west_in))
                                 * ACC_WIDTH'($signed(north_in));

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_reg <= '0;
        end else if (en) begin
            if (clr_acc) begin
                accum_reg <= $signed(intermediate_product) >>> 8;
            end else begin
                accum_reg <= accum_reg + ($signed(intermediate_product) >>> 8);
            end
        end
    end

    assign acc_out = accum_reg;

    // -------------------------------------------------------------------------
    // A1. Reset must clear pipeline registers within one cycle
    // -------------------------------------------------------------------------
    property p_rst_clears_pipeline;
        @(posedge clk) rst |=> (east_out == '0 && south_out == '0);
    endproperty
    a_rst_clears_pipeline: assert property (p_rst_clears_pipeline)
        else $error("[ASSERT FAIL] a_rst_clears_pipeline [Signed Q8.8]: pipeline not zeroed after rst");

    // -------------------------------------------------------------------------
    // A2. Reset must clear accumulator within one cycle
    // -------------------------------------------------------------------------
    property p_rst_clears_acc;
        @(posedge clk) rst |=> (acc_out == '0);
    endproperty
    a_rst_clears_acc: assert property (p_rst_clears_acc)
        else $error("[ASSERT FAIL] a_rst_clears_acc [Signed Q8.8]: acc_out not zeroed after rst");

    // -------------------------------------------------------------------------
    // A3. East passthrough: east_out must mirror west_in after one en=1 cycle
    // -------------------------------------------------------------------------
    property p_east_passthrough;
        @(posedge clk) disable iff (rst)
        en |=> (east_out == $past(west_in, 1, , @(posedge clk)));
    endproperty
    a_east_passthrough: assert property (p_east_passthrough)
        else $error("[ASSERT FAIL] a_east_passthrough [Signed Q8.8]: east_out=%h, expected=%h",
                    east_out, $past(west_in, 1, , @(posedge clk)));

    // -------------------------------------------------------------------------
    // A4. South passthrough: south_out must mirror north_in after one en=1 cycle
    // -------------------------------------------------------------------------
    property p_south_passthrough;
        @(posedge clk) disable iff (rst)
        en |=> (south_out == $past(north_in, 1, , @(posedge clk)));
    endproperty
    a_south_passthrough: assert property (p_south_passthrough)
        else $error("[ASSERT FAIL] a_south_passthrough [Signed Q8.8]: south_out=%h, expected=%h",
                    south_out, $past(north_in, 1, , @(posedge clk)));

    // -------------------------------------------------------------------------
    // A5. Hold when disabled: east_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_east_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (east_out == $past(east_out, 1, , @(posedge clk)));
    endproperty
    a_east_hold: assert property (p_east_hold)
        else $error("[ASSERT FAIL] a_east_hold [Signed Q8.8]: east_out changed while en=0");

    // -------------------------------------------------------------------------
    // A6. Hold when disabled: south_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_south_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (south_out == $past(south_out, 1, , @(posedge clk)));
    endproperty
    a_south_hold: assert property (p_south_hold)
        else $error("[ASSERT FAIL] a_south_hold [Signed Q8.8]: south_out changed while en=0");

    // -------------------------------------------------------------------------
    // A7. Hold when disabled: acc_out must not change when en=0
    // -------------------------------------------------------------------------
    property p_acc_hold;
        @(posedge clk) disable iff (rst)
        !en |=> (acc_out == $past(acc_out, 1, , @(posedge clk)));
    endproperty
    a_acc_hold: assert property (p_acc_hold)
        else $error("[ASSERT FAIL] a_acc_hold [Signed Q8.8]: acc_out changed while en=0");

    // -------------------------------------------------------------------------
    // A8. No X/Z on acc_out
    // -------------------------------------------------------------------------
    property p_no_x_acc;
        @(posedge clk) disable iff (rst)
        !$isunknown(acc_out);
    endproperty
    a_no_x_acc: assert property (p_no_x_acc)
        else $error("[ASSERT FAIL] a_no_x_acc [Signed Q8.8]: X/Z on acc_out");

    // -------------------------------------------------------------------------
    // A9. No X/Z on east_out
    // -------------------------------------------------------------------------
    property p_no_x_east;
        @(posedge clk) disable iff (rst)
        !$isunknown(east_out);
    endproperty
    a_no_x_east: assert property (p_no_x_east)
        else $error("[ASSERT FAIL] a_no_x_east [Signed Q8.8]: X/Z on east_out");

    // -------------------------------------------------------------------------
    // A10. No X/Z on south_out
    // -------------------------------------------------------------------------
    property p_no_x_south;
        @(posedge clk) disable iff (rst)
        !$isunknown(south_out);
    endproperty
    a_no_x_south: assert property (p_no_x_south)
        else $error("[ASSERT FAIL] a_no_x_south [Signed Q8.8]: X/Z on south_out");

    // -------------------------------------------------------------------------
    // A11. Signed Q8.8 Clear behavior:
    //      acc_out = (sign_ext(west) * sign_ext(north)) >>> 8
    //      Uses $past with explicit clock. Local variables avoided for XSim.
    // -------------------------------------------------------------------------
    property p_acc_clr_loads_product;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) && $past(clr_acc, 1, , @(posedge clk))) |->
        ($signed(acc_out) == ((ACC_WIDTH'($signed($past(west_in,  1, , @(posedge clk)))) *
                               ACC_WIDTH'($signed($past(north_in, 1, , @(posedge clk))))) >>> 8));
    endproperty
    a_acc_clr_loads_product: assert property (p_acc_clr_loads_product)
        else $error("[ASSERT FAIL] a_acc_clr_loads_product [Signed Q8.8]: acc_out=%h (signed=%0d)",
                    acc_out, $signed(acc_out));

    // -------------------------------------------------------------------------
    // A12. Signed Q8.8 Accumulate behavior:
    //      acc_out = prev_acc + (sign_ext(west) * sign_ext(north)) >>> 8
    // -------------------------------------------------------------------------
    property p_acc_accumulate;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) && !$past(clr_acc, 1, , @(posedge clk))) |->
        ($signed(acc_out) == ($signed($past(acc_out, 1, , @(posedge clk))) +
                              ((ACC_WIDTH'($signed($past(west_in,  1, , @(posedge clk)))) *
                                ACC_WIDTH'($signed($past(north_in, 1, , @(posedge clk))))) >>> 8)));
    endproperty
    a_acc_accumulate: assert property (p_acc_accumulate)
        else $error("[ASSERT FAIL] a_acc_accumulate [Signed Q8.8]: acc_out=%h (signed=%0d)",
                    acc_out, $signed(acc_out));

    // -------------------------------------------------------------------------
    // A13. Intermediate product wire integrity (signed)
    // -------------------------------------------------------------------------
    property p_intermediate_product_correct;
        @(posedge clk) disable iff (rst)
        ($signed(intermediate_product) ==
         (ACC_WIDTH'($signed(west_in)) * ACC_WIDTH'($signed(north_in))));
    endproperty
    a_intermediate_product_correct: assert property (p_intermediate_product_correct)
        else $error("[ASSERT FAIL] a_intermediate_product_correct [Signed Q8.8]: product=%h", intermediate_product);

    // -------------------------------------------------------------------------
    // A14. Sign integrity: positive * positive must yield a non-negative result
    // -------------------------------------------------------------------------
    property p_pos_times_pos_is_pos;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) &&
         $past(clr_acc, 1, , @(posedge clk)) &&
         !$past(west_in[DATA_WIDTH-1],  1, , @(posedge clk)) &&
          $past(west_in,  1, , @(posedge clk)) != '0 &&
         !$past(north_in[DATA_WIDTH-1], 1, , @(posedge clk)) &&
          $past(north_in, 1, , @(posedge clk)) != '0) |->
        !acc_out[ACC_WIDTH-1];
    endproperty
    a_pos_times_pos_is_pos: assert property (p_pos_times_pos_is_pos)
        else $error("[ASSERT FAIL] a_pos_times_pos_is_pos [Signed Q8.8]: pos*pos gave acc_out=%h", acc_out);

    // -------------------------------------------------------------------------
    // A15. Sign integrity: positive * negative must yield a negative result
    // -------------------------------------------------------------------------
    property p_pos_times_neg_is_neg;
        @(posedge clk) disable iff (rst)
        ($past(en, 1, , @(posedge clk)) &&
         $past(clr_acc, 1, , @(posedge clk)) &&
         !$past(west_in[DATA_WIDTH-1],  1, , @(posedge clk)) &&
          $past(west_in,  1, , @(posedge clk)) != '0 &&
          $past(north_in[DATA_WIDTH-1], 1, , @(posedge clk))) |->
        acc_out[ACC_WIDTH-1];
    endproperty
    a_pos_times_neg_is_neg: assert property (p_pos_times_neg_is_neg)
        else $error("[ASSERT FAIL] a_pos_times_neg_is_neg [Signed Q8.8]: pos*neg gave acc_out=%h", acc_out);

endmodule
