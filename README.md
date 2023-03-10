# Performance implications of `-XX:+/-PerfDisableSharedMem`

*-This repo based on [Evan Jones](https://www.evanjones.ca/) original [mmap-pause](https://github.com/evanj/mmap-pause) project. See [README_orig.md](README_orig.md) for the original README file.-*

The goal of this project is to investigate the overhead and latency introduced by the [HotSpot Jvmstat Performance Counters](https://openjdk.org/groups/hotspot/docs/Serviceability.html#bjvmstat) feature which by default writes metrics (i.e. so called "*performance counters*") periodically to a memory mapped file.

## Jvmstat Performance Counters

By default the HotSpot JVM exports a set of performance counters for monitoring various internal subsystems of the JVM. The intention is that updating these counters incurs in zero overhead such that they can be always on. The [jstat](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jstat.html) tool can be used to monitor some of these counters. The full set of counters can be queried with `jcmd <pid> PerfCounter.print` or accessed programmatically (see [Accessing Jvmstat counters programmatically](#accessing-jvmstat-counters-programmatically)).

### Implementation

The Jvmstat performance counters feature is controlled by the `-XX:+/-UsePerfData` command line flag which is on by default. A second flag, `-XX:+/-PerfDisableSharedMem` controls wether the perf data will be exported via a memory mapped file. The flag is off by default meaning that the perf counters will be made available in a memory mapped file with the name `/tmp/hsperfdata_<username>/<pid>` (see [JDK-6938627](https://bugs.openjdk.org/browse/JDK-6938627) and [JDK-7009828](https://bugs.openjdk.org/browse/JDK-7009828)) for why this location can't be changed). This file is also used by other tools like [`jps`](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jps.html), [`jcmd`](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jcmd.html) or [jconsole](https://docs.oracle.com/javase/8/docs/technotes/tools/unix/jconsole.html) to discover running JVMS so disabling the shared memory hsperf file will more or less affect the functionality of these tools as well.

#### Implementation details

As so often, the best (and only) documentation of the performance counters implementation details is in the [source code](https://github.com/openjdk/jdk8u-dev/blob/master/hotspot/src/share/vm/runtime/perfData.hpp#L69-L242) :). In summary, if `UsePerfData` is on, the JVM will reserve a chunk of `PerfDataMemorySize` (defaults to 32) kilobytes of memory for storing performance counters:

```
$ jcmd <pid> PerfCounter.print | -E 'sun.perfdata.(used|size)
sun.perfdata.size=32768
sun.perfdata.used=17984
```

If `PerfDisableSharedMem` is false, this will be shared memory backed by a file (i.e. `/tmp/hsperfdata_<username>/<pid>`). Otherwise, it will be ordinary, anonymous memory and the only way to access it will be with the help of the `-XX:+PerfDataSaveToFile` option after JVM shutdown. In that case, the counters will be written to `hsperfdata_<pid>` by default, but that can be configured with `-XX:PerfDataSaveFile`.

Each performance data item has a name (e.g. `java.cls.loadedClasses`), a type (currently "long" or "byte array" aka "string"), a unit of measure (i.e. None, Byte, Ticks, Events, String or Hertz) and can be classified either as a Constant, a Variable or a Counter. Constant data items are set only once, at creation time (e.g. `sun.rt.javaCommand="HelloWorld"`), Variables can change their value arbitrarily (e.g. `sun.gc.metaspace.capacity=4587520`) while Counters are monotonically increasing or decreasing values (e.g. `sun.os.hrt.ticks=429365879599`).

Variables and Counters both can either be set explicitly, when a certain event happens (e.g. after a GC, like `sun.gc.collector.0.invocations=0`) or they can be periodically sampled each `PerfDataSamplingInterval` (defaults to 50) milliseconds (e.g. `sun.gc.generation.0.space.0.used=5263880`).

### Accessing Jvmstat counters programmatically

The Jvmstat counters of a VM (including the VM we'Re running in) can be accessed with the help of the [sun.jvmstat.monitor](https://openjdk.org/groups/serviceability/jvmstat/overview-summary.html) API. A trivial program which prints all counters with their current values looks as follows:

```java
// On JDK <= 8: javac -classpath JAVA_HOME/lib/tools.jar HSperf.java
// On JDK >= 9: javac --add-exports=jdk.internal.jvmstat/sun.jvmstat.monitor=ALL-UNNAMED HSperf.java

import java.lang.management.ManagementFactory;
import java.util.List;

import sun.jvmstat.monitor.Monitor;
import sun.jvmstat.monitor.MonitoredHost;
import sun.jvmstat.monitor.MonitoredVm;
import sun.jvmstat.monitor.VmIdentifier;

public class HSperf {
  public static void main(String[] args) throws Exception {
    String pid = (args.length == 0) ? // self ?
      ManagementFactory.getRuntimeMXBean().getName().split("@")[0] : args[0];
    MonitoredHost host = MonitoredHost.getMonitoredHost((String) null);
    MonitoredVm vm = host.getMonitoredVm(new VmIdentifier(pid));
    List<Monitor> perfCounters = vm.findByPattern(".*");
    for (Monitor m : perfCounters) {
      System.out.println(m.getName() + "=" + m.getValue());
    }
  }
}
```

### Pros and cons of Jvmstat performance counters

The biggest advantage of the Jvmstat performance counters is that they are switched on by default, incur in a very low overhead and that they can be easily collected. In particular, it is possible to collect the counters without the need to start another Java process by simply reading from the memory mapped hsperf data file. E.g. there exists a [Go library](https://xin053.github.io/hsperfdata/) for parsing the hsperf data file and it would be trivial write a similar program in plain C or any other programming language.

On the downside, Jvmstat counters are not part of the Java SE specification and have been added quite some time ago [with JDK 1.5](https://docs.oracle.com/javase/1.5.0/docs/tooldocs/share/jstat.html). The initial implementation hasn't been enhanced a lot ever since and support for e.g. new garbage collectors like Shenandoah or ZGC is weak. Some counters like for example heap usage is trivial and cheap to implement for generational collectors like Serial or ParallelGC but much more expensive for region based collectors with thousands of regions. Also, some code like for example [`PerfLongVariant::sample()`](https://github.com/openjdk/jdk/blob/75d630621c86840eed9b29bf6e4c5e22e82369f0/src/hotspot/share/runtime/perfData.cpp#L210-L214) is still incomplete (i.e. in this example sampling for long counters without sample helper is missing).

Finally, after [Evan Jones](https://www.evanjones.ca/) has posted his blogs "[The Four Month Bug: JVM statistics cause garbage collection pauses](https://www.evanjones.ca/jvm-mmap-pause.html)" and "[Finding the Four Month Bug: A debugging story](https://www.evanjones.ca/jvm-mmap-pause-finding.html)" almost exactly eight years ago, many services started to disable hsperf's shared memory file (i.e. `-XX:+PerfDisableSharedMem`). The following section will investigate if the original results published by Evan are still valid today.

## Measuring perfromance implications of Jvmstat Performance Counters

Measuring tail latency of a service is not trivial and a multidimensional problem which depends on many factors like JDK version, GC, OS, kernel version, filesystem, number of CPUs, amount of memory, type of storage, etc. The following investigation will mainly focus on the effect of the JDK and the Linux kernel version on systems with classical hard disc drives or more modern solid state disks.

### Setup

I've forked Evan's original test case and only slightly modified the [`diskload.sh`](./diskload.sh) script which generates disk I/O load to additionally purge the generated files from the file cache and sync them to disk after each round of copy operations.

On the Java side I use the [jHiccup agent](https://github.com/giltene/jHiccup) in addition to the GC logs to measure the latency distribution of the test program. I've tested with OpenJDK 8, 17 and a development version of JDK 20 using the following command line arguments:
```
jdk8   : -javaagent:jHiccup.jar="-l /dev/shm/tmp/jHiccup.log" -Xmx1G -Xms1G -XX:+PrintGCDetails -XX:+PrintGC -XX:+PrintGCDateStamps -XX:+PrintGCApplicationStoppedTime MakeGarbage 240 > /dev/shm/tmp/gc.log
jdk17+ : -javaagent:jHiccup.jar="-l /dev/shm/tmp/jHiccup.log" -Xmx1G -Xms1G -Xlog:gc -Xlog:safepoint MakeGarbage 240 > /dev/shm/tmp/gc.log
```
I also used jHiccpus capability to [generate histograms from GC log files](https://github.com/giltene/jHiccup#using-jhiccup-to-process-pause-logs-from-eg-gc-log-files) (see [`jdk8log2hlog.sh`](./jdk8log2hlog.sh)). It turns out that the latency histograms generated by jHiccup are very similar to the distribution of safepoint pauses generated from the GC log files, so I'll mostly show the jHiccup graphs (see [Generating latency histograms from GC logs](#generating-latency-histograms-from-gc-logs) for more details).

All the logs are written to the tempfs file system mounted to `/dev/shm` to minimize the effects of log writing on the results. The final latency graphs from the jHiccup histograms are plotted with [HistogramLogAnalyzer](https://github.com/HdrHistogram/HistogramLogAnalyzer).

Regarding the test hardware, I use AWS EC2 [c4.4xlarge](https://instances.vantage.sh/aws/ec2/c4.4xlarge) instances with 80gb of [EBS storage](https://aws.amazon.com/ebs/) on either a HDD (i.e. "[standard](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html#vol-type-prev)") or a SDD (i.e. "[gp2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html#vol-type-ssd)"). On these instances I run Amazon Linux 2012 with a 3.2 kernel and ext4 file system, AL 2018 with a 4.14 kernel and xfs file system and AL 2023 with a 5.10 kernel and xfs file system respectively.

### Running the tests

A c4.4xlarge instance has 16 vCPUs and 30gb of memory. For each experiment I ran 4 JVMs in parallel for four hours with the above option plus one of `-XX:-UsePerfData`, `-XX:+PerfDisableSharedMem`, `-XX:-PerfDisableSharedMem` (the default), and `-XX:+PerfAsyncSharedMem`. The last option (`PerfAsyncSharedMem`) is a quick POC for evaluating the impact of asynchronously writing out the hsperf data counters to shared memory from an independent thread. With `-XX:+PerfAsyncSharedMem` the JVM will allocate both, traditional as well as shared memory for the Jvmstat counters. However, at runtime the counters will always be updated in the anonymous memory (like with `-XX:+PerfDisableSharedMem`) and only be written out periodically to shared memory (currently every `PerfDataSamplingInterval` ms) from an independent thread (see the code for [JDK 8](https://github.com/simonis/jdk8u-dev/tree/PerfAsyncSharedMem), [JDK 17](https://github.com/simonis/jdk17u-dev/tree/PerfAsyncSharedMem) and [JDK tip](https://github.com/simonis/jdk/tree/PerfAsyncSharedMem)).

In parallel I ran `./diskload.sh` with four parallel processes to generate I/O load on the disks and `LINES=20 top -b -d 10 > /dev/shm/tmp/top.log` for a general overview of the system. The typical `top` output during the runs looks as follows (indicating that there are more than enough CPU and memory resources for the Java processes):
```
top - 20:09:40 up  5:47,  6 users,  load average: 7.94, 4.58, 2.47
Tasks: 143 total,   1 running, 142 sleeping,   0 stopped,   0 zombie
Cpu(s): 26.5%us,  1.3%sy,  0.0%ni, 63.4%id,  8.6%wa,  0.0%hi,  0.0%si,  0.1%st
Mem:  30888044k total,  9007676k used, 21880368k free,    48844k buffers
Swap:        0k total,        0k used,        0k free,  7055964k cached

  PID USER      PR  NI  VIRT  RES  SHR S %CPU %MEM    TIME+  COMMAND
25035 ec2-user  20   0 4745m 378m  11m S 112.4  1.3   1:49.76 java
25105 ec2-user  20   0 4747m 378m  11m S 108.7  1.3   1:45.16 java
25141 ec2-user  20   0 4745m 379m  11m S 108.6  1.3   1:45.56 java
25070 ec2-user  20   0 4745m 379m  11m S 108.4  1.3   1:47.49 java
25194 ec2-user  20   0  106m 1664  580 D  5.3  0.0   0:01.18 dd
25192 ec2-user  20   0  106m 1668  580 D  5.2  0.0   0:01.18 dd
25195 ec2-user  20   0  106m 1668  580 D  5.2  0.0   0:01.17 dd
25193 ec2-user  20   0  106m 1668  580 D  5.1  0.0   0:01.16 dd
```

### Results

#### Amazon Linux 2012 / kernel 3.2 / HDD

We'll start with JDK 8 on Amazon Linux 2012. The first two graphs show the results of the two VM running with `-XX:-UsePerfData` and `-XX:+PerfDisableSharedMem`.

| ![](results_al2012_c4/java8x4-no-perf_c4_2.png) |
|-------|
| ![](results_al2012_c4/java8x4-no-mmap_c4_2.png) |

As you can see, the results are almost identical. This gives us conclusive evidence that merely collecting the counters without writing them to a shared memory file (i.e. `-XX:+PerfDisableSharedMem`) doesn't generate any latency overhead compared to disabling hsperf counters altogether (i.e. `-XX:-UsePerfData`).

The next two graphs are from the JVMs which ran at the same time but with default settings (i.e. `-XX:-PerfDisableSharedMem`) and with the new `-XX:+PerfAsyncSharedMem` respectively.

| ![](results_al2012_c4/java8x4-async-off_c4_2.png) |
|-------|
| ![](results_al2012_c4/java8x4-async-on_c4_2.png) |

With the default settings we can clearly see that the maximum latency increases up to more than 4000 ms. Unfortunately, writing the Jvmstat memory region asynchronously to the memory mapped file, doesn't really help a lot. While it decreases the peak pause times to ~2500 ms, the P99.9% (1200 ms) is still way above the P99.9% (3.7 ms) without the memory mapped file. The reason why asynchronously writing the hsperf data doesn't really help is currently unclear to me and requires more investigation.

Next we'll present the results of running the same experiment with JDK 17 (with `-XX:+UseParallelGC`) instead of JDK 8.

#### Amazon Linux 2018 / kernel 4.14 / HDD

TBD

#### Amazon Linux 2023 / kernel 5.10 / HDD

TBD
#### Generating latency histograms from GC logs

TBD
## Outlook

There are still a lot of dimensions to this problem worth exploring:
- Test with different GCs
- Test on various file systems
- Test with different storage systems
- Test with hsperf data file in tempfs
- Test with different mount options (e.g. [noatime/relatime/lazytime](https://en.m.wikipedia.org/wiki/Stat_%28system_call%29#NOATIME), aso see "[Introducing lazytime](https://lwn.net/Articles/621046/)")
