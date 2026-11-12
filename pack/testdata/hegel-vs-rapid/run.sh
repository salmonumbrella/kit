#!/usr/bin/env bash
# Compare the Rapid and Hegel pack round-trip properties on planted bugs.
# Usage, from the repository root: pack/testdata/hegel-vs-rapid/run.sh [runs]
# Each mutation is applied, both tests run at 40 cases (kit's setting) and
# 100 cases (both tools' default), and the mutation is reverted.
set -euo pipefail
runs=${1:-5}
dir=pack/testdata/hegel-vs-rapid
bin=$(mktemp -d)
trap 'rm -rf "$bin"' EXIT
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
git diff --quiet -- pack || { echo "pack has local changes; commit or stash them first" >&2; exit 1; }

build() { # name, extra patch...
	local out=$1; shift
	for p in "$@"; do git apply "$p"; done
	if ! (cd pack && go test -c -o "$bin/$out" . >/dev/null); then
		for p in "$@"; do git apply -R "$p"; done
		exit 1
	fi
	for p in "$@"; do git apply -R "$p"; done
}

printf '%-24s %-6s %5s %5s %8s  %s\n' mutation tool cases found avg_s first_counterexample
for m in none "$dir"/[0-9]*.patch; do
	name=$(basename "$m" .patch)
	extra=(); [ "$m" = none ] || extra=("$m")
	build "$name-40" ${extra[@]+"${extra[@]}"}
	build "$name-100" ${extra[@]+"${extra[@]}"} "$dir/rapid-100-cases.patch"
	for cases in 40 100; do
		for tool in rapid hegel; do
			if [ "$tool" = rapid ]; then test=TestPackRoundTripProperty; else test=TestPackRoundTripHegel; fi
			found=0 total=0 example=""
			for _ in $(seq "$runs"); do
				rm -rf pack/.hegel pack/testdata/rapid
				start=$(now)
				out=$(cd pack && PACK_PROPERTY_CASES=$cases "$bin/$name-$cases" -test.run "^$test\$" -test.count=1 2>&1) && ok=1 || ok=0
				total=$(echo "$total + $(now) - $start" | bc)
				if [ "$ok" = 0 ]; then
					found=$((found + 1))
					[ -n "$example" ] || example=$(echo "$out" | grep -m1 -E 'draw blobs|hegel.Draw\(ht, blobSets\)' | sed -E 's/.*(draw blobs: |= )//' | cut -c1-90)
				fi
			done
			rm -rf pack/.hegel pack/testdata/rapid
			printf '%-24s %-6s %5s %3s/%-1s %8.2f  %s\n' "$name" "$tool" "$cases" "$found" "$runs" "$(echo "$total / $runs" | bc -l)" "$example"
		done
	done
done
