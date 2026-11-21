"""Run: python3 tcomp/tests/zsh_features.py (needs tmux and tcomp on PATH).

Tab acceptance, abbreviations, the empty-line history menu, flag descriptions,
background completion, the per-word cache, arrow-key responsiveness and Ctrl+R
history search in zsh."""
import os, re, subprocess, tempfile, time, shutil, sys
from pathlib import Path

TCOMP = Path(__file__).resolve().parents[1]
SHOTS = Path(tempfile.mkdtemp(prefix='tcomp-shots-'))

temp = tempfile.mkdtemp(prefix='tcompx-')
home = Path(temp)
repo = home / 'repo'; repo.mkdir()
other = home / 'other'; other.mkdir()
def sh(*a, cwd=repo): subprocess.run(a, cwd=cwd, check=True, capture_output=True)
sh('git', 'init', '-q', '-b', 'main')
sh('git', '-c', 'user.email=a@b', '-c', 'user.name=t', 'commit', '-q', '--allow-empty', '-m', 'init')
sh('git', 'branch', 'feature-login'); sh('git', 'branch', 'fix-typo')
sh('git', 'remote', 'add', 'origin', str(home / 'remote.git'))
(repo / 'src').mkdir(); (repo / 'docs').mkdir(); (repo / 'README.md').write_text('hi')
(home / 'Projects').mkdir(); (home / 'Music').mkdir()

cfg = home / '.config/tcomp'; cfg.mkdir(parents=True)
shutil.copy(TCOMP / 'abbr.tsv', cfg / 'abbr.tsv')
LONG = 'echo this-history-entry-is-much-longer-than-forty-one-columns-and-must-show-in-full'
(cfg / 'history.tsv').write_text(''.join(f'{repo}\x1f{c}\n' for c in [
    LONG, 'git status', 'echo first', 'ls -la src', 'echo first', 'git log --oneline', 'echo newest']) +
    f'{other}\x1fecho elsewhere\n')
NOW = int(time.time())
RAN = cfg / 'ran.tsv'   # Ctrl+R history: <time>\t<command>, oldest first; repeats keep the newest
SEED = (f'0\tgit checkout main\n{NOW-7200}\tgit commit -m wip\n{NOW-3600}\tcargo build\n'
        f'{NOW-1800}\techo git\n{NOW-5}\tgit commit -m wip\n')
RAN.write_text(SEED)
bins = home / 'bin'; bins.mkdir(); (bins / 'tcomp').symlink_to(shutil.which('tcomp') or sys.exit('tcomp not on PATH: brew bundle first'))
(home / '.zshrc').write_text(f"""PROMPT='T> '
autoload -Uz compinit; compinit -D
source {TCOMP}/tcomp.zsh
# A completer that takes 0.6s, like git listing branches, but deterministic.
slowcmd() {{ :; }}
_slowcmd() {{ sleep 0.6; compadd -- alpha-one alpha-two beta-three; }}
compdef _slowcmd slowcmd
""")
env = dict(os.environ, HOME=temp, ZDOTDIR=temp, XDG_CONFIG_HOME=str(home / '.config'),
           PATH=f'{bins}:' + os.environ['PATH'], TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8')
tm = ['tmux', '-u', '-L', f'tcompx-{os.getpid()}', '-f', '/dev/null']
def call(*a): return subprocess.check_output(tm + list(a), env=env, text=True, timeout=5)
def keys(*a): call('send-keys', '-t', 't', *a)
def raw(): return call('capture-pane', '-p', '-t', 't')
def screen(): return raw().rsplit('T>', 1)[-1].removeprefix(' ')
def last(): return [l for l in screen().splitlines() if l.strip()][-1].strip()
def line(): return screen().splitlines()[0] if screen().splitlines() else ''
def wait(check, msg, t=6):
    end = time.monotonic() + t
    while time.monotonic() < end:
        try:
            if check(): return
        except IndexError: pass
        time.sleep(.03)
    raise AssertionError(msg + '\n---\n' + screen())
def settle(): time.sleep(.35)
n = [0]
def shot(name):
    n[0] += 1; (SHOTS / f'{n[0]:02d}-{name}.txt').write_text(screen())
def clear(): keys('C-u'); wait(lambda: line().strip() == '', 'cleared'); settle()
passed = []
def ok(name): passed.append(name); print('PASS', name, flush=True)

try:
    call('new-session', '-e', 'LANG=C.UTF-8', '-e', 'LC_ALL=C.UTF-8', '-d', '-s', 't', '-c', str(repo), '-x', '100', '-y', '24', 'zsh', '-i')
    call('set-option', '-g', 'status', 'off')
    wait(lambda: 'T>' in raw(), 'prompt')
    settle()

    # 1. Tab walks git → push → origin → branch
    keys('-l', 'git pus'); wait(lambda: 'push' in screen(), 'menu shows push'); settle(); shot('git-pu-menu')
    keys('Tab'); wait(lambda: line().rstrip()=='git push', 'tab accepted push'); settle(); shot('after-push')
    wait(lambda: 'origin' in screen(), 'remote menu')
    keys('-l', 'or'); wait(lambda: line().rstrip()=='git push or', 'typed or'); settle(); shot('origin-filtered')
    keys('Tab'); wait(lambda: line().rstrip()=='git push origin', 'tab accepted origin'); settle(); shot('after-origin')
    wait(lambda: 'feature-login' in screen() or 'main' in screen(), 'branch menu'); shot('branch-menu')
    keys('-l', 'fe'); wait(lambda: 'feature-login' in screen(), 'filtered'); settle()
    keys('Tab'); wait(lambda: line().startswith('git push origin feature-login'), 'branch accepted')
    ok('Tab: git push origin <branch>')
    clear()

    # 2. Abbreviations
    keys('-l', 'gc -m'); settle(); shot('abbr-hint')
    assert '⇥ git commit -m ""' in screen(), screen()
    keys('Tab'); wait(lambda: line().startswith('git commit -m ""'), 'abbr expanded'); settle()
    keys('-l', 'hello'); wait(lambda: line().startswith('git commit -m "hello"'), 'cursor inside quotes'); shot('abbr-cursor')
    ok('Abbreviation: gc -m → git commit -m "▌"')
    clear()
    keys('-l', 'gst'); settle(); keys('Tab'); wait(lambda: line().rstrip()=='git status', 'gst expanded')
    ok('Abbreviation without cursor marker adds trailing space')
    clear()
    keys('-l', 'echo hi && gp'); settle(); keys('Tab'); wait(lambda: line().rstrip()=='echo hi && git push', 'after &&')
    ok('Abbreviation after &&')
    clear()
    keys('-l', 'echo gst'); settle(); keys('Tab'); settle()
    assert 'git status' not in line(), line()
    ok('Abbreviation not expanded as an argument')
    clear()

    # 3. ls flags with descriptions, then paths
    keys('-l', 'ls -'); wait(lambda: len(screen().splitlines()) > 3, 'ls flag menu'); settle(); shot('ls-flags')
    keys('Down'); settle(); shot('ls-flag-description')
    desc = last()
    assert desc and desc != 'History', 'no flag description: ' + screen()
    ok('ls - shows flags with descriptions: ' + [l for l in screen().splitlines() if '→' in l][0].strip() + ' — ' + desc)
    clear()
    # Long flag + description (git, since macOS ls has no --almost-all).
    keys('-l', 'git commit --amen'); wait(lambda: '--amend' in screen(), 'long flag'); settle()
    assert 'amend' in last().lower(), screen()
    ok('git commit --amen → ' + last())
    clear()
    keys('-l', 'git pus'); wait(lambda: 'push' in screen(), 'push'); settle()
    assert 'update remote' in screen(), screen()
    push_row = next(l for l in screen().splitlines()[1:] if 'push' in l)
    assert re.search(r'push ★', push_row) and not re.search('[①②③]', screen()), push_row   # picked with Tab in 1.
    ok('A completion you have picked before is marked ★: ' + push_row.strip())
    ok('git pus → ' + last())
    clear()
    keys('-l', 'ls -la '); wait(lambda: 'src' in screen() and 'docs' in screen(), 'local dirs'); settle(); shot('ls-la-local')
    ok('ls -la lists repo folders')
    clear()
    keys('-l', 'ls ~/'); wait(lambda: 'Projects' in screen() and 'Music' in screen(), 'home dirs'); settle(); shot('ls-home')
    keys('Tab'); wait(lambda: line().startswith('ls ~/') and len(line().strip()) > 5, 'tab accepted home dir'); settle(); shot('ls-home-accepted')
    ok('ls ~/ lists home folders, Tab accepts: ' + line().strip())
    clear()

    # 4. No history row while typing (history is Up / Ctrl+R)
    keys('-l', 'git l'); wait(lambda: '↳ log' in screen(), 'git l menu'); settle(); shot('no-history-row')
    assert '◷' not in screen() and 'git log --oneline' not in screen(), screen()
    ok('Typing shows no ◷ history row, just completions')
    clear()

    # 5. Up on an empty line opens history menu (newest at the bottom; Up walks up into the past)
    def menu(): return [l for l in screen().splitlines()[1:] if l.strip() and '◷ history' not in l and '↵ run' not in l]
    def sel(): return next((l for l in screen().splitlines() if '→' in l), '')
    keys('Up'); wait(lambda: 'echo newest' in screen() and line().strip() == '', 'history menu'); settle(); shot('up-history-menu')
    rows = menu()
    assert rows[-1].startswith('→ echo newest'), rows
    assert [r.lstrip('→ ').split('  ')[0] for r in rows] == [
        LONG[:63] + '…', 'git status',
        'ls -la src', 'echo first', 'git log --oneline', 'echo newest'], rows
    assert '◷ history' in screen().splitlines()[1] and '↵ run' in last(), screen()   # header, rows, hints
    head = next(l for l in screen().splitlines() if '◷ history' in l)
    assert '~/repo' in head and '1/6' in head, head
    assert '↵ run' in screen(), 'key hints footer'
    assert sum('echo first' in r for r in rows) == 1, 'dedupe failed'
    assert not any('elsewhere' in r for r in rows), 'other folder leaked'
    ok('Up opens folder history, oldest on top, newest at the bottom, deduped, with header and key hints')
    keys('Up'); settle(); keys('Up'); settle(); shot('up-up')
    assert 'echo first' in sel(), sel()
    ok('Up moves the highlight up, to older commands: ' + sel().strip())
    keys('Down'); settle()
    assert 'git log --oneline' in sel(), sel()
    keys('Down'); settle(); keys('Down'); settle()
    assert 'echo newest' not in screen(), 'Down on the newest row should close the menu'
    ok('Down moves the highlight down; Down on the newest row closes the menu')
    keys('Up'); wait(lambda: 'echo newest' in screen(), 'reopen'); keys('Up'); settle()
    keys('Right'); wait(lambda: line().startswith('git log --oneline'), 'Right fills'); settle()
    ok('Right fills the selected command for editing')
    clear()
    out = home / 'ran'
    (cfg / 'history.tsv').open('a').write(f'{repo}\x1ftouch {out}\n')
    keys('-l', 'cd .'); keys('Enter'); settle()                       # reload history (chpwd)
    keys('Up'); wait(lambda: 'touch' in screen() and line().strip() == '', 'menu'); settle(); shot('before-enter')
    cd_row = next(r for r in menu() if r.lstrip('→ ').startswith('cd .'))
    assert cd_row.rstrip().endswith('now'), 'age column: ' + cd_row
    ok('History menu shows how long ago each command ran: ' + cd_row.strip())
    if sel().lstrip('→ ').startswith('cd .'): keys('Up'); settle()
    keys('Enter'); wait(out.exists, 'Enter ran selected command')
    ok('Enter runs the highlighted history command')
    settle()
    keys('Up'); wait(lambda: 'touch' in screen(), 'menu'); keys('C-g'); settle()
    assert 'touch' not in screen() and line().strip() == ''
    ok('Ctrl+G closes the menu')
    keys('-l', 'echo x'); settle(); keys('Up'); settle()
    assert line().strip() != '' and not menu()[:1] == ['→ echo newest'], screen()   # no history menu
    ok('Up with text typed keeps tcomp behaviour')
    clear()

    hist = (cfg / 'history.tsv').read_text()
    keys('-l', 'echo timed'); keys('Enter'); settle()
    added = (cfg / 'history.tsv').read_text()[len(hist):].strip().split('\x1f')
    assert added[1] == 'echo timed' and abs(int(added[2]) - time.time()) < 30, added
    keys('Up'); wait(lambda: 'echo timed' in screen() and line().strip() == '', 'menu again'); settle()
    assert menu()[-1].rstrip().endswith('now'), menu()[-1]
    ok('Running a command records when, and the menu shows its age: ' + menu()[-1].strip())
    keys('C-g'); clear()

    # 5b. Enter takes the highlighted completion only after arrowing to it
    def last_hist(): return (cfg / 'history.tsv').read_text().splitlines()[-1].split('\x1f')[1]
    keys('-l', 'ls -d '); wait(lambda: 'src' in screen() and '→' in screen(), 'ls -d menu'); settle()
    keys('Enter'); wait(lambda: last_hist().rstrip() == 'ls -d', 'trailing space runs as typed')
    ok('Enter after a space, without arrowing, runs the line as typed')
    settle()
    keys('-l', 'ls -d s'); wait(lambda: 'src' in screen(), 'menu for s'); settle()
    keys('Enter'); wait(lambda: last_hist() == 'ls -d s', 'half-typed word runs as typed')
    ok('Enter on a half-typed word you did not arrow to runs as typed')
    settle()
    (repo / 'sample.txt').write_text('')
    keys('-l', 'ls -d s'); wait(lambda: 'src' in screen() and 'sample.txt' in screen(), 'two matches'); settle()
    keys('Down'); settle(); pick = sel().split('→', 1)[1].split()[1]
    keys('Enter'); wait(lambda: last_hist().startswith(f'ls -d {pick}'), f'Enter ran the arrowed-to {pick}')
    ok(f'Enter after arrowing to an item runs it: {last_hist()}')
    settle()
    clear()
    clear()

    # 6. Enter expands abbreviations in command position, like aliases
    keys('-l', 'md made/deep'); keys('Enter'); wait((repo / 'made/deep').is_dir, 'md ran as mkdir -p')
    settle()
    assert 'mkdir -p made/deep' in (cfg / 'history.tsv').read_text(), 'history should store the expansion'
    ok('Enter: md made/deep → mkdir -p made/deep (stored expanded in history)')
    keys('-l', 'echo ll > said.txt'); keys('Enter'); wait(lambda: (repo / 'said.txt').exists(), 'echo ran')
    wait(lambda: (repo / 'said.txt').read_text() == 'll\n', 'argument ll must not expand')
    ok('Enter leaves abbreviations in argument position alone')
    settle()
    keys('-l', 'gc -m'); keys('Enter'); wait(lambda: line().startswith('git commit -m ""'), 'gc -m expanded, not run'); settle()
    keys('-l', 'msg'); wait(lambda: line().startswith('git commit -m "msg"'), 'cursor inside quotes')
    ok('Enter on gc -m stops at %| for the message instead of running')
    clear()

    # 7. Responsiveness: slow completers run in the background
    def selected(): return next((l for l in screen().splitlines() if '→' in l), '')
    keys('-l', 'slowcmd '); t0 = time.monotonic(); keys('-l', 'al')
    wait(lambda: line().rstrip() == 'slowcmd al', 'typed text shows')
    took = time.monotonic() - t0
    assert took < 0.4, f'typing waited {took:.2f}s on a 0.6s completer'
    wait(lambda: 'alpha-one' in screen() and 'alpha-two' in screen(), 'background menu arrives', t=4)
    assert 'beta-three' not in screen(), screen()
    ok(f'Typing never waits on a slow completer (text in {took*1000:.0f}ms; menu filled in later)')
    t0 = time.monotonic(); keys('-l', 'pha-o')
    wait(lambda: 'alpha-one' in screen() and 'alpha-two' not in screen(), 'narrowed from cache')
    took = time.monotonic() - t0
    assert took < 0.4, f'narrowing re-ran the completer ({took:.2f}s)'
    ok(f'More letters of the same word filter the cached list ({took*1000:.0f}ms)')
    clear()
    keys('-l', 'slowcmd beta'); keys('Tab')
    wait(lambda: line().startswith('slowcmd beta-three'), 'Tab while loading', t=4)
    ok('Tab while loading waits for the result and accepts it')
    clear()
    keys('-l', 'slowcmd alpha-t'); keys('Right')
    wait(lambda: line().startswith('slowcmd alpha-two'), 'Right while loading', t=4)
    ok('Right while loading accepts the right option')
    clear()
    keys('-l', 'slowcmd al'); keys('Down')
    def rows(): return [l for l in screen().splitlines()[1:] if 'alpha' in l]
    wait(lambda: len(rows()) == 2 and '→' in rows()[1], 'Down moves to the 2nd row of the loaded menu', t=4)
    ok('Down while loading moves within the loaded menu: ' + selected().strip())
    clear()
    keys('-l', 'slowcmd al'); keys('C-u'); keys('-l', 'echo zz'); time.sleep(1.0)
    assert 'alpha' not in screen() and line().rstrip() == 'echo zz', screen()
    ok('A result for an older line is dropped')
    clear()
    keys('-l', 'slowcmd al'); keys('C-c'); time.sleep(1.0)
    assert 'alpha' not in screen(), screen()
    ok('Ctrl+C while loading leaves no menu behind')
    user = os.environ.get('USER') or os.getlogin()
    keys('-l', 'ls ~' + user[:2]); wait(lambda: user in screen(), f'~{user[:2]} lists {user}', t=4)
    ok(f'ls ~{user[:2]} lists users ({user}), which a forked worker cannot look up')
    clear()
    pane = call('display-message', '-p', '-t', 't', '#{pane_pid}').strip()
    kids = subprocess.run(['pgrep', '-P', pane], capture_output=True, text=True).stdout.split()
    assert not kids, f'leftover worker processes: {kids}'
    assert 'TCOMP' not in raw(), raw()
    ok('No leftover workers or protocol text on screen')
    clear()

    # 8. Cache safety: cases where more letters change what's offered
    keys('-l', 'ls -'); wait(lambda: '⚑' in screen(), 'ls flags'); settle()
    keys('-l', 'l'); wait(lambda: '-la' in screen() or '-lh' in screen(), 'combined flags for ls -l')
    ok('ls - then l offers combined flags (options are never filtered from cache)')
    clear()
    keys('-l', 'gi'); wait(lambda: 'git' in screen(), 'commands'); settle()
    keys('-l', 't'); wait(lambda: '↳ add' in screen() or '↳ am' in screen(), "bare git shows git's subcommands")
    ok('gi then t: bare git shows its subcommands, not commands named git*')
    clear()

    # 9. History rows show the whole command
    keys('Up'); wait(lambda: '◷ history' in screen() and line().strip() == '', 'history menu'); settle()
    for _ in range(20):                       # it's an old entry: scroll up to it
        if LONG[:40] in selected(): break
        keys('Up'); time.sleep(.08)
    settle(); shot('long-selected')
    lines = screen().splitlines()
    at = next(i for i, l in enumerate(lines) if '→' in l)
    first, rest = lines[at], lines[at + 1]
    assert first.rstrip() == '→ ' + LONG[:64], first   # no run time recorded: blank age
    assert rest.strip() == LONG[64:] and rest.startswith('  ' + LONG[64:]), rest
    assert all(len(l) < 100 for l in lines), 'no line fills the terminal width'
    assert '↵ run' in last(), screen()
    ok('History menu shows a long command in full, continuing on its own indented line')
    keys('C-g'); clear()

    # 10. Holding Down doesn't queue up behind the selection animation
    keys('-l', 'ls -'); wait(lambda: '⚑' in screen(), 'ls flags'); settle()
    before = selected(); t0 = time.monotonic(); keys(*['Down'] * 10)
    end, prev, changed = time.monotonic() + 2, before, t0
    while time.monotonic() < end:
        cur = selected()
        if cur != prev: prev, changed = cur, time.monotonic()
        if time.monotonic() - changed > 0.25: break
        time.sleep(.02)
    took = changed - t0
    assert prev != before and took < 0.35, f'10 Downs took {took:.2f}s'
    ok(f'10 quick Downs settle in {took*1000:.0f}ms')
    clear()

    # 11. Ctrl+R searches every session's history, like lig
    RAN.write_text(SEED)   # drop what the sections above ran
    def search_open(): return '⌕ search' in screen()
    def hist_rows():   # [(command, age)] between the header and the key hints
        if not search_open(): return []
        out = []
        for l in screen().splitlines()[1:]:
            if not l.strip() or '⌕ search' in l or '↵ fill' in l: continue
            parts = re.split(r'\s{2,}', l.lstrip('→ ').rstrip())
            out.append((parts[0], parts[1] if len(parts) > 1 else ''))
        return out
    keys('C-r'); wait(lambda: len(hist_rows()) == 4, 'Ctrl+R lists each command once')
    assert 'git commit -m wip' in selected(), screen()
    assert 'every session' in screen() and '1/4' in screen() and '↵ fill' in screen(), screen()
    assert hist_rows() == [('git checkout main', ''), ('cargo build', '1h'), ('echo git', '30m'), ('git commit -m wip', 'now')], hist_rows()
    ok('Ctrl+R on an empty line: newest at the bottom, each once, with when it ran')
    keys('-l', 'git'); wait(lambda: len(hist_rows()) == 3, 'typing narrows')
    assert [r[0] for r in hist_rows()] == ['echo git', 'git checkout main', 'git commit -m wip'], hist_rows()
    ok('Typing narrows: commands starting with it before ones containing it')
    keys('C-u'); keys('-l', 'GCM'); wait(lambda: len(hist_rows()) == 2 and 'cargo' not in screen(), 'fuzzy, any case')
    ok('Letters in order match too, ignoring case')
    def coloured(): return call('capture-pane', '-e', '-p', '-t', 't')
    def yellow(row):   # text drawn in yellow, ignoring bold / background codes around it
        row = re.sub(r'\x1b\[(?:1|48;5;\d+|49)m', '', row)
        return re.findall(r'\x1b\[33m([^\x1b]+)', row)
    def plain(row): return re.sub(r'\x1b\[[0-9;]*m', '', row)
    keys('C-u'); keys('-l', 'COMMIT')
    wait(lambda: any(yellow(l) == ['commit'] for l in coloured().splitlines() if 'wip' in plain(l)), 'the matched text is yellow')
    keys('C-u'); keys('-l', 'gcm')
    wait(lambda: any(yellow(l) == ['g', 'c', 'm'] for l in coloured().splitlines() if 'checkout' in plain(l)), 'matched letters are yellow')
    ok('Matched text, or each matched letter, is coloured')
    keys('C-u'); keys('-l', 'GCM'); wait(lambda: len(hist_rows()) == 2, 'back to GCM')
    keys('Up'); wait(lambda: 'git checkout main' in selected(), 'Up picks an older one'); settle()
    keys('Enter'); wait(lambda: line().rstrip() == 'git checkout main', 'Enter puts it on the line'); settle()
    ok('Enter fills the line without running it')
    keys('Enter'); wait(lambda: RAN.read_text().splitlines()[-1].endswith('\tgit checkout main'), 'a successful run is recorded')
    assert RAN.read_text().splitlines()[-1].split('\t')[0] != '0'
    keys('-l', 'false'); keys('Enter'); keys('-l', ' echo secret'); keys('Enter'); keys('-l', 'true'); keys('Enter')
    wait(lambda: RAN.read_text().splitlines()[-1].endswith('\ttrue'), 'true recorded')
    text = RAN.read_text(); assert '\tfalse' not in text and 'secret' not in text, text
    ok('Only commands that exit 0 are kept, and never a leading-space one')
    keys('C-l'); settle()
    with RAN.open('a') as f: f.write(f'{NOW}\techo from-another-tab\n')
    keys('C-r'); wait(lambda: 'echo from-another-tab' in selected(), "another session's commands show")
    ok("Commands from other sessions show up")
    keys('C-r'); wait(lambda: not search_open(), 'Ctrl+R again closes')
    keys('-l', 'git pus'); wait(lambda: 'push' in screen(), 'normal menu'); settle()
    keys('C-r'); settle()
    assert '↳ push' in screen() or 'push' in selected(), 'no match: the completion menu stays\n' + screen()
    keys('C-g'); clear()
    keys('-l', 'cargo'); keys('C-r'); wait(lambda: 'cargo build' in selected(), 'search'); keys('C-g')
    wait(lambda: not search_open() and line().rstrip() == 'cargo', 'Ctrl+G leaves the search, keeping the line')
    ok('Ctrl+R again or Ctrl+G closes; no match keeps the completion menu')
    clear()
    print(f'zsh features: all {len(passed)} checks OK')
    shutil.rmtree(SHOTS, ignore_errors=True)
finally:
    subprocess.run(tm + ['kill-server'], capture_output=True)
    shutil.rmtree(temp, ignore_errors=True)
    if SHOTS.exists():
        print(f'screen captures kept in {SHOTS}', file=sys.stderr)
