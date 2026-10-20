#!/usr/bin/env bash

set -euo pipefail

pause_if_interactive() {
  if [[ -t 0 ]]; then
    printf '\nPress Enter to close...'
    read -r _
  fi
}

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  pause_if_interactive
  exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)" \
  || fail "Could not open the Polymod repository directory."
cd "$script_dir"

command -v haxe >/dev/null 2>&1 \
  || fail "Haxe was not found on PATH. Install Haxe 4.3.7 or newer from https://haxe.org/download/ and retry."
command -v haxelib >/dev/null 2>&1 \
  || fail "Haxelib was not found on PATH. Reinstall Haxe 4.3.7 or newer and ensure Haxelib is on PATH."

if ! haxe_version="$(haxe --version)"; then
  fail 'Could not read the Haxe version. Run "haxe --version" to check your installation.'
fi

if [[ ! "$haxe_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  fail "Could not parse Haxe version '$haxe_version'. Haxe 4.3.7 or newer is required."
fi

haxe_major="${BASH_REMATCH[1]}"
haxe_minor="${BASH_REMATCH[2]}"
haxe_patch="${BASH_REMATCH[3]}"
if (( haxe_major < 4 || (haxe_major == 4 && haxe_minor < 3) ||
      (haxe_major == 4 && haxe_minor == 3 && haxe_patch < 7) )); then
  fail "Haxe 4.3.7 or newer is required. Detected Haxe $haxe_version."
fi

missing_libraries=()
check_libraries() {
  missing_libraries=()
  local library
  for library in polymod jsonpath jsonpatch thx.semver thx.core; do
    if ! (cd tests && haxelib path "$library" >/dev/null 2>&1); then
      printf 'Missing or unavailable library: %s\n' "$library"
      missing_libraries+=("$library")
    fi
  done
}

if [[ ! -d tests ]]; then
  fail 'Could not open the tests directory.'
fi

check_libraries
if (( ${#missing_libraries[@]} > 0 )); then
  printf 'Installing HMM and preparing the minimal test dependencies...\n'
  if ! haxelib --global path hmm >/dev/null 2>&1; then
    printf 'Installing HMM...\n'
    haxelib --global install hmm || fail 'Could not install HMM. Check the Haxelib output above.'
  fi

  (cd tests && haxelib run hmm install --quiet) \
    || fail 'Dependency setup failed. Check the Haxe/Haxelib output and confirm your internet connection.'

  check_libraries
  if (( ${#missing_libraries[@]} > 0 )); then
    fail 'Some required libraries are still unavailable after setup. Check the Haxelib output above.'
  fi
else
  printf 'All required libraries are available through Haxelib; skipping downloads.\n'
fi

printf 'Running Polymod HScript regression tests with Haxe %s...\n' "$haxe_version"
if ! haxe tests/run.hxml; then
  fail 'The test run failed. Review the test summary and errors above.'
fi

printf '\nAll Polymod tests passed.\n'
pause_if_interactive
