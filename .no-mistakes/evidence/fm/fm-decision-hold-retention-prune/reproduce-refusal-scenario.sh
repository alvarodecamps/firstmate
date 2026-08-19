#!/usr/bin/env bash
# The other half of the contract: reading the archive must NOT let teardown
# accept unverified work. Same throwaway home, same done_keep = 10.
# $1 = repo tree to exercise.
set -u
TREE=$1
HOME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/fm-retention-refusal.XXXXXX")
ID=sample-archived-gap-review
HOLD="$ID-decision-gap"

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
    "$TREE/bin/fm-teardown.sh" "$@" 2>&1 | grep -v '^●'
  return "${PIPESTATUS[0]}"
}
tasks() { (cd "$HOME_DIR" && tasks-axi "$@"); }

mkdir -p "$HOME_DIR"/{data,state,config,projects,fakebin} "$HOME_DIR/data/$ID"
for t in tmux treehouse no-mistakes gh gh-axi; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME_DIR/fakebin/$t"; chmod +x "$HOME_DIR/fakebin/$t"
done
cp "$TREE/.tasks.toml" "$HOME_DIR/.tasks.toml"
printf '## In flight\n\n## Queued\n\n## Done\n' > "$HOME_DIR/data/backlog.md"
printf '### firstmate tree under test: %s\n' "$TREE"

tasks add "$ID" "Investigate an archived sample gap" --kind scout --repo sample --start >/dev/null
{
  printf 'window=firstmate:fm-%s\n' "$ID"
  printf 'worktree=%s/projects/missing-%s\n' "$HOME_DIR" "$ID"
  printf 'project=%s/projects/sample\n' "$HOME_DIR"
  printf 'harness=codex\nkind=scout\nmode=scout\n'
} > "$HOME_DIR/state/$ID.meta"
printf 'done: report complete\n' > "$HOME_DIR/state/$ID.status"
printf '# Sample archived gap review\n\nOne captain choice remains.\n' > "$HOME_DIR/data/$ID/report.md"

say "One captain decision is inventoried, then closed OUTSIDE fm-decision-hold"
fm_decisions hold "$ID" gap --title "Choose the sample gap" --reason "captain gap choice pending" --repo sample
fm_decisions complete "$ID" gap
tasks done "$HOLD" >/dev/null
say "Ten later closes prune that record out of the live backlog"
for p in 01 02 03 04 05 06 07 08 09 10; do
  tasks add "sample-pad-$p" "Sample pad $p" --kind ship --repo sample >/dev/null
  tasks done "sample-pad-$p" >/dev/null
done
grep -qE "^- \[x\] $HOLD " "$HOME_DIR/data/done-archive.md" \
  && printf 'the unanswered close now lives only in data/done-archive.md\n'
grep -c "Resolution recorded by fm-decision-hold" "$HOME_DIR/data/done-archive.md" \
  | sed 's/^/resolution records in the archive: /'
BEFORE=$(shasum -a 256 "$HOME_DIR/data/done-archive.md" | awk '{print $1}')

say "Completion gate: fm-decision-hold.sh verify $ID"
fm_decisions verify "$ID"; printf 'verify exit=%s\n' "$?"

say "Teardown the captain runs next: bin/fm-teardown.sh $ID"
fm_teardown "$ID"; rc=$?
printf 'teardown exit=%s\n' "$rc"
printf 'scout state preserved: '
[ -e "$HOME_DIR/state/$ID.meta" ] && printf 'yes (state/%s.meta kept)\n' "$ID" || printf 'no - WORK WAS ERASED\n'
printf 'scout report preserved: '
[ -e "$HOME_DIR/data/$ID/report.md" ] && printf 'yes\n' || printf 'no - REPORT WAS ERASED\n'

say "No close path can invent the missing captain answer after the fact"
printf 'An answer recorded after the fact.\n' > "$HOME_DIR/late-decision.txt"
for verb in repair answer decline; do
  out=$(fm_decisions "$verb" "$ID" gap --decision-file "$HOME_DIR/late-decision.txt" 2>&1); vrc=$?
  printf '%s -> exit=%s: %s\n' "$verb" "$vrc" "$out"
done
out=$(fm_decisions hold "$ID" gap --title "Choose the sample gap" --reason "captain gap choice pending" --repo sample 2>&1); vrc=$?
printf 'hold (reopen) -> exit=%s: %s\n' "$vrc" "$out"

say "Nothing wrote a resolution record anywhere"
AFTER=$(shasum -a 256 "$HOME_DIR/data/done-archive.md" | awk '{print $1}')
[ "$BEFORE" = "$AFTER" ] && printf 'done-archive.md unchanged (sha256 %s)\n' "$AFTER" || printf 'ARCHIVE WAS REWRITTEN\n'
grep -c "Resolution recorded by fm-decision-hold" "$HOME_DIR/data/backlog.md" \
  | sed 's/^/resolution records in the live backlog: /'
rm -rf "$HOME_DIR"
