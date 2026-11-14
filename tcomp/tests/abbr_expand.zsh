#!/usr/bin/env zsh -f
# Unit test for Enter-time abbreviation expansion (_tcomp_abbr_expand_line),
# run against tcomp.zsh and abbr.tsv in this repo. Usage: zsh -f tests/abbr_expand.zsh
here=${0:A:h:h}
source $here/tcomp.zsh >/dev/null 2>&1
_tcomp_abbr_file=$here/abbr.tsv; _tcomp_abbr_stamp=''
integer failed=0
t() {
  BUFFER=$1; CURSOR=${#BUFFER}
  _tcomp_abbr_expand_line; local rc=$?
  local got="$BUFFER"; (( rc )) && got+="  [edit, cursor=$CURSOR]"
  if [[ $got == "$2" ]]; then print -r "ok    $1  →  $got"
  else print -r "FAIL  $1  →  $got   (want $2)"; (( failed++ )); fi
}
t 'll'                    'ls -GplAh'
t 'll src'                'ls -GplAh src'
t 'md a b'                'mkdir -p a b'
t 'echo ll'               'echo ll'
t 'echo "x; ll"'          'echo "x; ll"'
t 'echo hi && gst'        'echo hi && git status'
t 'gst; ll | head'        'git status; ls -GplAh | head'
t 'gc -m'                 'git commit -m ""  [edit, cursor=15]'
t 'gc -m "msg"'           'git commit -m "msg"'
t 'gc'                    'git commit'
t 'gpo main'              'git push origin main'
t 'gpo'                   'git push origin   [edit, cursor=16]'
t 'll; gc -m'             'ls -GplAh; git commit -m ""  [edit, cursor=26]'
t 'gc -m; ll'             'git commit -m ""; ls -GplAh  [edit, cursor=15]'
t 'lls'                   'lls'
t '-'                     'cd -'
t '3'                     'cd -3'
t 'git status'            'git status'
t '  ll'                  '  ls -GplAh'
t $'ll\ngst'              $'ls -GplAh\ngit status'
t ''                      ''
print "abbreviation expansion: $(( failed ? failed : 0 )) failed"; exit $(( failed > 0 ))
