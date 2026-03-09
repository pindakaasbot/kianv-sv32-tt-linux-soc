# RM_IHPSG13_1P_64x64_c2_bm_bist

IHP SG13G2 foundry-provided 64x64 single-port SRAM macro with BIST.

## Source

- **Repository**: https://github.com/IHP-GmbH/IHP-Open-PDK
- **Commit**: `7c124b7324778fbc2261aa8529ba04388eb3339e`
  ("SRAM cells layout: fixed PG pins Metal1.txt and Metal4.txt layers (#239)")
- **Path**: `ihp-sg13g2/libs.ref/sg13g2_sram/`

## Modifications from PDK

- **GDS**: Added prBoundary layer (189, datatype 4) rectangle around macro
  footprint. Required by librelane for macro placement extraction — the PDK
  GDS does not include this layer.
- **LIB (all 3 corners)**: Fixed `max_capacitance` values from `6.4e-14`
  (Farads) to `0.064` (picoFarads). PDK bug: values were in SI units instead
  of the Liberty convention of picoFarads, causing RSZ-0169 resizer failures.

## License

These files are part of IHP-Open-PDK and are licensed under the Apache License 2.0.
See the [IHP-Open-PDK repository](https://github.com/IHP-GmbH/IHP-Open-PDK) for details.
