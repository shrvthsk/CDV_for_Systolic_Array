`timescale 1ns/1ps

//==================================
//CDV with Assertions
//8 Bit Integer top_tb.sv
//==================================

module top_tb;
    import tb_pkg::*;

    // Physical Evaluation Clocking Nodes
    bit clk;
    bit rst;

    // Driver Connection Interfaces
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_inputs;
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_inputs;
    logic clr_acc;
    logic en;
    wire  [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][ACC_WIDTH-1:0] array_outputs;

    int total_cycles      = 0;
    int active_cycles     = 0;
    int first_valid_cycle = -1;
    bit pipeline_filled   = 0;

    always #10 clk = ~clk;

    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk(clk),
        .rst(rst),
        .en(en),
        .clr_acc(clr_acc),
        .west_in(west_inputs),
        .north_in(north_inputs),
        .array_out(array_outputs)
    );

    matrix_transaction tx;
    systolic_coverage   cov;

    logic [ACC_WIDTH-1:0] scoreboard_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    logic [DATA_WIDTH-1:0] west_delayed  [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic [DATA_WIDTH-1:0] north_delayed [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    bit en_prev;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            en_prev <= '0;
            for (int r = 0; r < ARRAY_SIZE; r++) begin
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    west_delayed[r][c]      <= '0;
                    north_delayed[r][c]     <= '0;
                    scoreboard_matrix[r][c] <= '0;
                end
            end
        end else begin
            en_prev <= en;
            for (int r = 0; r < ARRAY_SIZE; r++) begin
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    if (en) begin
                        west_delayed[r][c]  <= (c == 0) ? west_inputs[r]    : west_delayed[r][c-1];
                        north_delayed[r][c] <= (r == 0) ? north_inputs[c]   : north_delayed[r-1][c];

                        if (clr_acc)
                            scoreboard_matrix[r][c] <= $unsigned(
                                ((c == 0) ? west_inputs[r]  : west_delayed[r][c-1]) *
                                ((r == 0) ? north_inputs[c] : north_delayed[r-1][c])
                            );
                        else
                            scoreboard_matrix[r][c] <= scoreboard_matrix[r][c] + $unsigned(
                                ((c == 0) ? west_inputs[r]  : west_delayed[r][c-1]) *
                                ((r == 0) ? north_inputs[c] : north_delayed[r-1][c])
                            );
                    end
                end
            end
        end
    end

    int match_count    = 0;
    int mismatch_count = 0;
    real final_coverage_score = 0.0;

    always @(posedge clk) begin
        if (!rst) begin
            total_cycles++;
            if (en) active_cycles++;
            if (!pipeline_filled && active_cycles == 8) begin
                pipeline_filled   = 1;
                first_valid_cycle = total_cycles;
            end
        end
    end

    // =========================================================================
    // TB-A1: Scoreboard must never carry X/Z values after reset.
    //        If this fires, the reference model itself has an issue.
    // =========================================================================
    genvar sr, sc;
    generate
        for (sr = 0; sr < ARRAY_SIZE; sr++) begin : sb_assert_row
            for (sc = 0; sc < ARRAY_SIZE; sc++) begin : sb_assert_col
                a_sb_no_x: assert property (
                    @(posedge clk) disable iff (rst)
                    !$isunknown(scoreboard_matrix[sr][sc])
                ) else $error("[TB ASSERT FAIL] a_sb_no_x: X/Z in scoreboard[%0d][%0d] - reference model error", sr, sc);
            end
        end
    endgenerate

    initial begin
        clk     = 0;
        rst     = 1;
        en      = 0;
        clr_acc = 0;
        west_inputs  = '0;
        north_inputs = '0;

        tx  = new();
        cov = new();

        repeat (4) @(posedge clk);
        rst = 0;

        // =====================================================================
        // IA1. Post-reset sanity: all DUT outputs must be zero immediately
        //      after reset is deasserted.
        // =====================================================================
        @(posedge clk);
        for (int r = 0; r < ARRAY_SIZE; r++) begin
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                assert (array_outputs[r][c] === '0)
                    else $error("[IA1 FAIL] Post-reset: array_outputs[%0d][%0d] = %h (expected 0)",
                                r, c, array_outputs[r][c]);
            end
        end
        $display("[SYSTEM_START] Hardware reset released. Post-reset assertion passed. Initiating Flat Array Integer Sweep...");

        for (int transaction_idx = 0; transaction_idx < 1500; transaction_idx++) begin

            // =================================================================
            // IA2. Randomization must always succeed.
            //      $fatal stops simulation immediately; this is a fatal error.
            // =================================================================
            assert (tx.randomize())
                else $fatal(1, "[IA2 FAIL] Randomization failed at transaction %0d", transaction_idx);

            @(posedge clk);
            en           <= tx.en;
            clr_acc      <= tx.clr_acc;
            west_inputs  <= tx.west_in;
            north_inputs <= tx.north_in;

            cov.sample_direct(tx.west_in, tx.north_in, tx.clr_acc);

            #1;
            for (int r = 0; r < ARRAY_SIZE; r++) begin
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    if (en_prev) begin
                        // =============================================================
                        // IA3. Functional correctness assertion: DUT must match golden
                        //      scoreboard for every active PE on every checked cycle.
                        // =============================================================
                        assert (array_outputs[r][c] === scoreboard_matrix[r][c]) begin
                            match_count++;
                        end else begin
                            mismatch_count++;
                            $error("[IA3 FAIL] PE[%0d][%0d] Expected: %h  Got: %h  @ t=%0t",
                                   r, c, scoreboard_matrix[r][c], array_outputs[r][c], $time);
                        end
                    end
                end
            end
        end

        $display("  Pipeline Fill Latency          : %0d cycles", first_valid_cycle);
        $display("  Total Simulation Cycles        : %0d", total_cycles);
        $display("  Active (en=1) Cycles           : %0d", active_cycles);
        $display("  PE Utilization                 : %3.2f %%",
                  (real'(active_cycles) / real'(total_cycles)) * 100.0);
        $display("  Throughput (at 100MHz)         : %3.2f MOPS",
                  (real'(active_cycles) / real'(total_cycles)) * 100.0);

        repeat (40) @(posedge clk);

        final_coverage_score = cov.get_coverage();

        // =====================================================================
        // IA4. End-of-simulation coverage gate assertion.
        //      Coverage must reach at least 95% for the run to be valid.
        // =====================================================================
        assert (final_coverage_score >= 95.0)
            else $warning("[IA4 WARN] Coverage gate failed: achieved %3.2f%% (threshold: 95%%)",
                          final_coverage_score);

        $display("\n==================================================================================");
        $display("                   AMD XCRG FUNCTIONAL VALIDATION REPORT                          ");
        $display("==================================================================================");
        $display("  Total Scalar Checks Conducted  : %0d", (match_count + mismatch_count));
        $display("  Mathematical Assertions Passed : %0d", match_count);
        $display("  Hardware Failures / Mismatches : %0d", mismatch_count);
        $display("  Final Aggregated Loop Coverage : %3.2f %%", final_coverage_score);
        $display("==================================================================================\n");

        // =====================================================================
        // IA5. Zero-mismatch gate: simulation is only clean if no mismatches.
        // =====================================================================
        assert (mismatch_count == 0)
            else $error("[IA5 FAIL] %0d functional mismatch(es) detected - DUT is BROKEN", mismatch_count);

        $finish;
    end
endmodule
