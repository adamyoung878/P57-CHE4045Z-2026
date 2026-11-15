# P57 GAMS model

A MINLP of four co-located players that share steam, power and heat: 1 SCN-CHP 2 MEE, 3 HEN, and 4 Farm (crypto-mining farm). Each run minimises the economic objective EcO (1e5 $/yr), the environmental objective EnO (kt CO2e/yr), or both over a sweep of weights (MOO).

## Files

| File | What it does |
|---|---|
| `base_model.gms` | The model. Solves one Coalition per run. |
| `run_coalitions.py` | Runs `base_model.gms` for every Coalition and collects the results. |
| `pipeline.py` | Runs every scenario in `scenarios.csv`. |
| `scenarios.csv` | One row per scenario: name, Coalitions, GAMS options. |
| `starts/` | Best known solution of each Coalition, used as warm starts. `model_hash.txt` records the model version they belong to. |

## Setup

1. GAMS 54 (DICOPT, CONOPT, CPLEX). The demo licence is enough.
2. Python 3.8+ with `pandas` and `openpyxl` (`py -m pip install pandas openpyxl`).

GAMS is found on the PATH or in the Windows registry. If not, set `GAMS = r'C:\GAMS\54\gams.exe'` at the top of `run_coalitions.py`.

## Running

Open the folder in VS Code, then Terminal > New Terminal:

```
python pipeline.py                  # everything: base case and sensitivities
python pipeline.py list             # scenario names
python pipeline.py base             # base case only
python pipeline.py BTC              # one sensitivity (all BTC_ rows)
python pipeline.py BTC_0.7 DIND_2   # only these scenarios
python pipeline.py sens             # all sensitivity rows
python pipeline.py all --force      # rerun everything, even if up to date
```

Results go to `pipeline_results/<scenario>/coalition_results/`: `sweep.csv` (EcO and EnO of each Coalition and member at each RG), `variables.csv` (every variable level per Coalition and RG), the same two tables as sheets of `results.xlsx`, and one folder per Coalition with `run.lst`, `sol.gdx` and `point_RG*.gdx`. Finished scenarios are skipped on the next run.

All 15 Coalitions once, without the pipeline:

```
python run_coalitions.py
```

Results go to `coalition_results/` in the same form (an `--OBJ=EcO` or `--OBJ=EnO` run gives one sweep row per Coalition, with no RG). The settings at the top of the file pick the Coalitions (`COALITIONS`), GAMS options (`OPTIONS`) and warm or cold starts (`WARM`).

One Coalition: open `base_model.gms` in GAMS Studio and put options in the parameter box, or from a terminal:

```
gams base_model.gms --COAL=134 --OBJ=EcO
```

## GAMS options

| Option | Does | Default |
|---|---|---|
| `--COAL` | Coalition to solve (1, 2, 3, 4, 12, ..., 1234) | 1234 |
| `--OBJ` | `MOO`, `EcO` or `EnO` | MOO |
| `--BTCMULT` | Multiplier on the bitcoin price | 1 |
| `--DINDMULT` | Multiplier on the minimum industrial demand (5,000 kW) | 1 |
| `--BGMULT` | Multiplier on the biogas feedstock cost | 1 |
| `--RG2`, `--RG3`, `--RG4` | EcO weights of the three inner MOO points (outer points are 0 and 1) | 0.4, 0.5, 0.6 |
| `--START` | Warm start from a GDX of the same Coalition (integers fixed) | none |
| `--SEED`, `--SEEDPLAYER` | With `--START`: take one player's design from another GDX | none |

## Changing inputs

- **A new scenario:** add a row to `scenarios.csv`, e.g. `BTC_3,all,--BTCMULT=3` (all Coalitions). Edit it in VS Code or Notepad, not Excel, which corrupts the options.
- **Settings of a direct run:** `COALITIONS`, `OPTIONS` and `WARM` at the top of `run_coalitions.py`.
