#!/bin/bash

float_scale=2

function float_eval()
{
local stat=0
local result=0.0
if [[ $# -gt 0 ]]; then
result=$(echo "scale=$float_scale; $*" | bc -q 2>/dev/null)
stat=$?
if [[ $stat -eq 0  &&  -z "$result" ]]; then stat=1; fi
fi
echo "RESULT=$result"
return $stat
}

echo $2*1000 | bc -q 2>/dev/null

float_eval "($2 - 8.15)*($2 - 8.15) + ($4 - 3.83)*($4 - 3.83) + ($6 - 9.99)*($6 - 9.99)"
