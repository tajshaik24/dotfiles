complete -c tcomp -f
complete -c tcomp -n '__fish_use_subcommand' -a 'setup init analyze completion'
complete -c tcomp -n '__fish_seen_subcommand_from completion' -a 'zsh bash fish'
complete -c tcomp -n '__fish_seen_subcommand_from analyze' -a '(cat ~/.config/tcomp/commands.txt 2>/dev/null)'
complete -c tcomp -n '__fish_seen_subcommand_from setup' -l shell -r -a 'zsh bash fish'
