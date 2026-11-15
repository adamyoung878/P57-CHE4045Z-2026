# P57: energy and environmental impact allocation in industrial symbiosis using game theory

A MINLP of four co-located players that share steam, power and heat: 1 SCN-CHP, 2 MEE, 3 HEN, and 4 Farm (crypto-mining farm). Each run minimises the economic objective EcO (1e5 $/yr), the environmental objective EnO (kt CO2e/yr), or both over a sweep of weights (MOO). The model is solved for each of the 15 possible Coalitions (subsets of the players) and reports EcO and EnO of the Coalition and of each member.

## Start here

- **Results:** see [Results](#results). The base case is [`pipeline_results/P2/coalition_results/sweep.csv`](pipeline_results/P2/coalition_results/sweep.csv), which GitHub shows as a table.
- **Analysis workbooks:** [`analysis/`](analysis/). GitHub cannot preview Excel files, so download them (see [Analysis workbooks](#analysis-workbooks)).
- **Model:** [`base_model.gms`](base_model.gms).
- **Full solver outputs** (logs and GDX files): attached to the [latest release](https://github.com/adamyoung878/P57-CHE4045Z-2026/releases/latest).

## The model in brief

| Code | Player | Meaning |
|---|---|---|
| 1 | SCN-CHP | Supply chain network and CHP |
| 2 | MEE | Multi-effect evaporator |
| 3 | HEN | Heat exchanger network |
| 4 | Farm | Crypto-mining farm |

A Coalition is named by the codes of its members: `1` is SCN-CHP alone, `134` is SCN-CHP + HEN + Farm, `1234` is all four players.

Units: EcO in 1e5 $/yr, EnO in kt CO2e/yr. The MOO objective is `RG × EcO/scaleEcO + (1 − RG) × EnO/scaleEnO`, so **RG is the weight on EcO**: RG = 1 minimises EcO alone and RG = 0 minimises EnO alone. Each Coalition is solved at five points: RG = 0, the three inner weights (`--RG2`, `--RG3`, `--RG4`), and RG = 1.

## Results

### Scenarios

Each scenario has a folder in `pipeline_results/`.

| Folder | What changes | Coalitions | Values | RG points |
|---|---|---|---|---|
| `P2` | Base case | all 15 | n/a | 0, 0.4, 0.5, 0.6, 1 |
| `P1` | Inner weights shifted towards EnO | all 15 | n/a | 0, 0.1, 0.2, 0.3, 1 |
| `P3` | Inner weights shifted towards EcO | all 15 | n/a | 0, 0.7, 0.8, 0.9, 1 |
| `BTC_x` | Bitcoin price × x | 1234 | x = 0.5 to 2 in steps of 0.1 | 0, 0.25, 0.5, 0.75, 1 |
| `DIND_x` | Minimum industrial demand (5,000 kW) × x | 1234 | x = 0 to 2.5 in steps of 0.1 | 0, 0.25, 0.5, 0.75, 1 |
| `BG_x` | Biogas feedstock cost × x | 1234 | x = 0.5 to 2 in steps of 0.1 | 0, 0.25, 0.5, 0.75, 1 |

`BG_1` and `DIND_1` have no folder: with a multiplier of 1 and the same RG points they are the same run as `BTC_1`, so use `BTC_1`. In every committed scenario each Coalition returned a solution (`solved` is `True` in every row of every `sweep.csv`).

### What is in a scenario folder

| File | Contents |
|---|---|
| `coalition_results/sweep.csv` | EcO and EnO of each Coalition and of each member, at each RG point |
| `coalition_results/variables.csv` | Level of every variable, per Coalition and RG point |
| `coalition_results/results.xlsx` | The same two tables as the sheets `sweep` and `variables` |
| `stamp.txt` | Model version, warm-start version and options that produced the run |
| `starts_log.csv` | Only where the options change the economic solve: the improvements made to the warm starts |

**`sweep.csv`** has one row per Coalition and RG point (15 × 5 = 75 rows for `P1`, `P2` and `P3`; 5 rows for the sensitivities). Columns: `Coalition`, `members`, `solved`, `RG`, `EcO Coalition`, `EnO Coalition`, then `EcO` and `EnO` for each player (`SCN-CHP`, `MEE`, `HEN`, `Farm`). A player's columns are blank in Coalitions it is not part of.

**`variables.csv`** has one row per variable and index (`variable`, `index`, `description`), then one column per Coalition and RG point, named like `134 RG 0.4`. A value of 0 means the variable is zero; the GDX files leave zeros out.

### Analysis workbooks

The two workbooks in [`analysis/`](analysis/) hold the data analysis behind the thesis. They are standard Excel files, so use **Download raw file** on GitHub (or clone the repository).

| File | Contents |
|---|---|
| `analysis/Coalition_MOO_GT.xlsx` | Game Theory analysis and Pareto Fronts |
| `analysis/P57_Sensitivity.xlsx` | Sensitivity analysis data and figures |

### Full outputs

The repository holds only the result tables. The complete outputs, `pipeline_results/` exactly as produced, are attached to the [latest release](https://github.com/adamyoung878/P57-CHE4045Z-2026/releases/latest) as `p57_full_results.zip`. They add one folder per Coalition with `run.lst` (solver log and listing), `run.log`, `sol.gdx`, `point_RG*.gdx` and `moo_*.gdx`, plus each scenario's warm starts. They are left out of git because they are about 400 MB and can be regenerated.

## Files

| File | What it does |
|---|---|
| `base_model.gms` | The model. Solves one Coalition per run. |
| `run_coalitions.py` | Runs `base_model.gms` for every Coalition and collects the results. |
| `pipeline.py` | Runs every scenario in `scenarios.csv`. |
| `scenarios.csv` | One row per scenario: name, Coalitions, GAMS options. |
| `starts/` | Best known solution of each Coalition, used as warm starts. `model_hash.txt` records the model version they belong to. |
| `pipeline_results/` | Result tables of every scenario (see [Results](#results)). |
| `analysis/` | The data-analysis workbooks. |
| `requirements.txt` | Python packages, with the versions used. |

## Setup

1. GAMS 54 (DICOPT, CONOPT, CPLEX). The demo licence is enough. The results here were produced with GAMS 54.4.0 on Windows: DICOPT for the MINLP, CPLEX for MIPs, CONOPT for NLPs.
2. Python 3.8+ with the packages in `requirements.txt`:

```powershell
python -m pip install -r requirements.txt
```

GAMS is found on the PATH or in the Windows registry. If not, set `GAMS = r'C:\GAMS\54\gams.exe'` at the top of `run_coalitions.py`.

## Running

Open the folder in VS Code, then Terminal > New Terminal:

```powershell
python pipeline.py                  # everything: base case and sensitivities
python pipeline.py list             # scenario names
python pipeline.py base             # base case only
python pipeline.py BTC              # one sensitivity (all BTC_ rows)
python pipeline.py BTC_0.7 DIND_2   # only these scenarios
python pipeline.py sens             # all sensitivity rows
python pipeline.py all --force      # rerun everything, even if up to date
```

Results go to `pipeline_results/<scenario>/coalition_results/`: `sweep.csv` (EcO and EnO of each Coalition and member at each RG), `variables.csv` (every variable level per Coalition and RG), the same two tables as sheets of `results.xlsx`, and one folder per Coalition with `run.lst`, `sol.gdx` and `point_RG*.gdx`. Finished scenarios are skipped on the next run.

**On a fresh clone** the per-Coalition folders are missing (see [Full outputs](#full-outputs)), so `pipeline.py` treats every scenario as unfinished and reruns it. Name the scenarios you want, for example `python pipeline.py base` for the base case (`P2`) only.

All 15 Coalitions once, without the pipeline:

```powershell
python run_coalitions.py
```

Results go to `coalition_results/` in the same form (an `--OBJ=EcO` or `--OBJ=EnO` run gives one sweep row per Coalition, with no RG). The settings at the top of the file pick the Coalitions (`COALITIONS`), GAMS options (`OPTIONS`) and warm or cold starts (`WARM`).

One Coalition: open `base_model.gms` in GAMS Studio and put options in the parameter box, or from a terminal:

```powershell
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

## Notes

- `solved = True` means GAMS returned a solution. It is not a proof of global optimality.
- `pipeline.py` hashes `base_model.gms` ignoring blank lines and `*` comment lines. Changing any other line makes `starts/` and every `stamp.txt` out of date, so the next `python pipeline.py` refreshes the starts and reruns all scenarios.

## Authors

Authors:        Adam Young and Flynn Newell
Course:         CHE4045Z, 2026
Supervisors:    Prof. Adeniyi Isafiade, Takudzwa Chitsiga, Dr. Kyle Abrahams