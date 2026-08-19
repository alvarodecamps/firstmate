#!/usr/bin/env bash
# Operator-level reproduction of the 2026-08-17 retention incident.
# Drives the REAL bin/fm-decision-hold.sh and bin/fm-teardown.sh in a throwaway
# firstmate home at the tracked done_keep = 10. $1 = repo tree to exercise.
set -u
TREE=$1
LABEL=$2
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-retention-$LABEL.XXXXXX")
ID=sample-retention-review

say() { printf '\n=== %s\n' "$*"; }
fm_decisions() {
  PATH="$HOME_DIR/fakebin:$PATH" FM_HOME="$HOME_DIR" \
    FM_STATE_OVERRIDE="$HOME_DIR/state" FM_DATA_OVERRIDE="$HOME_DIR/data" \
    FM_CONFIG_OVERRIDE="$HOME_DIR/config" "$TREE/bin/fm-decision-hold.sh" "$@"
}
fm_teardown() {
  PATH="$HOME_DIR/fakebin:$PATH" FM_GATE_REFUSE_BYPASS=1 FM_ROOT_OVERRIDE="$TREE" \
    FM_HOME="$HOME_DIR" FM_STATE_OVERRIDE="$HOME_DIR/state" \
    FM_DATA_OVERRIDE="$HOME_DIR/data" FM_CONFIG_OVERRIDE="$HOME_DIR/config" \
    "$TREE/bin/fm-teardown.sh" "$@"
}
tasks() { (cd "$HOME_DIR" && tasks-axi "$@"); }

mkdir -p "$HOME_DIR"/{data,state,config,projects,fakebin} "$HOME_DIR/data/$ID"
for t in tmux treehouse no-mistakes gh gh-axi; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME_DIR/fakebin/$t"; chmod +x "$HOME_DIR/fakebin/$t"
done
cp "$TREE/.tasks.toml" "$HOME_DIR/.tasks.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$HOME_DIR/data/backlog.md"

printf '### firstmate tree under test: %s\n' "$TREE"
say "Backlog retention config the captain actually ships (.tasks.toml)"
cat "$HOME_DIR/.tasks.toml"

tasks add "$ID" "Investigate sample retention" --kind scout --repo sample --start >/dev/null
{
  printf 'window=firstmate:fm-%s\n' "$ID"
  printf 'worktree=%s/projects/missing-%s\n' "$HOME_DIR" "$ID"
  printf 'project=%s/projects/sample\n' "$HOME_DIR"
  printf 'harness=codex\nkind=scout\nmode=scout\n'
} > "$HOME_DIR/state/$ID.meta"
printf 'done: report complete\n' > "$HOME_DIR/state/$ID.status"
printf '# Sample retention review\n\nTwelve captain choices remain.\n' > "$HOME_DIR/data/$ID/report.md"

say "Scout registers 12 captain decisions (more than done_keep = 10)"
for k in 01 02 03 04 05 06 07 08 09 10 11 12; do
  fm_decisions hold "$ID" "choice-$k" --title "Choose sample option $k" \
    --reason "captain choice $k pending" --repo sample
  printf 'Use sample option %s.\n' "$k" > "$HOME_DIR/decision-$k.txt"
done

say "Scout records its decision inventory, then verifies it while every hold is open"
fm_decisions complete "$ID" choice-01 choice-02 choice-03 choice-04 choice-05 choice-06 \
  choice-07 choice-08 choice-09 choice-10 choice-11 choice-12
fm_decisions verify "$ID"

say "Captain answers all 12 (choice-01 routes follow-up work, choice-02 is declined)"
tasks add sample-retention-work "Apply sample option 01" --kind ship --repo sample \
  --blocked-by "$ID-decision-choice-01" >/dev/null
fm_decisions resolve "$ID" choice-01 --decision-file "$HOME_DIR/decision-01.txt" --routed-to sample-retention-work
fm_decisions decline "$ID" choice-02 --decision-file "$HOME_DIR/decision-02.txt"
for k in 03 04 05 06 07 08 09 10 11 12; do
  fm_decisions answer "$ID" "choice-$k" --decision-file "$HOME_DIR/decision-$k.txt"
done

say "Firstmate closes the scout in the backlog"
tasks done "$ID" --report "data/$ID/report.md" >/dev/null

say "Live backlog Done section after ordinary tasks-axi pruning (done_keep = 10)"
sed -n '/^## Done/,$p' "$HOME_DIR/data/backlog.md" | grep -E '^- \[x\]' | sed 's/ (.*//'
say "Resolved decisions tasks-axi moved into data/done-archive.md"
grep -E '^- \[x\]' "$HOME_DIR/data/done-archive.md" | sed 's/ (.*//'
say "Captain decision text is intact in the archive (choice-01)"
grep -n "Use sample option 01." "$HOME_DIR/data/done-archive.md" | head -2

say "Completion gate: fm-decision-hold.sh verify $ID"
fm_decisions verify "$ID"; printf 'verify exit=%s\n' "$?"

say "Teardown the captain runs next: bin/fm-teardown.sh $ID"
fm_teardown "$ID"; rc=$?
printf 'teardown exit=%s\n' "$rc"

say "Result for the captain"
if [ "$rc" -eq 0 ]; then
  printf 'teardown COMPLETED; scout state cleared: '
  [ -e "$HOME_DIR/state/$ID.meta" ] && printf 'no (state/%s.meta still present)\n' "$ID" || printf 'yes (state/%s.meta removed)\n' "$ID"
else
  printf 'teardown REFUSED; scout state preserved: '
  [ -e "$HOME_DIR/state/$ID.meta" ] && printf 'yes (state/%s.meta kept)\n' "$ID" || printf 'no\n'
fi
say "Archive is unchanged by the gate read (never rewritten)"
shasum -a 256 "$HOME_DIR/data/done-archive.md" | awk '{print "done-archive.md sha256 " $1}'
rm -rf "$HOME_DIR"
exit "$rc"
