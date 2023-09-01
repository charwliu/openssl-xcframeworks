#!/bin/bash

#—————————————————————————————————————————————————————————————————————————————————————————
# Spinner for lengthy operations
#
#—————————————————————————————————————————————————————————————————————————————————————————
spinner()
{
  [ -o xtrace ]
  local _XTRACE=$?
  if [[ $_XTRACE -eq 0 ]]; then { set +x; } 2>/dev/null; fi
  
  local pid=$!
  local delay=0.75
  local spinstr='|/-\' #\'' (<- fix for some syntax highlighters)
  while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
    local temp=${spinstr#?}
    printf "  [%c]" "$spinstr"
    local spinstr=$temp${spinstr%"$temp"}
    sleep $delay
    printf "\b\b\b\b\b"
  done

  wait $pid
  if [[ $_XTRACE -eq 0 ]]; then set -x; fi
  return $?
}
