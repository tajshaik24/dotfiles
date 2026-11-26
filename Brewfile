# Essentials for any Mac, including a work laptop: what the shell setup
# (zshrc, tmux.conf, tcomp) needs, plus everyday tools.
# install.sh always installs this. Projects and personal apps are in
# Brewfile.personal (install.sh --all).

# Shell
brew "rust"                       # builds tcomp from ./tcomp
brew "zsh-syntax-highlighting"
brew "fzf"                        # gcb abbreviation: pick a branch to check out
brew "tmux"                       # tmux.conf; tcomp's end-to-end test
brew "jq"                         # JSON on the command line; install.sh cleanup
brew "direnv"                     # per-directory env (hooked in ~/.zshrc.local)
cask "font-jetbrains-mono"        # terminal font

# Everyday tools
brew "gh"                         # GitHub CLI
brew "mole"                       # clean up and optimize the Mac
cask "1password"
cask "1password-cli"
cask "miniconda"                  # conda, auto-detected by zshrc
cask "orbstack"                   # Docker and Linux VMs
