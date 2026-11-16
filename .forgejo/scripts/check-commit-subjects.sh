#!/usr/bin/env bash
# the one home of the commit subject walk: the subjects workflow of the
# forge and the worker gate of the factory skill call this file, so the
# forge layer and the local layer cannot drift (issue 439)
# fail on any error
set -euo pipefail

# one argument: the commit range, for example main..HEAD
if [[ $# -ne 1 ]]; then
	echo "usage: check-commit-subjects.sh <base>..<head>" >&2
	exit 2
fi

# the pattern of the COMMITS section of AGENTS.md: type, optional scope,
# optional breaking mark, colon, one space, and a lowercase summary start
pattern='^(feat|fix|refactor|style|chore|ci|docs|revert)(\([a-z0-9][a-z0-9-]*\))?!?: [a-z]'

# a broken range fails the run, so a typo cannot pass the gate silently;
# an empty range holds no subject and passes
if ! subjects=$(git log --format='%s' --no-merges "$1"); then
	echo "not a readable commit range: $1" >&2
	exit 2
fi
if [[ -z "$subjects" ]]; then
	exit 0
fi

status=0
while IFS= read -r subject; do
	# at most 72 characters in the subject
	if [[ ${#subject} -gt 72 ]]; then
		echo "subject is longer than 72 characters: ${subject}"
		status=1
	fi
	if ! [[ $subject =~ ${pattern} ]]; then
		echo "subject does not follow conventional commits (see AGENTS.md, section COMMITS): ${subject}"
		status=1
	fi
	# no trailing period
	if [[ ${subject} == *. ]]; then
		echo "subject ends with a period: ${subject}"
		status=1
	fi
done <<< "$subjects"
exit "$status"
