# CockroachDB Logging

## Overview

CockroachDB [logs](https://www.cockroachlabs.com/docs/stable/logging-overview.html) include details about notable cluster, node, and range-level events.

Each log message is composed of a **payload** and an envelope that contains **event metadata** (e.g., severity, date, timestamp, channel).

Certain [notable events](https://www.cockroachlabs.com/docs/v21.1/eventlog.html)s are reported using a structured format.
Commonly, these notable events are also copied to the table `system.eventlog`.

Log messages are organized into appropriate **logging channels** and then routed through **log sinks**.

Each sink further **processes and filters** the messages before emitting them to destinations outside CockroachDB.

The mapping of channels to sinks, as well as the processing and filtering done by each sink, is [configurable](https://www.cockroachlabs.com/docs/stable/configure-logs.html).

### Channels

Below the list of all [channels](https://www.cockroachlabs.com/docs/v21.1/logging#logging-channels).

| Channel | Description |
|---------|-------------|
| DEV | Uncategorized and debug messages. |
| OPS | Process starts, stops, shutdowns, and crashes (if they can be logged); changes to cluster topology, such as node additions, removals, and decommissions.|
| HEALTH | Resource usage; node-node connection events, including connection errors; up- and down-replication and range unavailability.|
| STORAGE | Low-level storage logs |
| SESSIONS | Client connections and disconnections; SQL authentication logins/attempts and session/query terminations.|
| SQL_SCHEMA | Database, schema, table, sequence, view, and type creation; changes to table columns and sequence parameters.|
| USER_ADMIN | Changes to users, roles, and authentication credentials.|
| PRIVILEGES | Changes to privileges and object ownership.|
| SENSITIVE_ACCESS | SQL audit events.|
| SQL_EXEC | SQL statement executions and uncaught Go panic errors during SQL statement execution.|
| SQL_PERF | SQL executions that impact performance, such as slow queries.|

### Sinks

Channels output messages to sinks.
There are 3 types of sinks available:

- Log files
- Fluentd-compatible servers (Splunk)
- `stderr`

Each sink can be configured with **parameters**

| Parameter | Description |
|---------|-------------|
| `filter` | Minimum severity log [level](https://www.cockroachlabs.com/docs/v21.1/logging#logging-levels-severities) |
| `format` | Log message [format](https://www.cockroachlabs.com/docs/v21.1/log-formats.html)  |
| `redact` | When true, enables automatic redaction of personally identifiable information (PII) from log messages. This ensures that sensitive data is not transmitted when collecting logs centrally or over a network. For details, see Redact logs. |
| `redactable` | When true, preserves redaction markers around fields that are considered sensitive in the log messages. The markers are recognized by cockroach debug zip and cockroach debug merge-logs but may not be compatible with external log collectors. For details on how the markers appear in each format, see Log formats. |
| `exit-on-error` | When true, stops the Cockroach node if an error is encountered while writing to the sink. We recommend enabling this option on file sinks in order to avoid losing any log entries. When set to false, this can be used to mark certain sinks (such as stderr) as non-critical. |
| `auditable` | If true, enables exit-on-error on the sink. Also disables buffered-writes if the sink is under file-groups. This guarantees non-repudiability for any logs in the sink, but can incur a performance overhead and higher disk IOPS consumption. This setting is typically enabled for security-related logs. |

## Setup

Create file `logs.yaml` to store your logging configuration.
Read through it:

- we are only using files as sinks (not fluentd/Splunk)
- we use the JSON format
- the most used channels are mapped to file `cockroach.log`
- each other channel is mapped to a channel that bears its name, eg `cockroach-storage.log` for channel `storage`
- every sink inherits the default parameters

```yaml
file-defaults:
  max-file-size: 10MiB
  max-group-size: 100MiB
  buffered-writes: true
  filter: INFO
  format: json
  redact: false
  redactable: true
  exit-on-error: true
  auditable: false
fluent-defaults:
  filter: INFO
  # format: json-fluent # default
  redact: false
  redactable: true
  exit-on-error: false
  auditable: false
sinks:
  # fluent-servers:
  #  myhost:
  #    channels: [DEV, OPS, HEALTH]
  #    address: 127.0.0.1:5170
  #    net: tcp
  file-groups:
    default:
      channels: [DEV, OPS, HEALTH, SQL_SCHEMA, USER_ADMIN, PRIVILEGES]
    storage:
      channels: [STORAGE]
    sensitive-access:
      channels: [SENSITIVE_ACCESS]
    sessions:
      channels: [SESSIONS]
    sql-exec:
      channels: [SQL_EXEC]
    sql-perf:
      channels: [SQL_PERF]
    sql-internal-perf:
      channels: [SQL_INTERNAL_PERF]
  stderr:
    channels: all
    filter: NONE
    format: json
    redact: false
    redactable: true
    exit-on-error: true
capture-stray-errors:
  enable: true
  max-group-size: 100MiB
```

Download and install the [CockroachDB binary](https://www.cockroachlabs.com/docs/stable/install-cockroachdb.html).
Then, start a secure database instance

```bash
# From https://www.cockroachlabs.com/docs/v21.1/secure-a-cluster#step-1-generate-certificates
mkdir certs my-safe-directory
cockroach cert create-ca --certs-dir=certs --ca-key=my-safe-directory/ca.key
cockroach cert create-node localhost $(hostname) --certs-dir=certs --ca-key=my-safe-directory/ca.key

# start a secure single node cluster
cockroach start-single-node --certs-dir=certs --background --log-config-file=logs.yaml

# log into the cluster as root
cockroach sql --certs-dir=certs
```

### File output

Good, now open a new Terminal window to inspect the files that were created

```bash
$ cd cockroach-data/logs
$ ls -l
total 552
lrwxr-x---   1 fabio  staff      58 Oct 27 15:13 cockroach-stderr.log -> cockroach-stderr.mac.fabio.2021-10-27T19_13_01Z.011252.log
-rw-r-----   1 fabio  staff     910 Oct 27 15:13 cockroach-stderr.mac.fabio.2021-10-27T19_13_01Z.011252.log
lrwxr-x---   1 fabio  staff      59 Oct 27 15:13 cockroach-storage.log -> cockroach-storage.mac.fabio.2021-10-27T19_13_01Z.011252.log
-rw-r-----   1 fabio  staff   10793 Oct 27 15:44 cockroach-storage.mac.fabio.2021-10-27T19_13_01Z.011252.log
lrwxr-x---   1 fabio  staff      51 Oct 27 15:13 cockroach.log -> cockroach.mac.fabio.2021-10-27T19_13_01Z.011252.log
-rw-r-----   1 fabio  staff  236291 Oct 27 16:02 cockroach.mac.fabio.2021-10-27T19_13_01Z.011252.log

# display last line of cockroach.log
$ tail -n1 cockroach.log
{"channel_numeric":2,"channel":"HEALTH","timestamp":"1635365292.961975000","cluster_id":"a9dc27ba-af51-4c8c-b165-69a937b48eb9","node_id":1,"severity_numeric":1,"severity":"INFO","goroutine":20,"file":"server/status/runtime.go","line":569,"entry_counter":478,"redactable":1,"tags":{"n":"1"},"message":"runtime stats: 178 MiB RSS, 274 goroutines (stacks: 3.7 MiB), 47 MiB/85 MiB Go alloc/total (heap fragmentation: 7.2 MiB, heap reserved: 13 MiB, heap released: 58 MiB), 71 MiB/78 MiB CGO alloc/total (0.6 CGO/sec), 1.4/1.1 %(u/s)time, 0.0 %gc (0x), 24 KiB/22 KiB (r/w)net"}
```

As expected, we see file `cockroach.log`, `cockroach-storage.log` and `cockroach-stderr.log`.
The format is JSON, as configured.

But where are the other log files? We're missing those related to sessions, audit, sql-exec...
Some logging channels needs to be enabled by means of [Cluster Settings](https://www.cockroachlabs.com/docs/v21.1/cluster-settings).

For example, channel `SESSIONS` is enabled by these 2 cluster settings, set to `False` by default:

- `server.auth_log.sql_connections.enabled` --> if set, log SQL client connect and disconnect events
- `server.auth_log.sql_sessions.enabled`    --> if set, log SQL session login/disconnection events

Check the [Logging Channels](https://www.cockroachlabs.com/docs/v21.1/logging-overview.html#logging-channels) for more information on which cluster settings you need to enable.

Now, let's change a simple setting in `logs.yaml` to test how logs look like.
In this exercise, we change the log format from `json` to `crdb-v2`, which is more humanly readable.

```bash
# stop the cluster
$ cockroach quit --certs-dir=certs

# on my macbook, sed is aliased to gsed (GNU sed)
$ sed -i 's/json/crdb-v2/g' logs.yaml

# restart the cluster
$ cockroach start-single-node --certs-dir=certs --background --log-config-file=logs.yaml 

# check again the last line of cockroach.log
$ tail -n1 cockroach.log
I211027 20:20:40.838139 447 sql/sqlliveness/slinstance/slinstance.go:144 ⋮ [n1] 52  created new SQL liveness session ‹ef0fdfe18b014b42a809f36257c3818b›
```

As expected, we see the new format.

Let's do one more exercise.
At the **SQL prompt**, enable the `SQL_EXEC` channel

```sql
SET CLUSTER SETTING sql.trace.log_statement_execute = True;
```

and immediately you will see these new files

```bash
$ ls -l 
total 904
lrwxr-x---   1 fabio  staff    60B Oct 27 16:31 cockroach-sql-exec.log@ -> cockroach-sql-exec.mac.fabio.2021-10-27T20_31_16Z.013087.log
-rw-r-----   1 fabio  staff   3.5K Oct 27 16:31 cockroach-sql-exec.mac.fabio.2021-10-27T20_31_16Z.013087.log
[...]

$ tail -n1 cockroach-sql-exec.log
I211027 20:34:11.553235 10838 9@util/log/event_log.go:32 ⋮ [intExec=‹cancel/pause-requested›] 95 ={"Timestamp":1635366851551571000,"EventType":"query_execute","Statement":"‹UPDATE \"\".system.jobs SET status = CASE WHEN status = $1 THEN $2 WHEN status = $3 THEN $4 ELSE status END WHERE (status IN ($1, $3)) AND ((claim_session_id = $5) AND (claim_instance_id = $6)) RETURNING id, status›","Tag":"UPDATE","User":"node","ApplicationName":"$ internal-cancel/pause-requested","PlaceholderValues":["‹'pause-requested'›","‹'paused'›","‹'cancel-requested'›","‹'reverting'›","‹'\\xef0fdfe18b014b42a809f36257c3818b'›","‹1›"],"ExecMode":"exec-internal","Age":1.631}
```

Very good! Now you have a simple setup to test how logging works.

### Fluentd output

You can also hook up [Fluentd](https://www.fluentd.org/) to test how logging is handled over a network.

Create a file `fluent.conf` in your home directory

```bash
##########
# Inputs #
##########

# this source reads files in a directory
# <source>
#   @type tail
#   path "/var/log/*.log"
#   read_from_head true
#   tag gino
#   <parse>
#     @type json
#     time_type string
#     time_format "%Y-%m-%d %H:%M:%S.%N"
#     # time_type float
#     time_key timestamp
#   </parse>
# </source>

# this source listens on a network port
<source>
  @type tcp
  tag CRDB
  <parse>
    @type json
    time_type float
    time_key timestamp
  </parse>
  port 5170
  bind 0.0.0.0
  delimiter "\n"
</source>

###########
# Outputs #
###########

# output to file buffer
<match **>
  @type file
  path /output/
  append true
  <buffer>
    timekey 1d
    timekey_use_utc true
    timekey_wait 1m
  </buffer>
  <format>
    @type out_file
    delimiter ","
    time_format "%Y-%m-%d %H:%M:%S.%N"
  </format>
</match>
```

Then, start the server using Docker

```bash
cd ~
mkdir output

# make sure you map the path accordingly
docker run -ti --rm -v /Users/fabio/fluent.conf:/fluentd/etc/fluent.conf -v /Users/fabio/output:/output -p=5170:5170 fluent/fluentd
```

If fluent start successfully, you should see this output on stdout:

```text
2021-11-01 16:56:24 +0000 [info]: parsing config file is succeeded path="/fluentd/etc/fluent.conf"
2021-11-01 16:56:24 +0000 [info]: using configuration file: <ROOT>
[...]
2021-11-01 16:56:24 +0000 [info]: adding source type="tcp"
2021-11-01 16:56:24 +0000 [info]: #0 starting fluentd worker pid=17 ppid=7 worker=0
2021-11-01 16:56:24 +0000 [info]: #0 fluentd worker is now running worker=0
```

Ok, fluent started successfully and it's listening for incoming messages.

Now, stop CockroachDB

```bash
cockroach quit --certs-dir=certs
```

Uncomment this section in the `logs.yaml` file

```yaml
  fluent-servers:
    myhost:
      channels: [DEV, OPS, HEALTH]
      address: 127.0.0.1:5170
      net: tcp
```

Restart CockroachDB

```bash
cockroach start-single-node --certs-dir=certs --background --log-config-file=logs.yaml
```

Check directory `output` and tail the file

```bash
$ tail -n1 output/buffer.*.log
2021-11-01 17:03:09.353577800   CRDB    {"tag":"cockroach.health","c":2,"t":"1635786189.332476000","x":"92c25c70-6e91-41f6-9480-6b2de3cb729a","N":1,"s":1,"sev":"I","g":325,"f":"server/status/runtime.go","l":569,"n":73,"r":1,"tags":{"n":"1"},"message":"runtime stats: 101 MiB RSS, 271 goroutines (stacks: 3.5 MiB), 27 MiB/58 MiB Go alloc/total (heap fragmentation: 7.4 MiB, heap reserved: 8.9 MiB, heap released: 17 MiB), 3.8 MiB/7.0 MiB CGO alloc/total (0.0 CGO/sec), 0.0/0.0 %(u/s)time, 0.0 %gc (0x), 79 KiB/180 KiB (r/w)net"}
```

Good stuff, you successfully integrated Fluentd with CockroachDB logging framework!

## Reference

- [Logging Overview](https://www.cockroachlabs.com/docs/stable/logging-overview.html)
- [Configure Logs](https://www.cockroachlabs.com/docs/stable/configure-logs.html)
- [Logging Use Cases](https://www.cockroachlabs.com/docs/stable/logging-use-cases.html)
- [Log Formats](https://www.cockroachlabs.com/docs/v21.1/log-formats.html)
- [Notable Event Types](https://www.cockroachlabs.com/docs/v21.1/eventlog.html)
- [Cluster Settings](https://www.cockroachlabs.com/docs/v21.1/cluster-settings)
- [Fluentd Docs](https://docs.fluentd.org/)
