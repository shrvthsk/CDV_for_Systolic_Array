`timescale 1ns/1ps

//==================================
//CDV with Assertions
//Signed Q8.8 tb_pkg.sv
//==================================

package tb_pkg;
    parameter int DATA_WIDTH = 16;  // 16-bit Word Width (8-bit Int, 8-bit Fraction, signed)
    parameter int ACC_WIDTH  = 32;  // 32-bit Signed Accumulator
    parameter int ARRAY_SIZE = 8;   // 8x8 Systolic Grid Matrix Size

    class matrix_transaction;
        rand bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_in;
        rand bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_in;
        rand bit clr_acc;
        rand bit en;

        constraint c_enable { en dist {1 := 95, 0 := 5}; }
        constraint c_clear  { clr_acc dist {1 := 5, 0 := 95}; }

        constraint corner_cases {
            foreach (west_in[i]) {
                west_in[i] dist {
                    16'h0000            := 20,  // Zero
                    16'h7FFF            := 20,  // +127.996 (max positive)
                    16'h8000            := 20,  // -128.0   (max negative)
                    [16'h0001:16'h7FFE] := 20,  // Positive mid-range
                    [16'h8001:16'hFFFF] := 20   // Negative mid-range
                };
            }
            foreach (north_in[i]) {
                north_in[i] dist {
                    16'h0000            := 20,
                    16'h7FFF            := 20,
                    16'h8000            := 20,
                    [16'h0001:16'h7FFE] := 20,
                    [16'h8001:16'hFFFF] := 20
                };
            }
        }
    endclass

    class systolic_coverage;

        class lane_cover_container;
            covergroup lane_cg;
                option.per_instance = 1;
                type_option.merge_instances = 1;

                coverpoint w_val {
                    bins zero     = {16'h0000};
                    bins max_pos  = {16'h7FFF};             // +127.996
                    bins max_neg  = {16'h8000};             // -128.0
                    bins positive = {[16'h0001:16'h7FFE]};  // positive range
                    bins negative = {[16'h8001:16'hFFFF]};  // negative range
                }
                coverpoint n_val {
                    bins zero     = {16'h0000};
                    bins max_pos  = {16'h7FFF};
                    bins max_neg  = {16'h8000};
                    bins positive = {[16'h0001:16'h7FFE]};
                    bins negative = {[16'h8001:16'hFFFF]};
                }
                coverpoint clr_val {
                    bins cleared     = {1};
                    bins accumulated = {0};
                }
            endgroup

            bit [DATA_WIDTH-1:0] w_val;
            bit [DATA_WIDTH-1:0] n_val;
            bit clr_val;

            function new();
                lane_cg = new();
            endfunction

            function void sample_node(bit [DATA_WIDTH-1:0] w, bit [DATA_WIDTH-1:0] n, bit c);
                w_val   = w;
                n_val   = n;
                clr_val = c;
                lane_cg.sample();
            endfunction
        endclass

        lane_cover_container lanes[ARRAY_SIZE];

        function new();
            foreach (lanes[i]) begin
                lanes[i] = new();
            end
        endfunction

        function void sample_direct(
            bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] w_matrix,
            bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] n_matrix,
            bit clr_sig
        );
            foreach (lanes[i]) begin
                lanes[i].sample_node(w_matrix[i], n_matrix[i], clr_sig);
            end
        endfunction

        function real get_coverage();
            real aggregated_score = 0.0;
            foreach (lanes[i]) begin
                aggregated_score += lanes[i].lane_cg.get_inst_coverage();
            end
            return (aggregated_score / ARRAY_SIZE);
        endfunction
    endclass
endpackage