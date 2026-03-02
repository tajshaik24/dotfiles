# Custom git branch completion that prioritizes the current branch
# This override makes the current branch appear first in tab completion
# for all git commands that complete branch names (checkout, merge, rebase, etc.)

# Only override if the original git completion function exists
if (( $+functions[__git_branch_names] )); then

  # Save the original function
  functions[__git_branch_names_original]=$functions[__git_branch_names]

  # Define custom version
  __git_branch_names () {
    local expl
    declare -a branch_names
    local current_branch

    # Get current branch (fails silently if not in git repo or detached HEAD)
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null)

    # Get all branches using git for-each-ref
    branch_names=(${${(f)"$(_call_program branchrefs git for-each-ref --format='"%(refname)"' refs/heads 2>/dev/null)"}#refs/heads/})

    # If we have a current branch, move it to the front
    if [[ -n "$current_branch" ]]; then
      # Remove current branch from array (if it exists)
      branch_names=(${branch_names:#$current_branch})
      # Add current branch to the front
      branch_names=($current_branch $branch_names)
    fi

    # Pass to the git completion system
    _wanted branch-names expl 'branch name' compadd "$@" -a - branch_names
  }

fi
