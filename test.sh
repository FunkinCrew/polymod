#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if [[ "$SCRIPT_PATH" == [A-Za-z]:\\* || "$SCRIPT_PATH" == [A-Za-z]:/* ]]; then
  if ! command -v cygpath >/dev/null 2>&1; then
    printf 'ERROR: Cannot convert the Windows script path. Run this script from Git Bash.\n' >&2
    exit 1
  fi
  SCRIPT_PATH="$(cygpath -u "$SCRIPT_PATH")"
fi
if [[ "$SCRIPT_PATH" != */* ]]; then
  SCRIPT_PATH="./$SCRIPT_PATH"
fi
ROOT_DIR="$(cd -P -- "${SCRIPT_PATH%/*}" && pwd)"
TEST_DIR="$ROOT_DIR/tests"
MIN_HAXE_MAJOR=4
MIN_HAXE_MINOR=3
MIN_HAXE_PATCH=7

pause_before_exit() {
  local status=$?
  trap - EXIT

  if [[ -t 0 ]]; then
    printf '\nPress any key to close...'
    IFS= read -r -n 1 -s _ || true
    printf '\n'
  fi

  exit "$status"
}

report_failure() {
  local status=$?
  if (( status != 0 )); then
    printf '\nERROR: Test setup or execution failed (exit code %s).\n' "$status" >&2
    printf 'Review the output above, correct the issue, and run this script again.\n' >&2
  fi
}

trap report_failure ERR
trap pause_before_exit EXIT

if ! command -v haxe >/dev/null 2>&1; then
  printf 'ERROR: Haxe was not found on PATH.\n' >&2
  printf 'Install Haxe 4.3.7 or newer from https://haxe.org/download/ and reopen your terminal.\n' >&2
  exit 1
fi

if ! command -v haxelib >/dev/null 2>&1; then
  printf 'ERROR: Haxelib was not found on PATH.\n' >&2
  printf 'Reinstall Haxe 4.3.7 or newer and ensure the haxelib command is available.\n' >&2
  exit 1
fi

if ! HAXE_VERSION="$(haxe --version)"; then
  printf 'ERROR: Could not read the Haxe version. Check that "haxe --version" works.\n' >&2
  exit 1
fi

if [[ ! "$HAXE_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  printf 'ERROR: Unrecognized Haxe version: %s\n' "$HAXE_VERSION" >&2
  exit 1
fi

HAXE_MAJOR="${BASH_REMATCH[1]}"
HAXE_MINOR="${BASH_REMATCH[2]}"
HAXE_PATCH="${BASH_REMATCH[3]}"

if (( HAXE_MAJOR < MIN_HAXE_MAJOR ||
      (HAXE_MAJOR == MIN_HAXE_MAJOR && HAXE_MINOR < MIN_HAXE_MINOR) ||
      (HAXE_MAJOR == MIN_HAXE_MAJOR && HAXE_MINOR == MIN_HAXE_MINOR && HAXE_PATCH < MIN_HAXE_PATCH) )); then
  printf 'ERROR: Haxe 4.3.7 or newer is required; found %s.\n' "$HAXE_VERSION" >&2
  printf 'Update Haxe from https://haxe.org/download/ and run this script again.\n' >&2
  exit 1
fi

cd "$TEST_DIR"

missing_dependencies=()
for library in polymod jsonpath jsonpatch thx.semver thx.core; do
  if ! haxelib path "$library" >/dev/null 2>&1; then
    missing_dependencies+=("$library")
  fi
done

if [[ ! -f .haxelib/.repo-version || ${#missing_dependencies[@]} -gt 0 ]]; then
  printf 'Preparing the minimal Haxelib dependencies for the test suite...\n'

  if ! haxelib --global path hmm >/dev/null 2>&1; then
    printf 'Installing HMM...\n'
    haxelib --global install hmm
  fi

  haxelib run hmm install --quiet
fi

printf 'Linking the test environment to this Polymod checkout...\n'
haxelib dev polymod "$ROOT_DIR"

missing_dependencies=()
for library in polymod jsonpath jsonpatch thx.semver thx.core; do
  if ! haxelib path "$library" >/dev/null 2>&1; then
    missing_dependencies+=("$library")
  fi
done

if (( ${#missing_dependencies[@]} > 0 )); then
  printf 'ERROR: These required libraries are still unavailable: %s\n' "${missing_dependencies[*]}" >&2
  exit 1
fi

printf 'Running the Polymod HScript regression suite with Haxe %s...\n' "$HAXE_VERSION"
haxe run.hxml
printf '\nAll Polymod tests passed.\n'
