#!/bin/bash
gpg --list-sigs $1 | grep ^sig | cut -d' ' -f9 | sort | uniq > ${1}.ids
gpg --recv-keys `cat ${1}.ids`
gpg --export `cat ${1}.ids` > ${1}.gpg
gpg --no-default-keyring --keyring ./${1}.gpg --list-sigs | sig2dot.pl | neato -Tps > ${1}.ps
