#!/bin/bash

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BOLD="\e[1m"
DEFAULT="\e[39m"

if [ $# -ne 2 ]
then
  printf "error: must pass the test file folder\n"
  printf "usage: $0 <zwasm> <some-folder>\n"
  exit 1
fi

ok=()
ko=()
sf=()
SECONDS=0
for f in `find . $2 -name '*.txt'`
do
  tool=`grep TOOL $f | sed -e 's/;;; TOOL: \(.*\)/\1/g'`
  error=`grep ERROR $f | sed -e 's/;;; ERROR: \(.*\)/\1/g'`
  if [[ ! -z $tool && "$tool" == "wat2wasm" && -z $error ]]
  then
    printf "$1 $f"
    $1 < $f > /dev/null 2>&1
    return_code=$?
    case $return_code in
      0)
        ok+=($f)
        printf " ${BOLD}${GREEN}OK${DEFAULT}\n"
        ;;
      1)
        ko+=($f)
        printf " ${BOLD}${YELLOW}KO${DEFAULT}\n"
        ;;
      134)
        sf+=($f)
        printf " ${BOLD}${RED}SF${DEFAULT}\n"
        ;;
    esac
  fi
done

printf "\nSegmentation faults:\n"
for segmentation_faults in ${sf[@]}
do
  printf "  ${BOLD}${RED}$segmentation_faults${DEFAULT}\n"
done
printf "\n${BOLD}${GREEN}${#ok[@]}${DEFAULT} passes ${BOLD}${YELLOW}${#ko[@]}${DEFAULT} failures ${BOLD}${RED}${#sf[@]}${DEFAULT} crashes (in ${SECONDS}s)\n"

