`timescale 1ns / 1ps

module systolic_array #(
    parameter int DATA_WIDTH = 8,
    parameter int ACC_WIDTH  = 32,
    parameter int ARRAY_SIZE = 8
)(
    input  logic                                                 clk,
    input  logic                                                 rst,
    input  logic                                                 en,
    input  logic                                                 clr_acc,
    input  logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0]                west_in,
    input  logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0]                north_in,
    output logic [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][ACC_WIDTH-1:0] array_out
);

    // Internal interconnect structural wire declarations
    wire [DATA_WIDTH-1:0] horiz_wires [0:ARRAY_SIZE-1][0:ARRAY_SIZE];
    wire [DATA_WIDTH-1:0] vert_wires  [0:ARRAY_SIZE][0:ARRAY_SIZE-1];

    // Map external boundary vector buses to internal grid routing wires
    genvar i;
    generate
        for (i = 0; i < ARRAY_SIZE; i++) begin : boundary_binding
            assign horiz_wires[i][0] = west_in[i];
            assign vert_wires[0][i]  = north_in[i];
        end
    endgenerate

    // 2D Spatial Struct Generation Instantiation Block
    genvar row, col;
    generate
        for (row = 0; row < ARRAY_SIZE; row++) begin : row_space
            for (col = 0; col < ARRAY_SIZE; col++) begin : col_space
                pe #(
                    .DATA_WIDTH(DATA_WIDTH),
                    .ACC_WIDTH(ACC_WIDTH)
                ) pe_node (
                    .clk(clk),
                    .rst(rst),
                    .en(en),
                    .clr_acc(clr_acc),
                    .west_in(horiz_wires[row][col]),
                    .north_in(vert_wires[row][col]),
                    .east_out(horiz_wires[row][col+1]),
                    .south_out(vert_wires[row+1][col]),
                    .acc_out(array_out[row][col])
                );
            end
        end
    endgenerate

    // =========================================================================
    // SVA ASSERTIONS - Systolic Array (8-Bit Integer)
    // =========================================================================

    // -------------------------------------------------------------------------
    // SA1. After reset, all array outputs must be zero within one cycle.
    //      Checks entire packed output bus at once.
    // -------------------------------------------------------------------------
    property p_rst_clears_all_outputs;
        @(posedge clk) rst |=> (array_out == '0);
    endproperty
    a_rst_clears_all_outputs: assert property (p_rst_clears_all_outputs)
        else $error("[ASSERT FAIL] a_rst_clears_all_outputs: array_out not fully cleared after rst");

    // -------------------------------------------------------------------------
    // SA2. No X/Z on any array output when not in reset.
    //      Uses a generate loop so each PE output is individually labeled.
    // -------------------------------------------------------------------------
    genvar ar, ac;
    generate
        for (ar = 0; ar < ARRAY_SIZE; ar++) begin : assert_row
            for (ac = 0; ac < ARRAY_SIZE; ac++) begin : assert_col
                a_no_x_out: assert property (
                    @(posedge clk) disable iff (rst)
                    !$isunknown(array_out[ar][ac])
                ) else $error("[ASSERT FAIL] a_no_x_out: X/Z on array_out[%0d][%0d]", ar, ac);
            end
        end
    endgenerate

    // -------------------------------------------------------------------------
    // SA3. Boundary inputs to west and north must never carry X/Z values
    //      once reset is released (guards upstream driver correctness)
    // -------------------------------------------------------------------------
    genvar bi;
    generate
        for (bi = 0; bi < ARRAY_SIZE; bi++) begin : assert_boundary
            a_no_x_west: assert property (
                @(posedge clk) disable iff (rst)
                !$isunknown(west_in[bi])
            ) else $error("[ASSERT FAIL] a_no_x_west: X/Z on west_in[%0d]", bi);

            a_no_x_north: assert property (
                @(posedge clk) disable iff (rst)
                !$isunknown(north_in[bi])
            ) else $error("[ASSERT FAIL] a_no_x_north: X/Z on north_in[%0d]", bi);
        end
    endgenerate

endmodule

