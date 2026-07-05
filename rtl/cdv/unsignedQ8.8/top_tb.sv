`timescale 1ns/1ps

//==================================
//Unsigned Q8.8 top_tb.sv
//==================================

module top_tb;
    import tb_pkg::*;

    int active_size = ARRAY_SIZE;   // initialised early so always blocks are safe

    bit clk, rst;
    always #10 clk = ~clk;

    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] west_inputs  = '0;
    logic [ARRAY_SIZE-1:0][DATA_WIDTH-1:0] north_inputs = '0;
    logic clr_acc, en;
    wire  [ARRAY_SIZE-1:0][ARRAY_SIZE-1:0][ACC_WIDTH-1:0] array_outputs;

    systolic_array #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH (ACC_WIDTH),
        .ARRAY_SIZE(ARRAY_SIZE)
    ) dut (
        .clk(clk), .rst(rst), .en(en), .clr_acc(clr_acc),
        .west_in(west_inputs), .north_in(north_inputs),
        .array_out(array_outputs)
    );

    logic [ACC_WIDTH-1:0]  scoreboard_matrix [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic [DATA_WIDTH-1:0] west_delayed      [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    logic [DATA_WIDTH-1:0] north_delayed     [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int r = 0; r < ARRAY_SIZE; r++)
                for (int c = 0; c < ARRAY_SIZE; c++) begin
                    west_delayed[r][c]      <= '0;
                    north_delayed[r][c]     <= '0;
                    scoreboard_matrix[r][c] <= '0;
                end
        end else if (en) begin
            // Reverse-order blocking shifts: each read sees the UPDATED value
            // from the same cycle (models 1-cycle east/south pipeline correctly)
            for (int r = 0; r < active_size; r++)
                for (int c = active_size-1; c >= 0; c--)
                    west_delayed[r][c] = (c == 0) ? west_inputs[r] : west_delayed[r][c-1];

            for (int c = 0; c < active_size; c++)
                for (int r = active_size-1; r >= 0; r--)
                    north_delayed[r][c] = (r == 0) ? north_inputs[c] : north_delayed[r-1][c];

            for (int r = 0; r < active_size; r++)
                for (int c = 0; c < active_size; c++) begin
                    if (clr_acc)
                        scoreboard_matrix[r][c] =
                            $unsigned(west_delayed[r][c] * north_delayed[r][c]) >> 8;
                    else
                        scoreboard_matrix[r][c] = scoreboard_matrix[r][c] +
                            ($unsigned(west_delayed[r][c] * north_delayed[r][c]) >> 8);
                end
        end
    end

    int total_cycles = 0, active_cycles = 0, first_valid_cycle = -1;
    bit pipeline_filled = 0;

    always @(posedge clk) begin
        if (!rst) begin
            total_cycles++;
            if (en) active_cycles++;
            if (!pipeline_filled && active_cycles == active_size) begin
                pipeline_filled   = 1;
                first_valid_cycle = total_cycles;
            end
        end
    end

    matrix_transaction tx;
    systolic_coverage  cov;
    int match_count = 0, mismatch_count = 0;
    real cov_score;

    task automatic check_sb();
        #1;
        for (int r = 0; r < active_size; r++)
            for (int c = 0; c < active_size; c++)
                if (en && scoreboard_matrix[r][c] !== '0) begin
                    if (array_outputs[r][c] === scoreboard_matrix[r][c])
                        match_count++;
                    else begin
                        mismatch_count++;
                        $error("[Q8.8 MISMATCH] PE[%0d][%0d] Expected=%0h  Got=%0h",
                                r, c, scoreboard_matrix[r][c], array_outputs[r][c]);
                    end
                end
    endtask

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
    endtask

    localparam int MAX_RANDOM_ITER = 5000;

    initial begin
        void'($value$plusargs("N=%d", active_size));
        if (active_size < 1 || active_size > ARRAY_SIZE) begin
            $error("[CONFIG] N=%0d out of range [1,%0d].", active_size, ARRAY_SIZE);
            $finish;
        end

        clk     = 0;
        rst     = 1;
        en      = 0;
        clr_acc = 0;
        tx  = new();
        cov = new(active_size);

        $display("\n[INIT] Q8.8 Unsigned Systolic Array - Active Size: %0d x %0d",
                  active_size, active_size);
        repeat (4) @(posedge clk);
        rst = 0;
        $display("[INIT] Reset released.");

        $display("[PHASE-1] Directed stimulus...");
        drive_directed(16'h0000, 16'h0000, 1'b1);  // zero × zero,  clr=1
        drive_directed(16'hFFFF, 16'hFFFF, 1'b0);  // max  × max,   clr=0
        drive_directed(16'h8000, 16'h0100, 1'b1);  // mid  × mid
        drive_directed(16'h0000, 16'hFFFF, 1'b0);  // zero × max  (cross)
        drive_directed(16'hFFFF, 16'h0000, 1'b1);  // max  × zero (cross)

        cov_score = cov.get_coverage();
        $display("[PHASE-1] Done. Coverage = %3.2f%%", cov_score);
        if (cov_score < 100.0)
            $warning("[PHASE-1] Coverage not 100%% - check bin definitions.");

        begin
            int iter = 0;
            bit [MAX_ARRAY_SIZE-1:0][DATA_WIDTH-1:0] w_tmp, n_tmp;

            $display("[PHASE-2] Random verification - %0d iterations...", MAX_RANDOM_ITER);

            while (iter < MAX_RANDOM_ITER) begin
                if (!tx.randomize()) begin $error("Randomize failed"); $finish; end

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

        $display("\n==================================================================================");
        $display("          AMD XCRG Q8.8 FIXED-POINT VALIDATION REPORT                            ");
        $display("==================================================================================");
        $display("  Active Array Size              : %0d x %0d  (compiled at %0d x %0d)",
                  active_size, active_size, ARRAY_SIZE, ARRAY_SIZE);
        $display("  Pipeline Fill Latency          : %0d cycles", first_valid_cycle);
        $display("  Total Simulation Cycles        : %0d", total_cycles);
        $display("  Active (en=1) Cycles           : %0d", active_cycles);
        $display("  PE Utilization                 : %3.2f %%",
                  (real'(active_cycles) / real'(total_cycles)) * 100.0);
        $display("  Throughput (at 100MHz)         : %3.2f MOPS",
                  (real'(active_cycles) / real'(total_cycles)) * 100.0);
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
