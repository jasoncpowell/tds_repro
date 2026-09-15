# Helpers shared by bin/compare and bin/verify-upstream. Callers set `status=0`
# before using `report`.

# Prints "<tests run> <failures>" from the ExUnit summary in the given log.
# Elixir 1.20+ prints "Result: 67 passed, 33 excluded" or "Result: 0/33 passed";
# earlier versions print "100 tests, 33 failures, 67 excluded", where the test
# count includes the excluded tests.
test_counts() {
  local log=$1 line
  local new_format='Result: ([0-9]+)(/([0-9]+))? passed'
  local old_format='([0-9]+) tests?, ([0-9]+) failures?(, ([0-9]+) excluded)?'

  line=$(grep -Eo "$new_format" "$log" | tail -1)
  if [[ $line =~ $new_format ]]; then
    local passed=${BASH_REMATCH[1]} total=${BASH_REMATCH[3]:-${BASH_REMATCH[1]}}
    echo "$total $((total - passed))"
    return
  fi

  line=$(grep -Eo "$old_format" "$log" | tail -1)
  if [[ $line =~ $old_format ]]; then
    echo "$((BASH_REMATCH[1] - ${BASH_REMATCH[4]:-0})) ${BASH_REMATCH[2]}"
  fi
}

# Prints an "ok" or "FAIL" line, and sets status=1 on failure.
report() {
  local label=$1 passed=$2 detail=$3
  if [ "$passed" -eq 0 ]; then
    printf '  ok    %s (%s)\n' "$label" "$detail"
  else
    printf '  FAIL  %s (%s)\n' "$label" "$detail"
    status=1
  fi
}
