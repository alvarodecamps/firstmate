#!/usr/bin/env bash
# End-to-end reproduction of the 2026-08-17 retention incident, driven exactly as
# a captain meets it: register captain decisions, answer them, close the scout,
# then run bin/fm-teardown.sh.
#
# Usage: FM_REPO=<firstmate checkout> repro-decision-hold-retention.sh <label>
set -u

FM_REPO=${FM_REPO:?set FM_REPO to the firstmate checkout under test}
LABEL=${1:-run}
export FM_GATE_REFUSE_BYPASS=1   # same exemption tests/lib.sh uses inside a gate worktree

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/fm-retention-repro.XXXXXX")
trap 'rm -rf -- "$TMP_ROOT"' EXIT

say() { printf '\n=== %s ===\n' "$*"; }
cmd() { printf '$ %s\n' "$*"; }

make_home() {  # <name>
  local home="$TMP_ROOT/$1" t
  mkdir -p "$home/data" "$home/state" "$home/config" "$home/projects" "$home/fakebin"
  cp "$FM_REPO/.tasks.toml" "$home/.tasks.toml"
  printf '## In flight\n\n## Queued\n\n## Done\n' > "$home/data/backlog.md"
  for t in tmux treehouse no-mistakes gh gh-axi; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$home/fakebin/$t"
    chmod +x "$home/fakebin/$t"
  done
  printf '%s\n' "$home"
}

tasks_in() { local home=$1; shift; (cd "$home" && tasks-axi "$@"); }

decisions() {  # <home> <args...>
  local home=$1; shift
  PATH="$home/fakebin:$PATH" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
    FM_DATA_OVERRIDE="$home/data" FM_CONFIG_OVERRIDE="$home/config" \
    "$FM_REPO/bin/fm-decision-hold.sh" "$@"
}

teardown() {  # <home> <id>
  local home=$1 id=$2
  PATH="$home/fakebin:$PATH" FM_ROOT_OVERRIDE="$FM_REPO" FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$FM_REPO/bin/fm-teardown.sh" "$id"
}

seed_scout() {  # <home> <id> <headline>
  local home=$1 id=$2 headline=$3
  mkdir -p "$home/data/$id"
  tasks_in "$home" add "$id" "$headline" --kind scout --repo sample --start >/dev/null
  { printf 'window=firstmate:fm-%s\n' "$id"
    printf 'worktree=%s/projects/sample-scratch\n' "$home"
    printf 'project=%s/projects/sample\n' "$home"
    printf 'harness=codex\nkind=scout\nmode=scout\n'; } > "$home/state/$id.meta"
  printf 'done: report complete\n' > "$home/state/$id.status"
  printf '# %s\n\nThe evidence is complete.\n' "$headline" > "$home/data/$id/report.md"
}

printf '################  firstmate decision-hold retention  ################\n'
printf 'label            : %s\n' "$LABEL"
printf 'repo under test  : %s\n' "$FM_REPO"
printf 'fm-decision-hold : sha256 %s\n' "$(shasum -a 256 "$FM_REPO/bin/fm-decision-hold.sh" | awk '{print substr($1,1,16)}')"
printf 'script version   : %s\n' "${FM_SCRIPT_VERSION:-unstated}"

############################################################################
say "SCENARIO A - twelve answered captain decisions, then scout teardown"
############################################################################
HOME_A=$(make_home retention)
ID=sample-retention-review
cmd "cat .tasks.toml   # the tracked backlog retention config, unmodified"
sed 's/^/    /' "$HOME_A/.tasks.toml"

seed_scout "$HOME_A" "$ID" "Investigate sample retention"

printf '\n-- register twelve captain decisions and inventory them --\n'
for k in 01 02 03 04 05 06 07 08 09 10 11 12; do
  decisions "$HOME_A" hold "$ID" "choice-$k" --title "Choose sample option $k" \
    --reason "captain choice $k pending" --repo sample >/dev/null || exit 1
  printf 'Use sample option %s.\n' "$k" > "$HOME_A/decision-$k.txt"
done
cmd "fm-decision-hold.sh complete $ID choice-01 .. choice-12"
decisions "$HOME_A" complete "$ID" choice-01 choice-02 choice-03 choice-04 choice-05 \
  choice-06 choice-07 choice-08 choice-09 choice-10 choice-11 choice-12 | sed 's/^/    /'

printf '\n-- the captain answers all twelve (routed, declined, answered) --\n'
tasks_in "$HOME_A" add sample-retention-work "Apply sample option 01" --kind ship \
  --repo sample --blocked-by "$ID-decision-choice-01" >/dev/null
cmd "fm-decision-hold.sh resolve $ID choice-01 --routed-to sample-retention-work"
decisions "$HOME_A" resolve "$ID" choice-01 --decision-file "$HOME_A/decision-01.txt" \
  --routed-to sample-retention-work | sed 's/^/    /'
cmd "fm-decision-hold.sh decline $ID choice-02"
decisions "$HOME_A" decline "$ID" choice-02 --decision-file "$HOME_A/decision-02.txt" | sed 's/^/    /'
for k in 03 04 05 06 07 08 09 10 11 12; do
  decisions "$HOME_A" answer "$ID" "choice-$k" --decision-file "$HOME_A/decision-$k.txt" | sed 's/^/    /'
done

printf '\n-- firstmate closes the scout in the backlog --\n'
cmd "tasks-axi done $ID --report data/$ID/report.md"
tasks_in "$HOME_A" done "$ID" --report "data/$ID/report.md" >/dev/null

say "where the twelve resolved decision records now live (done_keep = 10)"
cmd "grep -c 'decision-choice' data/backlog.md   # live backlog"
printf '    %s of 12 still live\n' "$(grep -c 'decision-choice' "$HOME_A/data/backlog.md")"
cmd "grep -c 'decision-choice' data/done-archive.md   # done archive"
printf '    %s of 12 archived by ordinary Done pruning\n' "$(grep -c 'decision-choice' "$HOME_A/data/done-archive.md" 2>/dev/null || echo 0)"
cmd "grep 'decision-choice' data/done-archive.md"
grep 'decision-choice' "$HOME_A/data/done-archive.md" 2>/dev/null | sed 's/^/    /'

ARCHIVE_A="$HOME_A/data/done-archive.md"
BEFORE_SUM=$(shasum -a 256 "$ARCHIVE_A" | awk '{print $1}')

say "the captain-facing gate: fm-decision-hold.sh verify"
cmd "fm-decision-hold.sh verify $ID"
decisions "$HOME_A" verify "$ID" > "$HOME_A/verify.out" 2> "$HOME_A/verify.err"
VRC=$?
sed 's/^/    /' "$HOME_A/verify.out"; sed 's/^/    /' "$HOME_A/verify.err"
printf '    exit=%s\n' "$VRC"

say "the captain-facing gate: bin/fm-teardown.sh"
cmd "fm-teardown.sh $ID"
teardown "$HOME_A" "$ID" > "$HOME_A/teardown.out" 2> "$HOME_A/teardown.err"
TRC=$?
sed 's/^/    /' "$HOME_A/teardown.out"; sed 's/^/    /' "$HOME_A/teardown.err"
printf '    exit=%s\n' "$TRC"
if [ "$TRC" -eq 0 ]; then
  printf 'SCENARIO A RESULT: teardown ACCEPTED the fully answered scout.\n'
else
  printf 'SCENARIO A RESULT: teardown REFUSED the fully answered scout (the incident).\n'
fi
printf 'origin metadata after teardown: %s\n' \
  "$([ -f "$HOME_A/state/$ID.meta" ] && echo 'still present (teardown blocked)' || echo 'removed (teardown completed)')"
printf 'archived decision records still present: %s of 12 (never deleted)\n' \
  "$(grep -c 'decision-choice' "$ARCHIVE_A" 2>/dev/null || echo 0)"
AFTER_SUM=$(shasum -a 256 "$ARCHIVE_A" | awk '{print $1}')
printf 'done-archive.md sha256 before the gate ran : %s\n' "$BEFORE_SUM"
printf 'done-archive.md sha256 after  the gate ran : %s\n' "$AFTER_SUM"
printf 'the gate read the archive without writing it: %s\n' \
  "$([ "$BEFORE_SUM" = "$AFTER_SUM" ] && echo yes || echo 'NO - the archive was rewritten')"

############################################################################
say "SCENARIO B - control: a hold closed OUTSIDE fm-decision-hold, then archived"
############################################################################
HOME_B=$(make_home outofband)
GID=sample-archived-gap-review
seed_scout "$HOME_B" "$GID" "Investigate an archived sample gap"
decisions "$HOME_B" hold "$GID" gap --title "Choose the sample gap" \
  --reason "captain gap choice pending" --repo sample >/dev/null
decisions "$HOME_B" complete "$GID" gap >/dev/null
cmd "tasks-axi done $GID-decision-gap    # closed outside fm-decision-hold: nothing was decided"
tasks_in "$HOME_B" done "$GID-decision-gap" >/dev/null
for p in 01 02 03 04 05 06 07 08 09 10; do
  tasks_in "$HOME_B" add "sample-pad-$p" "Sample pad $p" --kind ship --repo sample >/dev/null
  tasks_in "$HOME_B" done "sample-pad-$p" >/dev/null
done
printf 'the unanswered hold is now archived, not live: live=%s archived=%s\n' \
  "$(grep -c "$GID-decision-gap" "$HOME_B/data/backlog.md")" \
  "$(grep -c "$GID-decision-gap" "$HOME_B/data/done-archive.md" 2>/dev/null || echo 0)"
cmd "fm-teardown.sh $GID"
teardown "$HOME_B" "$GID" > "$HOME_B/teardown.out" 2> "$HOME_B/teardown.err"
BRC=$?
sed 's/^/    /' "$HOME_B/teardown.out"; sed 's/^/    /' "$HOME_B/teardown.err"
printf '    exit=%s\n' "$BRC"
if [ "$BRC" -eq 0 ]; then
  printf 'SCENARIO B RESULT: teardown ACCEPTED unverified work - THE GATE IS WEAKENED.\n'
else
  printf 'SCENARIO B RESULT: teardown REFUSED unverified work - the gate holds.\n'
fi
printf 'origin metadata after teardown: %s\n' \
  "$([ -f "$HOME_B/state/$GID.meta" ] && echo 'still present (teardown blocked)' || echo 'removed (teardown completed)')"
printf '\n################  end %s  ################\n' "$LABEL"
