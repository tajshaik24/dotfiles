# Everything this Mac needs from Homebrew. install.sh runs:
#   brew bundle --file=~/Developer/dotfiles/Brewfile
# Safe to run repeatedly; brew only installs what's missing.
# List anything installed that isn't here: brew bundle cleanup --file=Brewfile

# Shell (zshrc, tcomp)
brew "rust"                       # builds tcomp from ./tcomp
brew "zsh-syntax-highlighting"
brew "fzf"                        # gcb abbreviation: pick a branch to check out
brew "tmux"                       # tmux.conf; tcomp's end-to-end test
brew "direnv"                     # per-directory env (hooked in ~/.zshrc.local)
brew "openssl@3"                  # on PATH and in LDFLAGS/CPPFLAGS (zshrc)

# Dev tools
brew "gh"                         # GitHub CLI
brew "go"                         # GOPATH set in zshrc
brew "nvm"                        # Node versions (Homebridge runs on nvm's Node 22)
brew "uv"                         # Python packages and tools
brew "poppler"                    # PDF tools: pdftotext, pdftoppm
brew "xcodegen"                   # Xcode projects from a spec
brew "openjdk@17"                 # Android builds (muslim-smart-home sets JAVA_HOME to it)
brew "jq"                         # JSON CLI; rex-agent-restore needs it
brew "mole"                       # clean up and optimize the Mac

# Apps
cask "1password"
cask "1password-cli"
cask "android-commandlinetools"   # Android SDK: platform-tools, android-35, build-tools 35
cask "claude"
cask "cursor"
cask "font-jetbrains-mono"
cask "miniconda"                  # conda, auto-detected by zshrc
cask "notion-calendar"
cask "orbstack"
cask "zoom"
