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
command -v node >/dev/null 2>&1 \
  || fail "Node.js was not found on PATH. The JS tests need it; install it from https://nodejs.org/ and retry."

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
  for library in polymod hxcpp jsonpath jsonpatch thx.semver thx.core; do
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

# Runs every target even if an earlier one fails, so one run reports all broken targets.
failed_targets=()
run_target() {
  local name="$1"
  local hxml="$2"
  printf 'Running Polymod HScript regression tests with Haxe %s (%s)...\n' "$haxe_version" "$name"
  if ! haxe "$hxml"; then
    failed_targets+=("$name")
  fi
}

# Git Bash and Cygwin on Windows need the Windows binary path.
case "$OSTYPE" in
  msys* | cygwin*) cpp_hxml='tests/run-cpp-windows.hxml' ;;
  *) cpp_hxml='tests/run-cpp-unix.hxml' ;;
esac

run_target 'Interp' tests/run-interp.hxml
run_target 'HXCPP' "$cpp_hxml"
run_target 'JS' tests/run-js.hxml

if (( ${#failed_targets[@]} > 0 )); then
  fail "The tests failed on: ${failed_targets[*]}. Review the test summaries and errors above."
fi

printf '\nAll Polymod tests passed.\n'
pause_if_interactive
