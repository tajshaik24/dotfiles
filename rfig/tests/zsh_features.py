"""Run: python3 rfig/tests/zsh_features.py (needs tmux and rfig on PATH).

Tab acceptance, abbreviations, the empty-line history menu and flag descriptions in zsh."""
import os, subprocess, tempfile, time, shutil, sys
from pathlib import Path

RFIG = Path(__file__).resolve().parents[1]
SHOTS = Path(tempfile.mkdtemp(prefix='rfig-shots-'))

temp = tempfile.mkdtemp(prefix='rfigx-')
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

cfg = home / '.config/rfig'; cfg.mkdir(parents=True)
shutil.copy(RFIG / 'abbr.tsv', cfg / 'abbr.tsv')
(cfg / 'history.tsv').write_text(''.join(f'{repo}\x1f{c}\n' for c in [
    'git status', 'echo first', 'ls -la src', 'echo first', 'git log --oneline', 'echo newest']) +
    f'{other}\x1fecho elsewhere\n')
bins = home / 'bin'; bins.mkdir(); (bins / 'rfig').symlink_to(shutil.which('rfig') or sys.exit('rfig not on PATH: brew bundle first'))
(home / '.zshrc').write_text(f"""PROMPT='T> '
autoload -Uz compinit; compinit -D
source {RFIG}/rfig.zsh
""")
env = dict(os.environ, HOME=temp, ZDOTDIR=temp, XDG_CONFIG_HOME=str(home / '.config'),
           PATH=f'{bins}:' + os.environ['PATH'], TERM='xterm-256color', LANG='C.UTF-8', LC_ALL='C.UTF-8')
tm = ['tmux', '-u', '-L', f'rfigx-{os.getpid()}', '-f', '/dev/null']
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
    ok('git pus → ' + last())
    clear()
    keys('-l', 'ls -la '); wait(lambda: 'src' in screen() and 'docs' in screen(), 'local dirs'); settle(); shot('ls-la-local')
    ok('ls -la lists repo folders')
    clear()
    keys('-l', 'ls ~/'); wait(lambda: 'Projects' in screen() and 'Music' in screen(), 'home dirs'); settle(); shot('ls-home')
    keys('Tab'); wait(lambda: line().startswith('ls ~/') and len(line().strip()) > 5, 'tab accepted home dir'); settle(); shot('ls-home-accepted')
    ok('ls ~/ lists home folders, Tab accepts: ' + line().strip())
    clear()

    # 4. Tab skips the history row
    keys('-l', 'git l'); wait(lambda: '◷ git log --oneline' in screen(), 'history row'); settle(); shot('history-row')
    keys('Tab'); settle()
    assert line().strip() != 'git log --oneline', 'Tab took the history row: ' + line()
    ok('Tab skips ◷ history row → ' + line().strip())
    clear()

    # 5. Up on an empty line opens history menu
    keys('Up'); wait(lambda: '◷ echo newest' in screen(), 'history menu'); settle(); shot('up-history-menu')
    rows = [l for l in screen().splitlines() if '◷' in l]
    assert '→' in rows[0] and 'echo newest' in rows[0], rows
    assert sum('echo first' in r for r in rows) == 1, 'dedupe failed'
    assert not any('elsewhere' in r for r in rows), 'other folder leaked'
    ok('Up opens folder history, newest first, deduped')
    keys('Up'); settle(); keys('Up'); settle(); shot('up-up-up')
    sel = [l for l in screen().splitlines() if '→' in l][0]
    assert 'echo first' in sel, sel
    ok('Up again goes further back: ' + sel.strip())
    keys('Down'); settle(); keys('Down'); settle(); keys('Down'); settle()
    assert '◷' not in screen(), 'menu should close past newest'
    ok('Down past newest closes menu')
    keys('Up'); wait(lambda: '◷' in screen(), 'reopen'); keys('Up'); settle()
    keys('Right'); wait(lambda: line().startswith('git log --oneline'), 'Right fills'); settle()
    ok('Right fills the selected command for editing')
    clear()
    out = home / 'ran'
    (cfg / 'history.tsv').open('a').write(f'{repo}\x1ftouch {out}\n')
    keys('-l', 'cd .'); keys('Enter'); settle()                       # reload history (chpwd)
    keys('Up'); wait(lambda: '◷ touch' in screen() or '◷ cd .' in screen(), 'menu'); settle(); shot('before-enter')
    if '→ ◷ cd .' in screen(): keys('Up'); settle()
    keys('Enter'); wait(out.exists, 'Enter ran selected command')
    ok('Enter runs the highlighted history command')
    settle()
    keys('Up'); wait(lambda: '◷' in screen(), 'menu'); keys('C-g'); settle()
    assert '◷' not in screen() and line().strip() == ''
    ok('Ctrl+G closes the menu')
    keys('-l', 'echo x'); settle(); keys('Up'); settle()
    assert '◷ echo newest' not in screen() or line().startswith('echo x')
    ok('Up with text typed keeps rfig behaviour')
    print(f'zsh features: all {len(passed)} checks OK')
finally:
    subprocess.run(tm + ['kill-server'], capture_output=True)
