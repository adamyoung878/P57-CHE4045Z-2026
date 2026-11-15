"""Solve base_model.gms for each coalition and read the results into tables"""
import io
import os
import re
import shutil
import subprocess
import pandas as pd

# ======================================================================================================================
# SETTINGS
# ======================================================================================================================
COALITIONS = ['1', '2', '3', '4', '12', '13', '14', '23', '24', '34', '123', '124', '134', '234', '1234']
OPTIONS = []        # GAMS options for every run, e.g. ['--BTCMULT=1.5'] or ['--OBJ=EcO']
WARM = True         # start from starts/<coalition>.gdx
GAMS = ''           # full path of gams.exe, or '' to find it

PLAYERS = {'1': 'SCN-CHP', '2': 'MEE', '3': 'HEN', '4': 'Farm'}
OBJECTIVES = {'ECO': 'EcO', 'ENO': 'EnO', 'MOO': 'MOO'}
HERE = os.path.dirname(os.path.abspath(__file__))
MODEL = os.path.join(HERE, 'base_model.gms')
RESULTS = os.path.join(HERE, 'coalition_results')
STARTS = os.path.join(HERE, 'starts')


# ======================================================================================================================
# RUNNING GAMS
# ======================================================================================================================
def find_gams():
    """GAMS above, else gams on the PATH, else the GAMS the Windows installer registered"""
    path = GAMS
    if path == '':
        path = shutil.which('gams')
    if path is None and os.name == 'nt':
        import winreg
        for root in [winreg.HKEY_CURRENT_USER, winreg.HKEY_LOCAL_MACHINE]:
            try:
                path = os.path.join(winreg.QueryValue(root, r'Software\Classes\gams.location'), 'gams.exe')
                break
            except OSError:
                pass
    if path is None or not os.path.exists(path):
        raise FileNotFoundError('GAMS not found: set GAMS at the top of run_coalitions.py')
    return path


def find_gdxdump():
    folder = os.path.dirname(os.path.realpath(find_gams()))
    if os.name == 'nt':
        return os.path.join(folder, 'gdxdump.exe')
    return os.path.join(folder, 'gdxdump')


def objective(options):
    """'EcO' or 'EnO' if the options hold --OBJ, else 'MOO'"""
    for option in options:
        if option.upper().startswith('--OBJ='):
            return OBJECTIVES[option.upper()[6:]]
    return 'MOO'


def start_file(coal, options, warm):
    """starts/<coal>.gdx for a warm run, else ''. EnO runs start cold."""
    path = os.path.join(STARTS, coal + '.gdx')
    if warm and objective(options) != 'EnO' and os.path.exists(path):
        return path
    return ''


def solve(coal, options=OPTIONS, warm=WARM):
    """Run GAMS for one Coalition in coalition_results/<coal>/"""
    folder = os.path.join(RESULTS, coal)
    TABLES.pop(folder, None)
    try:
        shutil.rmtree(folder)
    except FileNotFoundError:
        pass
    except PermissionError:
        raise PermissionError('Close the files in ' + folder + ' (GAMS Studio or Excel) and run again')
    os.makedirs(folder)
    command = [find_gams(), MODEL, '--COAL=' + coal, 'lo=2', 'lf=run.log', 'o=run.lst', 'gdx=sol.gdx'] + options
    start = start_file(coal, options, warm)
    if start != '':
        command.append('--START=' + os.path.relpath(start, folder))     # relative, so spaces in folders are safe
    subprocess.run(command, cwd=folder)


def solve_all(coalitions=COALITIONS, options=OPTIONS, warm=WARM):
    """Solve each Coalition and say whether it solved"""
    for coal in coalitions:
        solve(coal, options, warm)
        if solved(coal):
            print(coal + ': solved', flush=True)
        else:
            print(coal + ': no solution, see', os.path.join(RESULTS, coal, 'run.lst'), flush=True)


# ======================================================================================================================
# READING THE RESULTS
# ======================================================================================================================
# The GDX files leave out zeros, so a missing value is read as 0 (.get(key, 0.0))
TABLES = {}         # {results folder: {symbol: table}}: the tables read since solve() last ran in that folder


def read_symbol(coal, name):
    """A symbol of the solution of coal as a table: one column per index, then Val. Each table is read once."""
    folder = os.path.join(RESULTS, coal)
    tables = TABLES.setdefault(folder, {})
    if name in tables:
        return tables[name]
    result = subprocess.run([find_gdxdump(), 'sol.gdx', 'symb=' + name, 'format=csv'], cwd=folder,
                            capture_output=True, text=True)
    if result.returncode != 0:
        raise KeyError(name + ' is not in ' + os.path.join(folder, 'sol.gdx'))
    table = pd.read_csv(io.StringIO(result.stdout), dtype=str, keep_default_na=False)
    if 'Val' in table.columns:
        table['Val'] = pd.to_numeric(table['Val'], errors='coerce')
    tables[name] = table
    return table


def read_dict(coal, name):
    """A one-index symbol as {label: value}"""
    table = read_symbol(coal, name)
    return dict(zip(table[table.columns[0]], table['Val']))


def read_dict2(coal, name):
    """A two-index symbol as {(label 1, label 2): value}"""
    table = read_symbol(coal, name)
    return dict(zip(zip(table[table.columns[0]], table[table.columns[1]]), table['Val']))


def solved(coal):
    """True if GAMS returned a solution (the model fills res only then)"""
    if not os.path.exists(os.path.join(RESULTS, coal, 'sol.gdx')):
        return False
    return 'model status' in read_dict(coal, 'res')


def run_objective(coal):
    """'MOO', 'EcO' or 'EnO'"""
    return OBJECTIVES[read_symbol(coal, 'OBJ_run')['Dim1'][0].upper()]


def points(coal):
    """The MOO points of coal as (RG, point) pairs from RG = 0 to 1"""
    rg = read_dict(coal, 'RGAA')
    return sorted((rg.get(point, 0.0), point) for point in read_symbol(coal, 'RG_set')['Dim1'])


def read_sweep(coalitions=COALITIONS):
    """One row per Coalition and MOO point, RG = 0 to 1: EcO and EnO of the Coalition and of each member. An EcO or EnO
    run gives one row with no RG."""
    rows = []
    for coal in coalitions:
        members = '+'.join(PLAYERS[p] for p in coal)
        if not solved(coal):
            rows.append({'Coalition': coal, 'members': members, 'solved': False})
            continue
        if run_objective(coal) != 'MOO':
            res = read_dict(coal, 'res')
            tacm = read_dict(coal, 'EcOm')
            eim = read_dict(coal, 'EnOm')
            row = {'Coalition': coal, 'members': members, 'solved': True,
                   'EcO Coalition': res.get('EcO', 0.0), 'EnO Coalition': res.get('EnO', 0.0)}
            for p in coal:
                row['EcO ' + PLAYERS[p]] = tacm.get(p, 0.0)
                row['EnO ' + PLAYERS[p]] = eim.get(p, 0.0)
            rows.append(row)
            continue
        tac = read_dict(coal, 'EcO_store')
        ei = read_dict(coal, 'EnO_store')
        tacm = read_dict2(coal, 'EcOm_store')
        eim = read_dict2(coal, 'EnOm_store')
        for rg, point in points(coal):
            row = {'Coalition': coal, 'members': members, 'solved': True, 'RG': rg,
                   'EcO Coalition': tac.get(point, 0.0), 'EnO Coalition': ei.get(point, 0.0)}
            for p in coal:
                row['EcO ' + PLAYERS[p]] = tacm.get((point, p), 0.0)
                row['EnO ' + PLAYERS[p]] = eim.get((point, p), 0.0)
            rows.append(row)
    columns = (['Coalition', 'members', 'solved', 'RG', 'EcO Coalition', 'EnO Coalition']
               + ['EcO ' + name for name in PLAYERS.values()] + ['EnO ' + name for name in PLAYERS.values()])
    return pd.DataFrame(rows, columns=columns)


def read_levels(coal, gdx):
    """Every nonzero variable level in a GDX file of coal as {(variable, index): level}, index like '4.1.2'"""
    result = subprocess.run([find_gdxdump(), gdx, 'format=gamsbas'], cwd=os.path.join(RESULTS, coal),
                            capture_output=True, text=True)
    levels = {}
    for line in result.stdout.splitlines():
        # e.g.  q.L ('4'.'1'.'2') = 1234.5 ;  or  NEFF.L  = 12 ;
        match = re.match(r"\s*(\w+)\.L\s*(\((.*)\))?\s*=\s*(\S+)\s*;", line)
        if match:
            index = '.'.join(re.findall(r"'([^']*)'", match.group(3) or ''))
            levels[(match.group(1), index)] = float(match.group(4))
    return levels


def variable_names(coal):
    """{variable: description} in the order of the GDX file"""
    result = subprocess.run([find_gdxdump(), 'sol.gdx', 'Symbols'], cwd=os.path.join(RESULTS, coal),
                            capture_output=True, text=True)
    names = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 5)                     # number, name, dimension, type, records, description
        if len(parts) >= 5 and parts[3] == 'Var':
            names[parts[1]] = parts[5] if len(parts) == 6 else ''
    return names


def read_variables(coalitions=COALITIONS):
    """Every variable level: one row per variable and index, one column per Coalition and RG (or per EcO/EnO run)"""
    columns = {}
    names = {}
    for coal in coalitions:
        if not solved(coal):
            continue
        if len(names) == 0:
            names = variable_names(coal)
        if run_objective(coal) == 'MOO':
            for rg, point in points(coal):
                columns[coal + ' RG ' + '{:g}'.format(rg)] = read_levels(coal, 'point_' + point + '.gdx')
        else:
            columns[coal + ' ' + run_objective(coal)] = read_levels(coal, 'sol.gdx')
    indices = {name: [] for name in names}
    for levels in columns.values():
        for name, index in levels:
            if name in indices and index not in indices[name]:
                indices[name].append(index)
    rows = []
    for name in names:
        for index in indices[name] or ['']:             # a variable that is 0 everywhere gets one row
            row = {'variable': name, 'index': index, 'description': names[name]}
            for column in columns:
                row[column] = columns[column].get((name, index), 0.0)
            rows.append(row)
    return pd.DataFrame(rows)


def save(sweep, variables):
    """The tables as CSV files and as the sheets of results.xlsx"""
    tables = {'sweep': sweep, 'variables': variables}
    try:
        for name in tables:
            tables[name].to_csv(os.path.join(RESULTS, name + '.csv'), index=False)
        with pd.ExcelWriter(os.path.join(RESULTS, 'results.xlsx'), engine='openpyxl') as excel:
            for name in tables:
                tables[name].to_excel(excel, sheet_name=name, index=False)
    except PermissionError:
        print('Close the CSV files and results.xlsx in Excel and run again')


# ======================================================================================================================
# RUN
# ======================================================================================================================
if __name__ == '__main__':
    solve_all()
    save(read_sweep(), read_variables())
    print('Results in', RESULTS)
