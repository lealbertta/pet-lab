#!/bin/zsh
set -eu
cd "${0:A:h}/.."
print '\nChoose your cat (enter a menu number):\n'
choices=("${(@f)$(node bin/pet-lab.mjs cats)}")
select choice in "${choices[@]}"; do
  if [[ -n "$choice" ]]; then
    node bin/pet-lab.mjs cat "${choice%% *}"
    break
  fi
done
