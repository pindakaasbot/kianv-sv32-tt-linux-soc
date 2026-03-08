# KianV SV32 TT Linux SoC — Build Experiments Log

## Overview

Fork: [pindakaasbot/kianv-sv32-tt-linux-soc](https://github.com/pindakaasbot/kianv-sv32-tt-linux-soc)
Upstream: [splinedrive/kianv-sv32-tt-linux-soc](https://github.com/splinedrive/kianv-sv32-tt-linux-soc)
Die size (8x4): 1724.16 × 710.64 µm
Target: IHP SG13G2 via Tiny Tapeout (ttihp26a)

## SRAM Macros Used

| Macro | Size (µm) | Purpose |
|-------|-----------|---------|
| RM_IHPSG13_2P_64x32_c2 | 702.83 × 74.87 | Register file (1x) |
| RM_IHPSG13_1P_64x64_c2_bm_bist | 784.48 × 64.36 | Cache (2x: icache + dcache) |
| RM_IHPSG13_1P_256x64_c2_bm_bist | 784.48 × 118.78 | Cache (abandoned — too slow) |

## Key Fixes Discovered

### 1. Yosys specify block incompatibility
- **Symptom**: `ERROR: syntax error, unexpected ','` in `RM_IHPSG13_1P_64x64_c2_bm_bist.v:139`
- **Cause**: IHP PDK Verilog model has `$setuphold` timing checks in `specify` blocks; Yosys can't parse these
- **Fix**: Replace PDK model with clean behavioral model (synthesis stub + behavioral sim)
- **Commit**: `50a351c`

### 2. Liberty file max_capacitance bug (64x64 SRAM)
- **Symptom**: `[RSZ-0169] Max cap for driver ...A_DOUT[9]... is unreasonably small 0.000pF`
- **Cause**: All three 64x64 `.lib` files have `max_capacitance : "6.4e-14"` — value in Farads instead of picoFarads (should be `0.064` pF). The 256x64 libs correctly use `0.064`.
- **Fix**: `sed` replace in all 3 corner lib files
- **Commit**: `1e0b1d7`

### 3. prBoundary layer missing from SRAM GDS files
- **Symptom**: `Failed to extract PR boundary from GDSII view of macro`
- **Cause**: IHP PDK SRAM GDS files don't include prBoundary layer (GDS layer 189, datatype 4)
- **Fix**: Added prBoundary rectangles (matching LEF SIZE dimensions) using gdstk Python library
- **Commit**: `1e0b1d7`

### 4. Empty string in ROUTING_OBSTRUCTIONS
- **Symptom**: `Value provided for variable 'ROUTING_OBSTRUCTIONS[10]' of type typing.Tuple is invalid: (0/5) tuple entries`
- **Cause**: Config generator script inserted `""` separators between SRAM obstruction groups
- **Fix**: Remove empty strings from the array
- **Commit**: `232c676`

## Build Results

### Nocache builds (regfile SRAM only)

| Branch | Commit | Density | Layout | GDS | Notes |
|--------|--------|---------|--------|-----|-------|
| exp-8x4-nocache | `b57a029` | 60% | rf@[40,40] | **PASS** | 0 routing DRC, PSM-0040 OK |
| exp-10x4-nocache | `e8d7463` | 60% | rf@[40,40] | **PASS** | 0 routing DRC, PSM-0040 OK |

Precheck fails on both (missing pin def file for 8x4/10x4 in tt-support-tools). GL test fails (no SRAM macro model for gate-level sim). These are infrastructure issues, not design issues.

### 256x64 cache builds (regfile + 2x 256x64 cache SRAMs)

All timed out at 6h CI limit. The 256x64 macros create too much routing complexity for the available CI time.

| Branch | Commit | Density | Layout | GDS | Notes |
|--------|--------|---------|--------|-----|-------|
| main | `b939d43` | 60% | stacked left | **TIMEOUT** | 6h limit |
| experimental-regfile | `88beb17` | 60% | regfile only in config | **TIMEOUT** | 6h limit |
| exp-8x4-a | `e1a76f0` | 60% | rf@40, ic@160, dc@330 | **TIMEOUT** | 6h limit |
| exp-8x4-b | `1339c45` | 60% | rf@40, ic@170, dc@350 | **TIMEOUT** | 6h limit |
| exp-8x4-c | `88284fb` | 60% | ic@40, dc@210, rf@600 | **TIMEOUT** | 6h limit |
| exp-8x4-d | `9d7d175` | 60% | ic@40, dc@210, rf@900 | **TIMEOUT** | 6h limit |
| exp-10x4-cache | `8046afb` | 60% | rf@40, ic@160, dc@330 | **TIMEOUT** | 6h limit (10x4 tiles) |

### 64x64 cache builds (regfile + 2x 64x64 cache SRAMs)

| Branch | Commit | Density | Layout | GDS | Failure reason |
|--------|--------|---------|--------|-----|----------------|
| exp-8x4-cache64 | `f8520eb` | 60% | tight stack left | **FAIL** | Yosys specify block error |
| exp-8x4-cache64 | `50a351c` | 60% | tight stack left | **FAIL** | RSZ-0169 max_capacitance = 0 |
| exp-8x4-cache64 | `1e0b1d7` | 60% | tight stack left | cancelled | superseded by density change |
| exp-8x4-cache64 | `da1fac8` | 50% | rf@40,40 ic@40,130 dc@40,210 | cancelled | ~5h, no result |
| exp-cache64-e | `89e5843` | 60% | rf@40,40 ic@40,250 dc@40,450 | **FAIL** | empty string in ROUTING_OBSTRUCTIONS |
| exp-cache64-e | `664de9d` | 50% | rf@40,40 ic@40,250 dc@40,450 | cancelled | ~5h, no result |
| exp-cache64-f | `a845fb2` | 60% | rf@900,40 ic@40,40 dc@40,130 | **FAIL** | empty string in ROUTING_OBSTRUCTIONS |
| exp-cache64-f | `e033645` | 50% | rf@900,40 ic@40,40 dc@40,130 | cancelled | ~5h, no result |
| exp-cache64-g | `eef6f6a` | 60% | rf@40,480 ic@40,560 dc@40,635 | **FAIL** | empty string in ROUTING_OBSTRUCTIONS |
| exp-cache64-g | `4e3681a` | 50% | rf@40,480 ic@40,560 dc@40,635 | cancelled | ~5h, no result |
| exp-cache64-h | `d046347` | 60% | rf@40,40 ic@40,130 dc@860,130 | **FAIL** | empty string in ROUTING_OBSTRUCTIONS |
| exp-cache64-h | `269a7a7` | 50% | rf@40,40 ic@40,130 dc@860,130 | cancelled | ~5h, no result |
| **exp-cache64-i** | **`80e82f6`** | **50%** | **rf@40,40 ic@860,40 dc@40,600** | **PASS** | **0 routing DRC, PSM-0040 OK, ~1h** |
| exp-cache64-i | `25c2cc4` | 60% | rf@40,40 ic@860,40 dc@40,600 | **FAIL** | empty string in ROUTING_OBSTRUCTIONS |
| exp-cache64-j | `47baed2` | 60% | rf@500,300 ic@500,380 dc@500,450 | **FAIL** | empty string in ROUTING_OBSTRUCTIONS |
| exp-cache64-j | `cdc534b` | 50% | rf@500,300 ic@500,380 dc@500,450 | cancelled | ~5h, no result |

### Currently running

| Branch | Commit | Density | Layout | Notes |
|--------|--------|---------|--------|-------|
| exp-cache64-i | `d3fe01e` | 50% | 3 corners | Rebased on upstream, DRC+LVS re-enabled |
| exp-cache64-density-test | `a02ca6f` | 30% | 3 corners | Testing lower density |

## Key Findings

### 1. SRAM placement is critical for routing convergence
The 3-corner layout (config-i) is the only configuration that completed GDS successfully with cache SRAMs:
- **Regfile** at bottom-left [40, 40]
- **ICache** at bottom-right [860, 40]
- **DCache** at top-left [40, 600]

This maximizes separation between SRAMs and leaves the center + top-right of the die completely open for routing. All other layouts (stacked, side-by-side, center cluster, spread vertical) either timed out or were cancelled after 5+ hours.

### 2. 64x64 cache SRAMs fit; 256x64 do not (in CI time)
The 256x64 SRAM macros (118.78 µm tall) consistently timeout the 6h CI limit. The 64x64 macros (64.36 µm tall) completed in ~1h with the right placement.

### 3. IHP PDK SRAM files have multiple issues
Three bugs found in IHP-Open-PDK SRAM files:
- Missing prBoundary in GDS (all 1P SRAMs)
- Wrong max_capacitance units in 64x64 Liberty files
- Yosys-incompatible specify blocks in 64x64 Verilog model

### 4. Routing obstructions are necessary
The SRAM LEF files only define Metal1/Metal2 OBS. Metal4 and TopMetal1 full-area obstructions are needed to prevent signal routing conflicts with SRAM power pins and PDN stripes.

### 5. Lower density helps
Reducing PL_TARGET_DENSITY_PCT from 60 to 50 (and possibly lower) gives the placer more room and reduces routing congestion.

## Configuration Reference

### Working config (exp-cache64-i)
```
PL_TARGET_DENSITY_PCT: 50
CLOCK_PERIOD: 20
3 SRAM macros: 1x 2P_64x32 + 2x 1P_64x64
Layout: 3 corners (rf@40,40 ic@860,40 dc@40,600)
Custom PDN: Metal4 → TopMetal1
Routing obstructions: Metal2/3 edge strips + Metal4/5/TopMetal1 full area per SRAM
```

### Librelane version
`3.0.0.rc0` (gds.yaml), tools: `urish/tt-support-tools` ref `ihp-8x4`
