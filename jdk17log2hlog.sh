#!/bin/bash

#

EXTENSION="${1##*.}"

if [[ "$EXTENSION"x == "gz"x ]]; then
  CAT="zcat"
  BASENAME=`basename -s .txt.gz $1`
else
  CAT="cat"
  BASENAME=`basename -s .txt $1`
fi
DIRNAME=`dirname $1`
TMPNAME=$DIRNAME/$BASENAME.tmp
OUTNAME=$DIRNAME/$BASENAME.hlog

$CAT $1 | awk 'BEGIN {start = -1; } /info\]\[safepoint/ { split(substr($1, 2), a, /s\]\[/); t=gensub(",", ".", 1, a[1])*1000; if (start==-1) start = t; printf "%4.0f %s\n", t - start, $18 / 1000000.0; }' > $TMPNAME

JAVA=${JAVA:-"java"}
JHICCUP=${JHICCUP:-"jHiccup.jar"}

$JAVA -jar $JHICCUP -i 5000 -f $TMPNAME -fz -l $OUTNAME

rm $TMPNAME
