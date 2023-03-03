#!/bin/bash
#
# Generates disk load to trigger long mmap write pauses

set -e
#set -x

PARALLEL_DD=2
MAX_PARALLEL_DD=8


# Generate random bytes in case some weird disk system uses compression
echo "generating random source data with $MAX_PARALLEL_DD processes ..."
date
for i in `seq $MAX_PARALLEL_DD`; do
  dd if=/dev/urandom of=rnd-1g-$i bs=1M count=1024 &
done
wait

echo "generating parallel load with $PARALLEL_DD dd processes"
for i in `seq 1000000`; do
  date
  # Drop files from kernel file cache
  for j in `seq $PARALLEL_DD`; do
    dd of=rnd-1g-$j oflag=nocache conv=notrunc,fdatasync count=0
    dd of=rnd-1g-$j-2 oflag=nocache conv=notrunc,fdatasync count=0
  done
  for j in `seq $PARALLEL_DD`; do
    dd if=rnd-1g-$j of=rnd-1g-$j-2 bs=1M &
  done
  wait
  sync
done
