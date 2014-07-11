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
echo $result
return $stat
}

float_eval "($2 - 8.15) + ($4 - 3.83) + ($6 - 9.99)"
