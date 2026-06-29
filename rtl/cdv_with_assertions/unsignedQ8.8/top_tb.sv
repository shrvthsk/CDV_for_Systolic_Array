`timescale 1ns/1ps

module top_tb;
    import tb_pkg::*;

    bit clk;
    bit rst;

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

    // Unit Under Test Instantiation
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

    int match_count    = 0;
    int mismatch_count = 0;
    real final_coverage_score = 0.0;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int r = 0; r < ARRAY_SIZE; r++) begin
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    west_delayed[r][c]      <= '0;
                    north_delayed[r][c]     <= '0;
                    scoreboard_matrix[r][c] <= '0;
                end
            end
        end else if (en) begin
            for (int r = 0; r < ARRAY_SIZE; r++) begin
                for (int c = ARRAY_SIZE-1; c >= 0; c--) begin
                    if (c == 0) west_delayed[r][c] = west_inputs[r];
                    else        west_delayed[r][c] = west_delayed[r][c-1];
                end
            end

            for (int c = 0; c < ARRAY_SIZE; c++) begin
                for (int r = ARRAY_SIZE-1; r >= 0; r--) begin
                    if (r == 0) north_delayed[r][c] = north_inputs[c];
                    else        north_delayed[r][c] = north_delayed[r-1][c];
                end
            end

            for (int r = 0; r < ARRAY_SIZE; r++) begin
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    if (clr_acc) begin
                        scoreboard_matrix[r][c] = $unsigned(west_delayed[r][c] * north_delayed[r][c]) >> 8;
                    end else begin
                        scoreboard_matrix[r][c] = scoreboard_matrix[r][c] +
                                                  ($unsigned(west_delayed[r][c] * north_delayed[r][c]) >> 8);
                    end
                end
            end
        end
    end

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
    // TESTBENCH CONCURRENT ASSERTION
    // =========================================================================
    // TB-A1: Scoreboard must never carry X/Z values after reset.
    // =========================================================================
    genvar sr, sc;
    generate
        for (sr = 0; sr < ARRAY_SIZE; sr++) begin : sb_assert_row
            for (sc = 0; sc < ARRAY_SIZE; sc++) begin : sb_assert_col
                a_sb_no_x: assert property (
                    @(posedge clk) disable iff (rst)
                    !$isunknown(scoreboard_matrix[sr][sc])
                ) else $error("[TB ASSERT FAIL] a_sb_no_x [Q8.8]: X/Z in scoreboard[%0d][%0d]", sr, sc);
            end
        end
    endgenerate

    // =========================================================================
    // MAIN STIMULUS + IMMEDIATE ASSERTION CHECKER
    // =========================================================================
    initial begin
        clk     = 0;
        rst     = 1;
        en      = 0;
        clr_acc = 0;
        west_inputs  = '0;
        north_inputs = '0;

        tx  = new();
        cov = new();

        for (int r = 0; r < ARRAY_SIZE; r++) begin
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                scoreboard_matrix[r][c] = '0;
            end
        end

        repeat (4) @(posedge clk);
        rst = 0;

        // =====================================================================
        // IA1. Post-reset sanity: all DUT outputs must be zero
        // =====================================================================
        @(posedge clk);
        for (int r = 0; r < ARRAY_SIZE; r++) begin
            for (int c = 0; c < ARRAY_SIZE; c++) begin
                assert (array_outputs[r][c] === '0)
                    else $error("[IA1 FAIL] Post-reset: array_outputs[%0d][%0d] = %h (expected 0)",
                                r, c, array_outputs[r][c]);
            end
        end
        $display("[SYSTEM_START] Reset released. Post-reset assertion passed. Executing Q8.8 Spatial Wavefront Validation...");

        // 2000 loops to ensure convergence across all 16-bit coverage bins
        for (int transaction_idx = 0; transaction_idx < 2000; transaction_idx++) begin

            // =================================================================
            // IA2. Randomization must always succeed
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
                    // Gate check on en (broadcast) and non-zero scoreboard
                    if (en && scoreboard_matrix[r][c] !== '0) begin
                        // =============================================================
                        // IA3. Q8.8 Functional correctness assertion
                        // =============================================================
                        assert (array_outputs[r][c] === scoreboard_matrix[r][c]) begin
                            match_count++;
                        end else begin
                            mismatch_count++;
                            $error("[IA3 FAIL] [Q8.8] PE[%0d][%0d] Expected: %h  Got: %h  @ t=%0t",
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
        // IA4. Coverage gate assertion
        // =====================================================================
        assert (final_coverage_score >= 95.0)
            else $warning("[IA4 WARN] Coverage gate failed: achieved %3.2f%% (threshold: 95%%)",
                          final_coverage_score);

        $display("\n==================================================================================");
        $display("               AMD XCRG Q8.8 FIXED-POINT VALIDATION REPORT                         ");
        $display("==================================================================================");
        $display("  Total Scalar Checks Conducted  : %0d", (match_count + mismatch_count));
        $display("  Mathematical Assertions Passed : %0d", match_count);
        $display("  Hardware Failures / Mismatches : %0d", mismatch_count);
        $display("  Final Aggregated Loop Coverage : %3.4f %%", final_coverage_score);
        $display("==================================================================================\n");

        // =====================================================================
        // IA5. Zero-mismatch gate
        // =====================================================================
        assert (mismatch_count == 0)
            else $error("[IA5 FAIL] %0d functional mismatch(es) - DUT is BROKEN", mismatch_count);

        $finish;
    end
endmodule
