# Coverage-Driven Verification of a MAC-Based Systolic Array

A SystemVerilog implementation and verification of an 8×8 MAC-based systolic array using a **Coverage-Driven Verification (CDV)** methodology. The design is verified across three arithmetic formats, with a separate variant that augments the testbench with **SystemVerilog Assertions (SVA)**.

**Tool:** Xilinx Vivado 2025.2 (XSim simulator)

---

## Repository Structure

```
.
├── rtl/    
|    ├── cdv/                        # Coverage-Driven Verification (no assertions)
|    │   ├── integer8Bit/          # 8-bit unsigned integer MAC
|    │   │   ├── pe.sv
|    │   │   ├── systolic_array.sv
|    │   │   ├── tb_pkg.sv
|    │   │   └── top_tb.sv
|    │   ├── unsignedQ8.8/                   # 16-bit unsigned Q8.8 fixed-point MAC
|    │   │   ├── pe.sv
|    │   │   ├── systolic_array.sv
|    │   │   ├── tb_pkg.sv
|    │   │   └── top_tb.sv
|    │   └── signedQ8.8/            # 16-bit signed Q8.8 fixed-point MAC
|    │       ├── pe.sv
|    │       ├── systolic_array.sv
|    │       ├── tb_pkg.sv
|    │       └── top_tb.sv
|    │
|    └── cdvwithassertions/        # CDV + embedded SVA assertions
         ├── integer8Bit/
         ├── unsignedQ8.8/
         └── signedQ8.8/
             └── (same file layout as cdv/)
```

Each subdirectory is a self-contained simulation project targeting a specific arithmetic format.

---

## Design Overview

### Processing Element (`pe.sv`)

The atomic compute unit of the systolic array. Each PE performs a **Multiply-Accumulate (MAC)** operation and passes its inputs to its neighbors.

| Port | Direction | Description |
|---|---|---|
| `clk`, `rst` | in | Clock and synchronous reset |
| `en` | in | Enable — gates all register updates |
| `clr_acc` | in | Clears accumulator and loads a fresh product |
| `west_in` | in | Data flowing horizontally (left → right) |
| `north_in` | in | Data flowing vertically (top → bottom) |
| `east_out` | out | `west_in` delayed by one cycle (passthrough) |
| `south_out` | out | `north_in` delayed by one cycle (passthrough) |
| `acc_out` | out | Accumulated MAC result |

**MAC behavior:**
- `en=1, clr_acc=1` → `acc = west_in × north_in` (fresh start)
- `en=1, clr_acc=0` → `acc = acc + west_in × north_in` (accumulate)
- `en=0` → all registers hold their current value

### Systolic Array (`systolic_array.sv`)

An 8×8 grid of PEs instantiated via a `generate` loop. Horizontal wires carry data west-to-east; vertical wires carry data north-to-south. Each PE receives its row's `west_in` and its column's `north_in` from the boundary, then propagates values through internal interconnect wires.

```
Parameters: DATA_WIDTH, ACC_WIDTH, ARRAY_SIZE (default 8)

west_in[0..7] ──→  PE[0][0] ──→ PE[0][1] ──→ ... ──→ PE[0][7]
                      ↓             ↓                      ↓
west_in[1..7] ──→  PE[1][0] ──→ PE[1][1] ──→ ... ──→ PE[1][7]
                      ↓             ↓                      ↓
                     ...           ...                    ...
                      ↓             ↓                      ↓
west_in[7]    ──→  PE[7][0] ──→ PE[7][1] ──→ ... ──→ PE[7][7]
                   ↑       ↑
             north_in[0] north_in[1] ... north_in[7]
```

`array_out[row][col]` holds the accumulated MAC result of `PE[row][col]`.

---

## Arithmetic Formats

| Variant | `DATA_WIDTH` | `ACC_WIDTH` | Number Representation |
|---|---|---|---|
| `8_Bit_Integer` | 8 | 32 | Unsigned 8-bit integer |
| `Q8_8` | 16 | 32 | Unsigned Q8.8 fixed-point (0 to 255.996) |
| `Signed_Q8.8` | 16 | 32 | Signed Q8.8 fixed-point (−128.0 to +127.996) |

The PE and array RTL is parameterized — only `tb_pkg.sv` changes between variants to set the correct widths and constraints.

---

## Verification Methodology

### CDV Flow

```
tb_pkg.sv (parameters, transaction class, coverage class)
    │
    ├─► matrix_transaction   — constrained-random stimulus generator
    ├─► systolic_coverage    — functional coverage collector
    └─► golden scoreboard    — cycle-accurate reference model
          │
          ▼
      top_tb.sv
          │
          ├─ Drives 1500 randomized transactions into the DUT
          ├─ Samples coverage each cycle via cov.sample_direct()
          ├─ Compares DUT outputs against scoreboard (match / mismatch counts)
          └─ Prints a final validation report
```

### `matrix_transaction` (constrained random)

Randomizes `west_in[0:7]`, `north_in[0:7]`, `clr_acc`, and `en` per transaction. Key constraints:

- **Enable:** `en` asserts 90–95% of cycles (high utilization stress).
- **Clear:** `clr_acc` asserts ~25% of cycles.
- **Corner cases:** boundary values (zero / max) weighted equally against mid-range, ensuring edge-case coverage without purely random drift.

### `systolic_coverage` (functional coverage)

Uses a `lane_cover_container` class array (workaround for Vivado XSim's restriction on array-of-covergroup) to track coverage independently per lane. Each lane covergroup has:

- `coverpoint w_val` — bins: zero, max, mid-range
- `coverpoint n_val` — bins: zero, max, mid-range  
- `coverpoint clr_val` — bins: cleared, accumulated

Final coverage is the average `get_inst_coverage()` across all 8 lanes.

### Golden Scoreboard

A cycle-accurate behavioral model inside `top_tb.sv` mirrors the PE pipeline delays using shift registers (`west_delayed`, `north_delayed`). It computes the expected `scoreboard_matrix[r][c]` in parallel with the DUT and compares outputs after each active cycle.

### Simulation Report (printed at end of run)

```
==================================================================================
                   AMD XCRG FUNCTIONAL VALIDATION REPORT
==================================================================================
  Total Scalar Checks Conducted  : <N>
  Mathematical Assertions Passed : <N>
  Hardware Failures / Mismatches : 0
  Final Aggregated Loop Coverage : 100.00 %
==================================================================================
```

Additional metrics: pipeline fill latency, total cycles, active cycles, PE utilization %, and throughput in MOPS (at 100 MHz).

---

## SVA Assertions (`CDV_With_Assertions/`)

The assertion variant embeds SVA directly into the RTL modules. All assertions use explicit clocking events (`@(posedge clk)`) and the `$past(expr, 1, , @(posedge clk))` form required for Vivado XSim compatibility.

### PE Assertions (`pe.sv`) — A1 through A12

| ID | Name | Property |
|---|---|---|
| A1 | `a_rst_clears_pipeline` | `rst |=> east_out == 0 && south_out == 0` |
| A2 | `a_rst_clears_acc` | `rst |=> acc_out == 0` |
| A3 | `a_east_passthrough` | `en |=> east_out == $past(west_in)` |
| A4 | `a_south_passthrough` | `en |=> south_out == $past(north_in)` |
| A5 | `a_east_hold` | `!en |=> east_out == $past(east_out)` |
| A6 | `a_south_hold` | `!en |=> south_out == $past(south_out)` |
| A7 | `a_acc_hold` | `!en |=> acc_out == $past(acc_out)` |
| A8 | `a_no_x_acc` | No X/Z on `acc_out` when out of reset |
| A9 | `a_no_x_east` | No X/Z on `east_out` when out of reset |
| A10 | `a_no_x_south` | No X/Z on `south_out` when out of reset |
| A11 | `a_acc_clr_loads_product` | After `en & clr_acc`: `acc == $past(west_in) × $past(north_in)` |
| A12 | `a_acc_accumulate` | After `en & !clr_acc`: `acc == $past(acc) + $past(west_in) × $past(north_in)` |

### Systolic Array Assertions (`systolic_array.sv`) — SA1 through SA3

| ID | Name | Property |
|---|---|---|
| SA1 | `a_rst_clears_all_outputs` | `rst |=> array_out == '0` (entire output bus) |
| SA2 | `a_no_x_out` | No X/Z on any `array_out[r][c]` when out of reset (generated per PE) |
| SA3 | `a_no_x_west / a_no_x_north` | Boundary inputs carry no X/Z after reset (generated per lane) |

---

## How to Simulate (Vivado 2025.2)

1. Create a new RTL project in Vivado.
2. Add all four `.sv` files from the desired variant folder as simulation sources.
3. Set `top_tb` as the simulation top module.
4. Run behavioral simulation — the TCL console will print the validation report.

To switch arithmetic formats, simply swap the source folder (`8_Bit_Integer`, `Q8_8`, or `Signed_Q8.8`). No other changes are needed.

---

## Key Design Decisions

**Why a `lane_cover_container` class?** Vivado XSim does not support arrays of covergroups (`covergroup cg[N]`). Wrapping each covergroup in a class and instantiating an object array is the standard workaround.

**Why explicit `$past(..., @(posedge clk))` syntax?** Vivado XSim requires an explicit clocking event argument in `$past()` and does not support `$stable()` inside SVA properties without it. All assertions use the explicit form for simulator compatibility.

**Why embed assertions in RTL rather than a separate bind file?** Vivado's XSim has limited support for `bind` in behavioral simulation. Embedding assertions directly in the module ensures they are always active without extra project configuration.
