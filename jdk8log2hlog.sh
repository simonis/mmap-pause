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

$CAT $1 | awk 'BEGIN {start = -1; } /Total time for which application threads were stopped/ { split($1, a, "T"); split(a[2], b, "."); split(b[1], c, ":"); split(b[2], d, "+"); t=(((c[1]*60)+c[2])*60+c[3])*1000+d[1]; if (start==-1) start = t; printf "%4.0f %s\n", t - start,  gensub(",", ".", 1, $10)*1000; }' > $TMPNAME

JAVA=${JAVA:-"java"}
JHICCUP=${JHICCUP:-"jHiccup.jar"}

$JAVA -jar $JHICCUP -i 5000 -f $TMPNAME -fz -l $OUTNAME

rm $TMPNAME
