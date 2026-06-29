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

endmodule
