`timescale 1ns/1ps

//==================================
//8 Bit Integer tb_pkg.sv
//==================================

package tb_pkg;
    parameter int ARRAY_SIZE     = 8;   // DUT is compiled at this size
    parameter int MAX_ARRAY_SIZE = 32;  // Upper bound for transaction arrays
    parameter int DATA_WIDTH     = 8;
    parameter int ACC_WIDTH      = 32;

    class matrix_transaction;
        rand bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_in;
        rand bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_in;
        rand bit clr_acc;
        rand bit en;

        constraint c_enable { en      dist {1 := 90, 0 := 10}; }
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

    class systolic_coverage;

        class lane_cover_container;
            bit [DATA_WIDTH-1:0] w_val;
            bit [DATA_WIDTH-1:0] n_val;
            bit                  clr_val;

            covergroup lane_cg;
                option.per_instance         = 1;
                type_option.merge_instances = 1;

                cp_west  : coverpoint w_val {
                    bins zero = {8'h00};
                    bins max  = {8'hFF};
                    bins mid  = {[8'h01:8'hFE]};
                }
                cp_north : coverpoint n_val {
                    bins zero = {8'h00};
                    bins max  = {8'hFF};
                    bins mid  = {[8'h01:8'hFE]};
                }
                cp_clr   : coverpoint clr_val {
                    bins cleared     = {1'b1};
                    bins accumulated = {1'b0};
                }
            endgroup

            function new();
                lane_cg = new();
            endfunction

            function void sample_node(
                input bit [DATA_WIDTH-1:0] w,
                input bit [DATA_WIDTH-1:0] n,
                input bit                  c
            );
                w_val   = w;  n_val = n;  clr_val = c;
                lane_cg.sample();
            endfunction

            function real get_lane_coverage();
                return lane_cg.get_inst_coverage();
            endfunction
        endclass

        lane_cover_container lanes[];

        function new(int n);
            lanes = new[n];
            foreach (lanes[i]) lanes[i] = new();
        endfunction

        function void sample_direct(
            input bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] w_matrix,
            input bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] n_matrix,
            input bit                                       clr_sig
        );
            foreach (lanes[i])
                lanes[i].sample_node(w_matrix[i], n_matrix[i], clr_sig);
        endfunction

        function real get_coverage();
            real total = 0.0;
            if (lanes.size() == 0) return 0.0;
            foreach (lanes[i]) total += lanes[i].get_lane_coverage();
            return total / real'(lanes.size());
        endfunction

    endclass

endpackage
