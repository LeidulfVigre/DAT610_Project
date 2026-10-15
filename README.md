# CQI-based AMC in 5G NR – DAT610 project code

MATLAB code for evaluating CQI-based adaptive modulation and coding (AMC) on the 5G NR downlink (PDSCH), built on the MathWorks 5G Toolbox example *NR PDSCH Throughput Using Channel State Information Feedback*.

## Setup

1. Requires MATLAB with 5G Toolbox (written against R2026b). Parallel Computing Toolbox is optional; `parfor` runs as a normal loop without it.
2. Get the example's helper files: run
   `openExample('5g/NewRadioPDSCHThroughputWithCSIFeedbackExample')`
   and copy every `h*.m` file from that example folder (e.g. `hCSIDecode.m`, `hCSIEncode.m`, `hSkipWeakTimingOffset.m` and the files they call) into this folder, or add that folder to the MATLAB path.
3. Run `quickTest` first.

## Files

| File | Role |
| --- | --- |
| `baseConfig.m` | Fixed scenario parameters (one struct) |
| `runLink.m` | Base simulator: one link, one SNR point, returns throughput, BLER, spectral efficiency, modulation share, CQI |
| `snrFromDistance.m` | TR 38.901 UMa path loss → SNR per distance (LOS / NLOS) |
| `eval1_snr.m` | Evaluation 1: AMC (Table 1, Table 2) vs fixed MCS over SNR → Fig. 1 |
| `eval2_distance.m` | Evaluation 2: throughput vs distance, LOS vs NLOS → Fig. 2 |
| `eval3_mobility.m` | Evaluation 3: UE speed × CSI report period → Figs. 3–4 |
| `plotFigures.m` | Draws all figures from `results/*.mat` into `figures/*.pdf` |
| `quickTest.m` | Timing test and sanity checks |

## Order of work

1. `quickTest` – check that it runs, read the estimated runtime, then set `NFrames` in `baseConfig.m`.
2. `eval1_snr`, `eval2_distance`, `eval3_mobility` – can run on different computers; each saves its own `.mat` file in `results/`.
3. `plotFigures` – run any time; it plots whatever results exist.

## Validation (what to expect)

- High SNR, low speed, Table 2: mostly 256-QAM, throughput close to the maximum.
- Low speed: BLER near 10 % (the CQI target).
- AMC throughput never above the best fixed-MCS curve by much.
- Throughput falls with distance and with speed; longer CSI periods lose more at high speed.

## Things to check

- The code has not been run yet; expect small fixes on first run.
- Fixed MCS code rates in `eval1_snr.m` are from MCS Table 2 (MCS 3, 7, 15, 23); confirm with `nrPDSCHMCSTables`.
- `TxPowerdBm` and `UENoiseFiguredB` in `baseConfig.m` are assumptions; cite a source in the report.
- SISO is used by default. For 2×2 with rank 1, see the comment in `baseConfig.m`.
