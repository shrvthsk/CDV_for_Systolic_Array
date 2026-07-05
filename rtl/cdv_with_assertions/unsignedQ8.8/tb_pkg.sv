`timescale 1ns/1ps

//==================================
//CDV with Assertions
//Unsigned Q8.8 tb_pkg.sv
//==================================

package tb_pkg;
    parameter int DATA_WIDTH = 16;  // 16-bit Word Width (8-bit Int, 8-bit Fraction)
    parameter int ACC_WIDTH  = 32;  // 32-bit Accumulator Width (Q24.8 Alignment)
    parameter int ARRAY_SIZE = 8;   // 8x8 Systolic Grid Matrix Size

    class matrix_transaction;
        rand bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_in;
        rand bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_in;
        rand bit clr_acc;
        rand bit en;

        constraint c_enable { en dist {1 := 95, 0 := 5}; }
        constraint c_clear  { clr_acc dist {1 := 25, 0 := 75}; }

        constraint corner_cases {
            foreach (west_in[i]) {
                west_in[i] dist { 
                    16'h0000            := 40,  // Absolute Zero Boundary
                    16'hFFFF            := 40,  // Max Saturation Bound (255.9961)
                    [16'h0001:16'h00FF] := 10,  // Pure Sub-Fractional Space (Integer 0)
                    [16'h0100:16'hFFFE] := 10   // Standard Mid-Range Span
                };
            }
            foreach (north_in[i]) {
                north_in[i] dist { 
                    16'h0000            := 40, 
                    16'hFFFF            := 20, 
                    [16'h0001:16'h00FF] := 20,
                    [16'h0100:16'hFFFE] := 20
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
                    bins zero = {16'h0000};
                    bins max  = {16'hFFFF};
                    bins mid  = { [16'h0001:16'hFFFE] }; 
                }
                coverpoint n_val {
                    bins zero = {16'h0000};
                    bins max  = {16'hFFFF};
                    bins mid  = { [16'h0001:16'hFFFE] }; 
                }
                coverpoint clr_val {
                    bins cleared = {1};
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