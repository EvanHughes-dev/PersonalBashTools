#!/bin/bash

if [[ -z "$1" ]]; then
   echo "No valid ip address"
else	


 target="$1"



 ports=$(nmap -T4 -p- "$target" | grep "open" | cut -d'/' -f1)

 nmap -T4 -p "$ports" -A "$target"

fi
