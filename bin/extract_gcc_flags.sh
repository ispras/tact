#!/bin/bash

build_xml() {

    in_file=$1
    out_file=$2
    echo > $out_file
    cat $in_file | while read LINE
    do
        #<flag type="gcc_flag" value="-m64"/>
        echo "<flag type=\"gcc_flag\" value=\"$LINE\"/>" >> $out_file
   done
}


gcc  -march=native -v -Q --help=target | grep "\[" | awk '{print $1}' | grep "\-m" &> tmp.1
build_xml tmp.1 result_tgt

gcc  -march=native -v -Q --help=optimizers | grep "\[" | awk '{print $1}' | grep "\-f" &> tmp.1
build_xml tmp.1 result_opt


