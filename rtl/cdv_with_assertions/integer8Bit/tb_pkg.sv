`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 28.06.2026 10:23:10
// Design Name: 
// Module Name: tb_pkg
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

package tb_pkg;
    // Parameters for 8-bit Pure Integer Architecture
    parameter int DATA_WIDTH = 8;   // 8-bit Input Data Width
    parameter int ACC_WIDTH  = 32;  // 32-bit Accumulator Width (Prevents Overflow)
    parameter int ARRAY_SIZE = 8;   // 8x8 Systolic Grid Matrix Size

    // Transaction Stimulus Container Class
    class matrix_transaction;
        rand bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_in;
        rand bit [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_in;
        rand bit clr_acc;
        rand bit en;

        constraint c_enable { en dist {1 := 90, 0 := 10}; }
        constraint c_clear  { clr_acc dist {1 := 25, 0 := 75}; }

        constraint corner_cases {
            foreach (west_in[i]) {
                west_in[i] dist { 
                    8'h00         := 33,  
                    8'hFF         := 33,  
                    [8'h01:8'hFE] := 34   
                };
            }
            foreach (north_in[i]) {
                north_in[i] dist { 
                    8'h00         := 33, 
                    8'hFF         := 33, 
                    [8'h01:8'hFE] := 34 
                };
            }
        }
    endclass

    // FIXED COVERAGE CONTAINER: 
    // We use an explicit container class for the covergroup to bypass Vivado's array limitation.
    class systolic_coverage;
        
        // 1. Declare a simple wrapper class to house the individual covergroup
        class lane_cover_container;
            covergroup lane_cg;
                option.per_instance = 1;
                type_option.merge_instances = 1; 
                
                coverpoint w_val {
                    bins zero = {8'h00};
                    bins max  = {8'hFF};
                    bins mid  = {[8'h01:8'hFE]};
                }
                coverpoint n_val {
                    bins zero = {8'h00};
                    bins max  = {8'hFF};
                    bins mid  = {[8'h01:8'hFE]};
                }
                coverpoint clr_val {
                    bins cleared = {1};
                    bins accumulated = {0};
                }
            endgroup

            // Input variables used for sampling
            bit [DATA_WIDTH-1:0] w_val;
            bit [DATA_WIDTH-1:0] n_val;
            bit clr_val;

            function new();
                lane_cg = new();
            endfunction

            // Sample wrapper function
            function void sample_node(bit [DATA_WIDTH-1:0] w, bit [DATA_WIDTH-1:0] n, bit c);
                w_val   = w;
                n_val   = n;
                clr_val = c;
                lane_cg.sample();
            endfunction
        endclass

        // 2. Instantiate an array of these container objects instead
        lane_cover_container lanes[ARRAY_SIZE];

        function new();
            foreach (lanes[i]) begin
                lanes[i] = new();
            end
        endfunction

        // Direct explicit loop sampling trigger method
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
