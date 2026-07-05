`timescale 1ns/1ps

//==================================
//8 Bit Integer pe.sv
//==================================

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

endmodule