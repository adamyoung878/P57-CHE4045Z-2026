"""Run the scenarios in scenarios.csv (see README.md)"""
import hashlib
import os
import re
import shutil
import subprocess
import sys
import time
import pandas as pd
import run_coalitions as rc

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.path.join(HERE, 'scenarios.csv')
OUT = os.path.join(HERE, 'pipeline_results')
STARTS = os.path.join(HERE, 'starts')
TOL = 1e-4              # a start is replaced only by an EcO lower by more than this [1e5 $/year]
SEED_ROUNDS = 3         # most rounds of cross-seeding
# The variables --SEEDPLAYER takes from another solution (SEED block of base_model.gms)
SEED_VARIABLES = {'1': ['S_A', 'z', 'x', 'bb'],
                  '2': ['NEFF', 'b_PH'],
                  '3': ['y', 'q', 'th', 'tc', 'dt'],
                  '4': ['b_cr', 'b_crB', 'b_crS', 'CR_Cap', 'CR_Pco', 'CR_Pgr', 'Q_crB', 'Q_crS']}


# ======================================================================================================================
# SCENARIOS
# ======================================================================================================================
def read_scenarios():
    """The rows of scenarios.csv, each with its options as a list, its coalitions as a list, its key (the options not
    at their default) and run (the first row with the same key whose coalitions include the row's)"""
    table = pd.read_csv(SCENARIOS, dtype=str, keep_default_na=False)
    defaults = model_defaults()
    scenarios = []
    for row in table.to_dict('records'):
        row['options'] = row['options'].split()
        row['coalitions'] = read_coalitions(row['coalitions'])
        row['key'] = option_key(row['options'], defaults)
        row['run'] = row['name']
        for earlier in scenarios:
            if earlier['run'] == earlier['name'] and earlier['key'] == row['key'] and \
                    all(coal in earlier['coalitions'] for coal in row['coalitions']):
                row['run'] = earlier['name']
                break
        scenarios.append(row)
    return scenarios


def read_coalitions(text):
    """'all' -> every Coalition; '1234' or '1234 123' -> those, in the order of rc.COALITIONS"""
    if text.strip().lower() in ['', 'all']:
        return rc.COALITIONS
    return [coal for coal in rc.COALITIONS if coal in text.split()]


def model_defaults():
    """{option: default} from the $if not set lines of base_model.gms"""
    defaults = {}
    with open(rc.MODEL, encoding='utf-8', errors='replace') as f:
        for line in f:
            match = re.match(r'\$if not set (\w+) \$setGlobal \w+ (\S+)', line.strip(), re.IGNORECASE)
            if match:
                defaults[match.group(1).upper()] = match.group(2)
    return defaults


def option_key(options, defaults):
    kept = []
    for option in options:
        name, value = (option.split('=', 1) + [''])[:2]
        name = name.lstrip('-').upper()
        if not same_value(value, defaults.get(name)):
            kept.append('--' + name + '=' + value)
    return ' '.join(sorted(kept))


def same_value(a, b):
    if b is None:
        return False
    try:
        return float(a) == float(b)
    except ValueError:
        return a.upper() == b.upper()


def picked(scenario, name):
    """True if name is the scenario's name or its start before '_' (BTC picks BTC_0.5 ...)"""
    full = scenario['name'].upper()
    return full == name.upper() or full.startswith(name.upper() + '_')


def pick(scenarios, names):
    """The scenarios names pick (all if names is empty), with the rows whose runs they use"""
    if len(names) == 0:
        return scenarios
    runs = []
    for name in names:
        found = [s for s in scenarios if picked(s, name)]
        if len(found) == 0:
            print(name, 'is not in scenarios.csv (python pipeline.py list shows the names)')
        for s in found:
            if s['run'] not in runs:
                runs.append(s['run'])
    return [s for s in scenarios if s['run'] in runs and (s['name'] == s['run'] or
                                                           any(picked(s, name) for name in names))]


def list_scenarios():
    for s in read_scenarios():
        note = '' if s['run'] == s['name'] else '  (uses the run of ' + s['run'] + ')'
        coalitions = 'all' if s['coalitions'] == rc.COALITIONS else ' '.join(s['coalitions'])
        print(s['name'].ljust(10), coalitions.ljust(5), ' '.join(s['options']) or 'base case', note)


# ======================================================================================================================
# HASHES AND STAMPS
# ======================================================================================================================
def model_hash():
    """Hash of base_model.gms without comment and blank lines"""
    lines = []
    with open(rc.MODEL, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.rstrip()
            if line != '' and not line.startswith('*'):
                lines.append(line)
    return hashlib.sha1('\n'.join(lines).encode()).hexdigest()[:12]


def starts_hash(folder):
    h = hashlib.sha1()
    for coal in rc.COALITIONS:
        path = os.path.join(folder, coal + '.gdx')
        if os.path.exists(path):
            with open(path, 'rb') as f:
                h.update(f.read())
    return h.hexdigest()[:12]


def starts_model():
    """The model hash the starts were made for (starts/model_hash.txt)"""
    path = os.path.join(STARTS, 'model_hash.txt')
    if not os.path.exists(path):
        return ''
    with open(path) as f:
        return f.read().strip()


def stamp_text(scenario):
    return 'model ' + model_hash() + '\nstarts ' + starts_hash(STARTS) + '\noptions ' + scenario['key'] + '\n'


def up_to_date(scenario):
    """True if the scenario ran with this model, these starts and these options, and has its coalitions"""
    folder = os.path.join(OUT, scenario['name'])
    path = os.path.join(folder, 'stamp.txt')
    if not os.path.exists(path) or not os.path.exists(os.path.join(folder, 'coalition_results', 'sweep.csv')):
        return False
    for coal in scenario['coalitions']:
        if not os.path.exists(os.path.join(folder, 'coalition_results', coal, 'run.lst')):
            return False
    with open(path) as f:
        return f.read() == stamp_text(scenario)


def check_gams_ran(coal):
    """Stop if GAMS did not run at all (no run.lst), e.g. when the licence server refuses a session"""
    folder = os.path.join(rc.RESULTS, coal)
    if os.path.exists(os.path.join(folder, 'run.lst')):
        return
    log = ''
    if os.path.exists(os.path.join(folder, 'run.log')):
        with open(os.path.join(folder, 'run.log')) as f:
            log = f.read().strip()
    sys.exit('\nGAMS did not run ' + coal + '. Its log:\n' + log + '\n\nFix that and run python pipeline.py again; '
             'finished scenarios are skipped.')


# ======================================================================================================================
# STARTS
# ======================================================================================================================
def eco_run(coal, options, warm, extra=()):
    """Solve coal for the lowest EcO; its EcO, or None without a solution"""
    command = ['--OBJ=EcO'] + [o for o in options if not o.upper().startswith('--OBJ=')] + list(extra)
    rc.solve(coal, command, warm)
    check_gams_ran(coal)
    if not rc.solved(coal):
        return None
    return rc.read_dict(coal, 'res').get('EcO', 0.0)


def gdx_csv(path, symbol):
    """The records of symbol in a GDX file as lists of text, e.g. ['EcO', '73.45']"""
    result = subprocess.run([rc.find_gdxdump(), path, 'symb=' + symbol, 'format=csv'], capture_output=True, text=True)
    return [line.replace('"', '').split(',') for line in result.stdout.splitlines()[1:]]


def gdx_eco(path):
    """The EcO in res of a solution file, or None without a solution"""
    res = {}
    for parts in gdx_csv(path, 'res'):
        res[parts[0]] = float(parts[1])
    if 'model status' not in res:
        return None
    return res.get('EcO', 0.0)


def player_levels(path, p):
    """The nonzero SEED_VARIABLES of player p in a solution file, to 4 significant digits"""
    levels = []
    for symbol in SEED_VARIABLES[p]:
        for parts in gdx_csv(path, symbol):
            value = parts[-1]
            try:
                value = '%.4g' % float(value)
            except ValueError:
                pass                                    # Eps and other special values stay as text
            if value != '0':
                levels.append(symbol + ' ' + ' '.join(parts[:-1]) + ' ' + value)
    return levels


def warm_or_cold(starts, options, work, log):
    """Make each start the lower of a warm and a cold EcO run. Returns {Coalition: EcO}, the Coalitions whose start
    changed, and whether the options changed the EcO of a start"""
    best = {}
    changed = []
    new_eco = False
    for coal in rc.COALITIONS:
        start = os.path.join(starts, coal + '.gdx')
        sol = os.path.join(work, coal, 'sol.gdx')
        warm = None
        if os.path.exists(start):
            before = gdx_eco(start)
            warm = eco_run(coal, options, True)
            if warm is None or before is None or abs(warm - before) > TOL:
                new_eco = True
            if warm is not None:
                shutil.copyfile(sol, start)             # the levels of these options
        cold = eco_run(coal, options, False)
        best[coal] = warm
        if cold is not None and (warm is None or cold < warm - TOL):
            shutil.copyfile(sol, start)
            best[coal] = cold
            changed.append(coal)
            log.append({'Coalition': coal, 'change': 'cold run', 'EcO before': warm, 'EcO after': cold})
        print(coal + ':', 'solved' if best[coal] is not None else 'no solution', flush=True)
    return best, changed, new_eco


def cross_seed(starts, options, work, log, best, donors):
    """Try each player's design from each donor's start in every other Coalition with that player; keep it if the
    EcO falls. Later rounds take designs from the Coalitions improved in the round before. A design that repeats one
    already tried is skipped."""
    levels = {}
    for coal in rc.COALITIONS:
        if best[coal] is not None:
            for p in coal:
                levels[(coal, p)] = player_levels(os.path.join(starts, coal + '.gdx'), p)
    for round_number in range(1, SEED_ROUNDS + 1):
        if len(donors) == 0:
            break
        print('Cross-seeding round', round_number, flush=True)
        improved = []
        for coal in rc.COALITIONS:
            if best[coal] is None:
                continue
            start = os.path.join(starts, coal + '.gdx')
            sol = os.path.join(work, coal, 'sol.gdx')
            for p in coal:
                tried = [levels[(coal, p)]]
                for donor in donors:
                    if donor == coal or p not in donor or best[donor] is None or levels[(donor, p)] in tried:
                        continue
                    tried.append(levels[(donor, p)])
                    seed = os.path.relpath(os.path.join(starts, donor + '.gdx'), os.path.join(work, coal))
                    tac = eco_run(coal, options, True, ['--SEED=' + seed, '--SEEDPLAYER=' + p])
                    if tac is not None and tac < best[coal] - TOL:
                        log.append({'Coalition': coal, 'change': rc.PLAYERS[p] + ' design of ' + donor,
                                    'EcO before': best[coal], 'EcO after': tac})
                        shutil.copyfile(sol, start)
                        best[coal] = tac
                        for q in coal:
                            levels[(coal, q)] = player_levels(start, q)
                        tried.append(levels[(coal, p)])
                        if coal not in improved:
                            improved.append(coal)
            print(coal + ': done', flush=True)
        donors = improved


def improve_starts(starts, options, work, seed_from_all):
    """Improve the starts in the folder starts for these options; returns one row per change. Seeding takes designs
    from every Coalition if seed_from_all or the options change an EcO, else from the Coalitions whose start changed."""
    rc.STARTS = starts
    rc.RESULTS = work
    os.makedirs(starts, exist_ok=True)
    log = []
    best, changed, new_eco = warm_or_cold(starts, options, work, log)
    donors = changed
    if seed_from_all or new_eco:
        donors = rc.COALITIONS
    cross_seed(starts, options, work, log, best, donors)
    return pd.DataFrame(log, columns=['Coalition', 'change', 'EcO before', 'EcO after'])


def refresh_starts(force):
    """Remake starts/ if base_model.gms changed since they were made"""
    if starts_model() == model_hash() and not force:
        return
    print('Refreshing starts/ for this version of base_model.gms')
    work = os.path.join(OUT, 'starts_runs')
    log = improve_starts(STARTS, [], work, True)
    os.makedirs(OUT, exist_ok=True)
    log.to_csv(os.path.join(OUT, 'starts_log.csv'), index=False)
    shutil.rmtree(work, ignore_errors=True)
    with open(os.path.join(STARTS, 'model_hash.txt'), 'w') as f:
        f.write(model_hash() + '\n')
    print('Starts refreshed')


# ======================================================================================================================
# RUNS
# ======================================================================================================================
def run_sweeps(name, options, starts, coalitions):
    """The MOO sweep of each of the Coalitions, warm from the folder starts"""
    rc.STARTS = starts
    rc.RESULTS = os.path.join(OUT, name, 'coalition_results')
    os.makedirs(rc.RESULTS, exist_ok=True)
    rc.solve_all(coalitions, options, True)
    for coal in coalitions:
        check_gams_ran(coal)
    rc.save(rc.read_sweep(coalitions), rc.read_variables(coalitions))


def run_scenarios(scenarios, force):
    """Run each scenario that has its own run and is not up to date, one after the other"""
    waiting = [s for s in scenarios if s['run'] == s['name'] and (force or not up_to_date(s))]
    if len(waiting) > 0:
        print(len(waiting), 'scenarios to run', flush=True)
    times = []
    for k in range(len(waiting)):
        scenario = waiting[k]
        name = scenario['name']
        print('\n[' + str(k + 1) + '/' + str(len(waiting)) + ']', name, flush=True)
        began = time.time()
        folder = os.path.join(OUT, name)
        shutil.rmtree(folder, ignore_errors=True)
        os.makedirs(folder, exist_ok=True)
        starts = STARTS
        if changes_eco(scenario['key']):
            print('Improving the starts for these options', flush=True)
            starts = os.path.join(folder, 'starts')
            shutil.copytree(STARTS, starts, dirs_exist_ok=True)
            log = improve_starts(starts, scenario['options'], os.path.join(folder, 'tac_runs'), False)
            log.to_csv(os.path.join(folder, 'starts_log.csv'), index=False)
            shutil.rmtree(os.path.join(folder, 'tac_runs'), ignore_errors=True)
        which = 'all Coalitions' if scenario['coalitions'] == rc.COALITIONS else ', '.join(scenario['coalitions'])
        print('MOO sweep of', which, flush=True)
        run_sweeps(name, scenario['options'], starts, scenario['coalitions'])
        with open(os.path.join(folder, 'stamp.txt'), 'w') as f:
            f.write(stamp_text(scenario))
        times.append(time.time() - began)
        left = len(waiting) - k - 1
        if left > 0:
            print(name, 'done;', left, 'to go, about', round(left * sum(times) / len(times) / 60), 'min left', flush=True)
        else:
            print(name, 'done', flush=True)


def changes_eco(key):
    """True if the options in key change the EcO solve; --RG2, --RG3 and --RG4 only move the MOO points"""
    return any(not option.startswith('--RG') for option in key.split())


def base(names=(), force=False):
    """Refresh the starts if the model changed, then run the base case (no options)"""
    refresh_starts(force)
    run_scenarios([s for s in pick(read_scenarios(), names) if s['key'] == ''], force)


def sens(names=(), force=False):
    """Run the scenarios with options"""
    if starts_model() != model_hash():
        print('Warning: starts/ was made for another version of base_model.gms; run python pipeline.py base first')
    run_scenarios([s for s in pick(read_scenarios(), names) if s['key'] != ''], force)


# ======================================================================================================================
# RUN
# ======================================================================================================================
if __name__ == '__main__':
    words = [w for w in sys.argv[1:] if w != '--force']
    force = '--force' in sys.argv[1:]
    step = 'all'
    names = words
    if len(words) > 0 and words[0] in ['base', 'sens', 'all', 'list']:
        step = words[0]
        names = words[1:]
    if step == 'list':
        list_scenarios()
    if step in ['base', 'all']:
        base(names, force)
    if step in ['sens', 'all']:
        sens(names, force)
