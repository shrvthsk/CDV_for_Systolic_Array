`timescale 1ns/1ps

//==================================
//Unsigned Q8.8 pe.sv
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

    logic [ACC_WIDTH-1:0] accum_reg;
    logic [31:0] intermediate_product;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            east_out  <= '0;
            south_out <= '0;
        end else if (en) begin
            east_out  <= west_in;
            south_out <= north_in;
        end
    end

    assign intermediate_product = $unsigned(west_in * north_in);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            accum_reg <= '0;
        end else if (en) begin
            if (clr_acc) begin
                accum_reg <= intermediate_product >> 8; // Right-shift 8 realigns fraction bits
            end else begin
                accum_reg <= accum_reg + (intermediate_product >> 8);
            end
        end
    end

    assign acc_out = accum_reg;

endmodule