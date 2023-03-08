# Performance implications of `-XX:+/-PerfDisableSharedMem`

*-This repo based on [Evan Jones](https://www.evanjones.ca/) original [mmap-pause](https://github.com/evanj/mmap-pause) project. See [README_orig.md](README_orig.md) for the original README file.-*

The goal of this project is to investigate the overhead and latency introduecd by the [HotSpot Jvmstat Performance Counters](https://openjdk.org/groups/hotspot/docs/Serviceability.html#bjvmstat) feature which by default writes metrics (i.e. so called "*performance counters*") periodically to a memory mapped file.

## Jvmstat Performance Counters

By default the HotSpot JVM exports a set of performance counters for monitoring various internal subsystems of the JVM. The intention is that updating these counters incurs in zero overhead such that they can be always on. The [jstat](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jstat.html) tool can be used to monitor some of these counters. The full set of counters can be queried with `jcmd <pid> PerfCounter.print` or accessed programatically (see [Accessing Jvmstat counters programatically](#accessing-jvmstat-counters-programatically)).

### Implementation

The Jvmstat performance counters feature is controlled by the `-XX:+/-UsePerfData` command line flag which is on by default. A second flag, `-XX:+/-PerfDisableSharedMem` controls wether the perf data will be exported via a memory mapped file. The flag is off by default meaning that the perf counters will be made available in a memory mapped file with the name `/tmp/hsperfdata_<username>/<pid>` (see [JDK-6938627](https://bugs.openjdk.org/browse/JDK-6938627) and [JDK-7009828](https://bugs.openjdk.org/browse/JDK-7009828)) for why this location can't be changed). This file is also used by other tools like [`jps`](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jps.html), [`jcmd`](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jcmd.html) or [jconsole](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jconsole.html) to discover running JVMS so disabeling the shared memory hsperf file will more or less affect the functionality of these tools as well.

#### Implementation details

As so often, the best (and only) documentation of the performance counters implemenatation details is in the [source code](https://github.com/openjdk/jdk8u-dev/blob/master/hotspot/src/share/vm/runtime/perfData.hpp#L69-L242) :). In summary, if `UsePerfData` is on, the JVM will reserve a chunk of `PerfDataMemorySize` (defaults to 32) kilobytes of memory for storing performance counters:

```
$ jcmd <pid> PerfCounter.print | -E 'sun.perfdata.(used|size)
sun.perfdata.size=32768
sun.perfdata.used=17984
```

If `PerfDisableSharedMem` is false, this will be shared memory backed by a file (i.e. `/tmp/hsperfdata_<username>/<pid>`). Otherwise, it will be ordinary, anonymous memory and the only way to access it will be with the help of the `-XX:+PerfDataSaveToFile` option after JVM shutdown. In that case, the counters will be written to `hsperfdata_<pid>` by default, but that can be configured with `-XX:PerfDataSaveFile`.

Each perfornmance data item has a name (e.g. `java.cls.loadedClasses`), a type (currently "long" or "byte array" aka "string"), a unit of measure (i.e. None, Byte, Ticks, Events, String or Hertz) and can be classified either as a Constant, a Variable or a Counter. Constant data items are set only once, at creation time (e.g. `sun.rt.javaCommand="HelloWorld"`), Variables can change their value arbitrarily (e.g. `sun.gc.metaspace.capacity=4587520`) while Counters are monotonically increasing or decreasing values (e.g. `sun.os.hrt.ticks=429365879599`).

Variables and Counters both can either be set explictely, when a certain event happens (e.g. after a GC, like `sun.gc.collector.0.invocations=0`) or they can be periodically sampled each `PerfDataSamplingInterval` (defaults to 50) miliseconds (e.g. `sun.gc.generation.0.space.0.used=5263880`).

### Accessing Jvmstat counters programatically

[sun.jvmstat.monitor](https://openjdk.org/groups/serviceability/jvmstat/sun/jvmstat/monitor/package-summary.html)

[hsperfdata](https://xin053.github.io/hsperfdata/)

[Introducing lazytime](https://lwn.net/Articles/621046/)
[noatime/relatime/lazytime](https://en.m.wikipedia.org/wiki/Stat_%28system_call%29#NOATIME)