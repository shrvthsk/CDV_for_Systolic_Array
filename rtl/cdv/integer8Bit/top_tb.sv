`timescale 1ns/1ps
// ============================================================================
//  8-Bit Integer Systolic Array - Dynamic Testbench
//
//  Runtime size selection:  +N=<value>  (default = ARRAY_SIZE from package)
//  Coverage guarantee:      Directed phase explicitly hits every bin,
//                           followed by constrained-random verification.
// ============================================================================

module top_tb;
    import tb_pkg::*;

    // ── Runtime array size (set before any always block fires) ───────────────
    // Initialised to ARRAY_SIZE so always blocks see a valid value from t=0.
    // The initial block reads +N and may update it before rst is released.
    int active_size = ARRAY_SIZE;

    // ── Clock / reset ────────────────────────────────────────────────────────
    bit clk, rst;
    always #10 clk = ~clk;

    // ── DUT I/O - width fixed at compile-time ARRAY_SIZE ────────────────────
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_inputs  = '0;
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_inputs = '0;
    logic clr_acc, en;
    wire  [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][ACC_WIDTH-1:0] array_outputs;

    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .en       (en),
        .clr_acc  (clr_acc),
        .west_in  (west_inputs),
        .north_in (north_inputs),
        .array_out(array_outputs)
    );

    // ── Reference scoreboard ─────────────────────────────────────────────────
    // NBA-based pipeline delay model - matches DUT's 1-cycle east/south pass.
    // Only indices [0:active_size-1] are computed; the rest stay zero.
    logic [ACC_WIDTH-1:0]  scoreboard_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic [DATA_WIDTH-1:0] west_delayed      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic [DATA_WIDTH-1:0] north_delayed     [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    bit                    en_prev;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            en_prev <= '0;
            for (int r = 0; r < ARRAY_SIZE; r++)
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    west_delayed[r][c]      <= '0;
                    north_delayed[r][c]     <= '0;
                    scoreboard_matrix[r][c] <= '0;
                end
        end else begin
            en_prev <= en;
            // Only model active lanes; loops use runtime active_size
            for (int r = 0; r < active_size; r++) begin
                for (int c = 0; c < active_size; c++) begin
                    if (en) begin
                        west_delayed[r][c]  <=
                            (c == 0) ? west_inputs[r]    : west_delayed[r][c-1];
                        north_delayed[r][c] <=
                            (r == 0) ? north_inputs[c]   : north_delayed[r-1][c];

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

    // ── Performance counters ─────────────────────────────────────────────────
    int total_cycles = 0, active_cycles = 0, first_valid_cycle = -1;
    bit pipeline_filled = 0;

    always @(posedge clk) begin
        if (!rst) begin
            total_cycles++;
            if (en) active_cycles++;
            // Pipeline fills after active_size enabled cycles
            if (!pipeline_filled && active_cycles == active_size) begin
                pipeline_filled   = 1;
                first_valid_cycle = total_cycles;
            end
        end
    end

    // ── TB objects ───────────────────────────────────────────────────────────
    matrix_transaction tx;
    systolic_coverage  cov;
    int match_count = 0, mismatch_count = 0;
    real cov_score;

    // ── Scoreboard check - called #1 after each posedge ─────────────────────
    // Uses en_prev so the check is gated on the SAME en that updated the SB.
    task automatic check_sb();
        #1;
        for (int r = 0; r < active_size; r++)
            for (int c = 0; c < active_size; c++)
                if (en_prev) begin
                    if (array_outputs[r][c] === scoreboard_matrix[r][c])
                        match_count++;
                    else begin
                        mismatch_count++;
                        $error("[MISMATCH] PE[%0d][%0d] Expected=%0h  Got=%0h",
                                r, c, scoreboard_matrix[r][c], array_outputs[r][c]);
                    end
                end
    endtask

    // ── Directed stimulus - drives w_val × n_val to ALL active lanes ─────────
    // Guarantees a specific bin is hit on every lane simultaneously.
    task automatic drive_directed(
        input bit [DATA_WIDTH-1:0] w_val,
        input bit [DATA_WIDTH-1:0] n_val,
        input bit                  clr
    );
        bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] w_tmp = '0;
        bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] n_tmp = '0;
        @(posedge clk);
        en      <= 1;
        clr_acc <= clr;
        for (int i = 0; i < active_size; i++) begin
            west_inputs[i]  <= w_val;
            north_inputs[i] <= n_val;
            w_tmp[i]         = w_val;
            n_tmp[i]         = n_val;
        end
        cov.sample_direct(w_tmp, n_tmp, clr);
        // No scoreboard check here - pipeline not stable during priming
    endtask

    // ── Main ─────────────────────────────────────────────────────────────────
    localparam int MAX_RANDOM_ITER = 5000;

    initial begin
        // ── Step 1: resolve runtime N ────────────────────────────────────────
        void'($value$plusargs("N=%d", active_size));
        if (active_size < 1 || active_size > ARRAY_SIZE) begin
            $error("[CONFIG] N=%0d is out of range [1, %0d]. " ,
                    active_size, ARRAY_SIZE,
                   "Recompile with a larger ARRAY_SIZE in tb_pkg.sv.");
            $finish;
        end

        // ── Step 2: initialise ────────────────────────────────────────────────
        clk     = 0;
        rst     = 1;
        en      = 0;
        clr_acc = 0;
        tx  = new();
        cov = new(active_size);   // dynamic coverage for exactly N lanes

        $display("\n[INIT] 8-bit Integer Systolic Array - Active Size: %0d x %0d  (ARRAY_SIZE=%0d)",
                  active_size, active_size, ARRAY_SIZE);

        repeat (4) @(posedge clk);
        rst = 0;
        $display("[INIT] Reset released.");

        // ══ PHASE 1: Directed corner-case stimulus ════════════════════════════
        // Each transaction drives all active_size lanes to the SAME value,
        // so every lane hits every bin in exactly 5 transactions.
        // Bin map:
        //   cp_west / cp_north : zero(0x00), max(0xFF), mid(0x01-0xFE)
        //   cp_clr             : cleared(1), accumulated(0)
        $display("[PHASE-1] Directed stimulus - guaranteeing 100%% bin coverage...");

        drive_directed(8'h00, 8'h00, 1'b1);  // zero × zero,  clr=cleared
        drive_directed(8'hFF, 8'hFF, 1'b0);  // max  × max,   clr=accumulated
        drive_directed(8'h7F, 8'h01, 1'b1);  // mid  × mid
        drive_directed(8'h00, 8'hFF, 1'b0);  // zero × max   (cross)
        drive_directed(8'hFF, 8'h00, 1'b1);  // max  × zero  (cross)

        cov_score = cov.get_coverage();
        $display("[PHASE-1] Done. Coverage = %3.2f%%  (expected 100.00%%)", cov_score);
        if (cov_score < 100.0)
            $warning("[PHASE-1] Coverage not 100%% after directed phase - check bin definitions.");

        // ══ PHASE 2: Constrained-random functional verification ═══════════════
        begin
            int iter = 0;
            bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] w_tmp, n_tmp;

            $display("[PHASE-2] Random verification - %0d iterations...", MAX_RANDOM_ITER);

            while (iter < MAX_RANDOM_ITER) begin
                if (!tx.randomize()) begin $error("Randomize failed at iter %0d", iter); $finish; end

                @(posedge clk);
                en      <= tx.en;
                clr_acc <= tx.clr_acc;
                w_tmp = '0;  n_tmp = '0;
                for (int i = 0; i < active_size; i++) begin
                    west_inputs[i]  <= tx.west_in[i];
                    north_inputs[i] <= tx.north_in[i];
                    w_tmp[i]         = tx.west_in[i];
                    n_tmp[i]         = tx.north_in[i];
                end
                cov.sample_direct(w_tmp, n_tmp, tx.clr_acc);
                check_sb();

                iter++;
                if (iter % 1000 == 0)
                    $display("[PHASE-2] iter=%0d  coverage=%3.2f%%", iter, cov.get_coverage());
            end

            cov_score = cov.get_coverage();
        end

        repeat (40) @(posedge clk);

        // ══ Final Report ══════════════════════════════════════════════════════
        $display("\n==================================================================================");
        $display("           8-BIT INTEGER SYSTOLIC ARRAY VALIDATION REPORT                        ");
        $display("==================================================================================");
        $display("  Active Array Size              : %0d x %0d  (compiled at %0d x %0d)",
                  active_size, active_size, ARRAY_SIZE, ARRAY_SIZE);
        $display("  Pipeline Fill Latency          : %0d cycles", first_valid_cycle);
        $display("  Total Simulation Cycles        : %0d", total_cycles);
        $display("  Active (en=1) Cycles           : %0d", active_cycles);
        $display("  PE Utilization                 : %3.2f %%",
                  (real'(active_cycles) / real'(total_cycles)) * 100.0);
        $display("  Random Iterations Executed     : %0d", MAX_RANDOM_ITER);
        $display("  Total Scalar Checks            : %0d", match_count + mismatch_count);
        $display("  Assertions Passed              : %0d", match_count);
        $display("  Hardware Mismatches            : %0d", mismatch_count);
        $display("  Final Coverage Score           : %3.4f %%", cov_score);
        $display("  Coverage Goal (100%%) Met       : %s",
                  (cov_score >= 100.0) ? "YES [PASS]" : "NO  [FAIL]");
        $display("==================================================================================\n");
        $finish;
    end

endmodule
