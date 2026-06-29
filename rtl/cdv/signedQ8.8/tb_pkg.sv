`timescale 1ns/1ps
// ============================================================================
//  Signed Q8.8 Fixed-Point Systolic Array - Dynamic Testbench Package
//
//  Runtime size: +N=<value>  |  Compile-time default: ARRAY_SIZE below
//  Signed range: 0x0000=0, 0x7FFF=+127.996, 0x8000=-128.0, ..., 0xFFFF=-0.004
// ============================================================================

package tb_pkg;

    parameter int ARRAY_SIZE     = 8;
    parameter int MAX_ARRAY_SIZE = 32;
    parameter int DATA_WIDTH     = 16;  // 16-bit signed Q8.8
    parameter int ACC_WIDTH      = 32;  // 32-bit signed accumulator

    // ── Transaction class ────────────────────────────────────────────────────
    class matrix_transaction;
        rand bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_in;
        rand bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_in;
        rand bit clr_acc;
        rand bit en;

        constraint c_enable { en      dist {1 := 95, 0 := 5};  }
        constraint c_clear  { clr_acc dist {1 := 5,  0 := 95}; }

        // Signed Q8.8: positive [0x0001-0x7FFF], negative [0x8001-0xFFFF]
        constraint corner_cases {
            foreach (west_in[i]) {
                west_in[i] dist {
                    16'h0000            := 20,   // zero
                    16'h7FFF            := 20,   // +127.996 (max positive)
                    16'h8000            := 20,   // -128.0   (max negative)
                    [16'h0001:16'h7FFE] := 20,   // positive mid-range
                    [16'h8001:16'hFFFF] := 20    // negative mid-range
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

    // ── Functional coverage class ────────────────────────────────────────────
    class systolic_coverage;

        class lane_cover_container;
            bit [DATA_WIDTH-1:0] w_val;
            bit [DATA_WIDTH-1:0] n_val;
            bit                  clr_val;

            covergroup lane_cg;
                option.per_instance         = 1;
                type_option.merge_instances = 1;

                cp_west  : coverpoint w_val {
                    bins zero     = {16'h0000};
                    bins max_pos  = {16'h7FFF};
                    bins max_neg  = {16'h8000};
                    bins positive = {[16'h0001:16'h7FFE]};
                    bins negative = {[16'h8001:16'hFFFF]};
                }
                cp_north : coverpoint n_val {
                    bins zero     = {16'h0000};
                    bins max_pos  = {16'h7FFF};
                    bins max_neg  = {16'h8000};
                    bins positive = {[16'h0001:16'h7FFE]};
                    bins negative = {[16'h8001:16'hFFFF]};
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
