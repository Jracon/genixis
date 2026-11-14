#!/usr/bin/env bash

path=$1
length=$2
absolute=$3

for ((i = 1; i <= length; i++)); do
	if [ "$#" -eq 3 ]; then
		printf "%s%02i - %03i\n" "$path" $i $absolute
	elif [ "$#" -eq 2 ]; then
		printf "%s%02i\n" "$path" $i
	fi

	((absolute++))
done
