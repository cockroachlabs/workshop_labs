# Troubleshooting Workshop - Student labs

This workshop walks through the process of troubleshooting a problematic cluster.

[Troubleshooting Documentation](https://www.cockroachlabs.com/docs/stable/troubleshooting-overview.html)

## Lab 0 - Understanding the Problem

The customer complains about high latency and spike in CPU usage for some nodes during their load test.
They ask for your help to lower latencies and improve CPU utilization to achieve higher throughput.

You ask the DBA to provide you with the required information to replicate the issue on your side:

- the cluster configuration: CPUs, MEM, Storage, Networking, location, CockroachDB version, etc.
- the data, in form of a database backup file.
- the workload run, in form of SQL queries.

The customer informs you the UAT environment runs on 3 nodes in 1 region
They are using CockroachDB v21.1.x on 4 vCPUs/16GB Mem instances with standard storage.

The customer sent you :

1. a sample of the data

    ```text
    # table credits ~7.5mio rows
    17,f5da34d7-6c8a-4c1c-af05-e09d41f9fca2,O,2223248,2020-12-10 02:05:14,A,2020-12-25 02:39:30
    21,496bffa4-57d9-4c00-a038-1677ab00384c,R,1966446,2020-12-22 00:22:05,A,2020-04-28 12:57:07
    19,d64858e1-f43e-4983-924d-68087e384995,R,180638,2020-12-20 16:58:00,A,2020-10-02 22:00:17
    ```

2. the schema:

    ```sql
    CREATE TABLE credits (
        id INT2 NOT NULL,
        code UUID NOT NULL,
        channel STRING(1) NOT NULL,
        pid INT4 NOT NULL,
        end_date DATE NOT NULL,
        status STRING(1) NOT NULL,
        start_date DATE NOT NULL,
        CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC),
        INDEX credits_pid_idx (pid ASC),
        INDEX credits_code_id_idx (code ASC, id ASC) STORING (channel, status, end_date, start_date),
        FAMILY "primary" (id, code, channel, pid, end_date, status, start_date)
    );

    CREATE TABLE offers (
        id INT4 NOT NULL,
        code UUID NOT NULL,
        token UUID NOT NULL,
        start_date DATE,
        end_date DATE,
        CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC, token ASC),
        INDEX offers_token_idx (token ASC),
        FAMILY "primary" (id, code, token, start_date, end_date)
    );
    ```

3. the SQL queries run as part of the load test

    ```sql
    -- Q1
    SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
    -- Q2
    SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
    ```

## Lab 1 - Recreate the customer environment

### Create the CockroachDB cluster and recreate the dataset

Create the CockroachDB cluster. You can use [roachprod](https://github.com/cockroachdb/cockroach/tree/master/pkg/cmd/roachprod) or your favorite DevOps tool.

We use [carota](https://pypi.org/project/carota/) to generate the random datasets. SSH into one of the servers

```bash
#create cluster and genearte import data
./start.sh
#create table and import data
./import_data.sh
#create jump box and check imported data
./create_jump.sh
```

You can monitor the import in the DB Console in the **Jobs** page

You should see below output after all scripts have been executed:

```text
  schema_name | table_name | type  | owner | estimated_row_count | locality
--------------+------------+-------+-------+---------------------+-----------
  public      | credits    | table | root  |             7500000 | NULL
  public      | offers     | table | root  |                   0 | NULL
(2 rows)
```

## Lab 2 - Analyse the CockroachDB cluster

Before running the workload, let's review the database we just imported, as well as analyze the SQL queries in the workload.

Open a new Terminal, the **SQL Terminal**, and connect to n1

```bash
roachprod sql ${USER}-labs:1
```

We've imported 2 tables, let's see what they look like in terms of size, columns, ranges, indexes. You can view these details using the AdminUI and/or with the `SHOW RANGES` command.

![databases](https://github.com/cockroachlabs/workshop_labs/blob/master/troubleshooting/media/databases.png)

```sql
SHOW RANGES FROM TABLE credits;
```

```text
                        start_key                       |                        end_key                        | range_id | range_size_mb | lease_holder |           lease_holder_locality           | replicas |                                                          replica_localities
--------------------------------------------------------+-------------------------------------------------------+----------+---------------+--------------+-------------------------------------------+----------+----------------------------------------------------------------------------------------------------------------------------------------
  NULL                                                  | /1/"\x00\x05\x16\x80\xf7\xcbL䣵w\x81\x1a\x1d\xd6\xf6" |       39 |      0.000728 |            2 | cloud=gce,region=us-east1,zone=us-east1-b | {1,2,3}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b"}
  /1/"\x00\x05\x16\x80\xf7\xcbL䣵w\x81\x1a\x1d\xd6\xf6" | /15/"\x15\xe6\x1c\x06VE@j\xbcQv\x83\x01O\fQ"          |       42 |    225.473018 |            1 | cloud=gce,region=us-east1,zone=us-east1-b | {1,2,3}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b"}
  /15/"\x15\xe6\x1c\x06VE@j\xbcQv\x83\x01O\fQ"          | NULL                                                  |       57 |    222.716523 |            2 | cloud=gce,region=us-east1,zone=us-east1-b | {1,2,3}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b"}
(3 rows)

```

```sql
SHOW CREATE TABLE offers;
SHOW RANGES FROM TABLE offers;
```

```text
  table_name |                          create_statement
-------------+----------------------------------------------------------------------
  offers     | CREATE TABLE public.offers (
             |     id INT4 NOT NULL,
             |     code UUID NOT NULL,
             |     token UUID NOT NULL,
             |     start_date DATE,
             |     end_date DATE,
             |     CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC, token ASC),
             |     INDEX offers_token_idx (token ASC),
             |     FAMILY "primary" (id, code, token)
             | )
(1 row)

Time: 1.909s total (execution 1.909s / network 0.000s)

  start_key | end_key | range_id | range_size_mb | lease_holder |           lease_holder_locality           | replicas |                                                          replica_localities
------------+---------+----------+---------------+--------------+-------------------------------------------+----------+----------------------------------------------------------------------------------------------------------------------------------------
  NULL      | NULL    |       38 |             0 |            2 | cloud=gce,region=us-east1,zone=us-east1-b | {1,2,3}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b"}
(1 row)

Time: 2.557s total (execution 2.557s / network 0.000s)
```

Notice how table `offers` has 1 secondary index, and the table is empty (`range_size_mb` is 0).

Now, let's inspect the workload that's run against this database. Here's a formatted view of the 2 queries in `workload.sql`.

Please note, `000000` and `c744250a-1377-4cdf-a1f4-5b85a4d29aaa` are just placeholders for real variables: the customer has not supplied those so we hardcoded them.

```sql
-- Q1
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date
FROM credits AS c
WHERE c.status = 'A'
  AND c.end_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '000000'

UNION

SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date
FROM credits AS c, offers AS o
WHERE c.id = o.id
  AND c.code = o.code
  AND c.status = 'A'
  AND c.end_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';

-- Q2
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date
FROM credits AS c, offers AS o
WHERE c.id = o.id
  AND c.code = o.code
  AND c.status = 'A'
  AND c.end_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

So Q2 is basically the second part of Q1, and it's a join query between the 2 tables. Q1 also has a `SELECT DISTINCT` part, too.

## Lab 3 - Simulate the load test

Run the workload simulation passing all URLs. We are running this workload with 48 active connections, which is exactly the limit for this cluster size. Calculation - 3 nodes \* 4 vCPUs \* 4 Active Connections per vCPU = 48 Active Connections. 

Create file `workload.sql` with the queries given by the customer

```sql
-- Q1
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
-- Q2
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

Then run the workload passing the file `workload.sql`.

```bash
./run_workload.sh
```

You should see the output similar to below:

```text
_elapsed___errors__ops/sec(inst)___ops/sec(cum)__p50(ms)__p95(ms)__p99(ms)_pMax(ms)
   21.0s        0         1965.5         1980.8    109.1    302.0    402.7    419.4  1: SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
   21.0s        0         2011.5         1970.6     92.3    268.4    302.0    402.7  2: SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
   22.0s        0         2005.0         1981.9    104.9    302.0    385.9    436.2  1: SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
   22.0s        0         2001.1         1972.0     92.3    251.7    352.3    385.9  2: SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

```bash
roachprod adminurl --open ${USER}-labs:1
```

While it runs, check the Metrics in the AdminUI. Open the **Hardware** dashboard to see if you can replicate the spike in high CPU usage.

Notice how 1 node have very high CPU usage compared to all other nodes. Take notice in the **Summary** of the values for QPS as well.

Check the latency for these 2 queries. Open the **Statements** page or review the scrolling stats in your terminal.

Check also **Service Latency** charts in the **SQL** dashboard for a better understanding.

Stop the workload now. You can definitely replicate the customer scenario: high CPU spikes and high latency.

## Lab 4 - Analyze the Queries

Switch to the SQL Terminal. We want to pull the query plan for each query

### Q1 Query Plan

Let's start with Q1, and let's break it down into 2 parts, and let's pull the plan for the 1st part. Again, here the value `000000` is a placeholder for a value passed by the application.

```sql
EXPLAIN (VERBOSE) SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date
FROM credits AS c
WHERE c.status = 'A'
  AND c.end_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '000000';
```

```text
                                               info
--------------------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • project
  │ columns: (id, code, channel, status, end_date, start_date)
  │ estimated row count: 0
  │
  └── • filter
      │ columns: (id, code, channel, pid, end_date, status, start_date)
      │ estimated row count: 0
      │ filter: ((status = 'A') AND (end_date >= '2020-11-20')) AND (start_date <= '2020-11-20')
      │
      └── • index join
          │ columns: (id, code, channel, pid, end_date, status, start_date)
          │ estimated row count: 0
          │ table: credits@primary
          │ key columns: id, code
          │
          └── • scan
                columns: (id, code, pid)
                estimated row count: 0 (<0.01% of the table; stats collected 28 minutes ago)
                table: credits@credits_pid_idx
                spans: /0-/1
(23 rows)
```

So the optimizer is leveraging index `credits@credits_pid_idx` to filter rows that have that specific `pid`, but then it has to do a join with `primary` to fetch `status`, `end_date` and `start_date` to finish the rest of the `WHERE`, and `SELECT`, clauses.

Wouldn't it be better if it didn't have to do this join and instead accessing just 1 index?

### Q2 Query Plan

Let's now pull the plan for Q2.

```sql
EXPLAIN (VERBOSE) SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date
FROM credits AS c, offers AS o
WHERE c.id = o.id
  AND c.code = o.code
  AND c.status = 'A'
  AND c.end_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

```text
                                                  info
--------------------------------------------------------------------------------------------------------
  distribution: full
  vectorized: true

  • project
  │ columns: (id, code, channel, status, end_date, start_date)
  │ estimated row count: 0
  │
  └── • lookup join (inner)
      │ columns: (id, code, token, id, code, channel, end_date, status, start_date)
      │ estimated row count: 0
      │ table: credits@credits_code_id_idx
      │ equality: (code, id) = (code,id)
      │ equality cols are key
      │ pred: ((status = 'A') AND (end_date >= '2020-11-20')) AND (start_date <= '2020-11-20')
      │
      └── • scan
            columns: (id, code, token)
            estimated row count: 1 (100% of the table; stats collected 34 minutes ago)
            table: offers@offers_token_idx
            spans: /"\xc7D%\n\x13wLߡ\xf4[\x85\xa4Қ\xaa"-/"\xc7D%\n\x13wLߡ\xf4[\x85\xa4Қ\xaa"/PrefixEnd
(20 rows)
```

Here we see that the optimizer is choosing an index to filter from the `offers` table and join with `credits`, which is fine.

## Lab 5 - Addressing the Hotspot

Let's tackle the high CPU usage issue first. Why is it so, why is a node, n1 in this case, using all the CPU?

We can try to isolate the issue by running only Q2 in our workload, and let's see if the problem persist.

Switch to the Jumpbox Terminal and edit file `workload.sql` to comment Q1 out, then restart the workload. Give it a couple of minutes, and you should see that n1 is hot again, so we know that Q2 is the culprit.

```bash
./run_no_q1_workload.sh
```

Let's see if we have a hot range.

Upload file `hot.py` to the jumpbox, or run it locally on a new terminal if you prefer

```bash
roachprod put ${USER}-labs:1 hot.py
roachprod ssh ${USER}-labs:1
$ python3 hot.py --numtop 10 --host ${USER}-labs-0001.roachprod.crdb.io --adminport 26258 --dbport 26257  
rank  rangeId	       QPS	     Nodes	 leaseHolder	DBname, TableName, IndexName
  1:       38	2024.012019	 [1, 3, 2]	           1	['defaultdb', 'offers', '']
  2:       40	402.711378	 [1, 3, 2]	           2	['defaultdb', 'credits', 'credits_pid_idx']
  3:        4	  4.281725	 [1, 3, 2]	           3	['', '', '']
  4:        6	  4.091285	 [1, 3, 2]	           3	['', '', '']
  5:       35	  1.523397	 [1, 3, 2]	           3	['system', 'sqlliveness', '']
  6:       11	  1.310508	 [1, 3, 2]	           3	['system', 'jobs', '']
  7:        3	  0.868352	 [1, 3, 2]	           3	['', '', '']
  8:        2	  0.678571	 [1, 3, 2]	           3	['', '', '']
  9:       26	  0.506625	 [1, 3, 2]	           3	['system', 'namespace2', '']
 10:       31	  0.301066	 [1, 3, 2]	           3	['system', 'statement_diagnostics_requests', '']
```

So it looks like rangeId 38 on n2 is hot. What's in that range, why that range?

Back to your SQL terminal, show the ranges for `offers@offers_token_idx`, since the query plan showed it's using this index

```sql
SHOW RANGES FROM INDEX offers@offers_token_idx;
```

```text
  start_key | end_key | range_id | range_size_mb | lease_holder |           lease_holder_locality           | replicas |                                                          replica_localities
------------+---------+----------+---------------+--------------+-------------------------------------------+----------+----------------------------------------------------------------------------------------------------------------------------------------
  NULL      | NULL    |       38 |             0 |            2 | cloud=gce,region=us-east1,zone=us-east1-b | {1,2,3}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-b"}
(1 row)
```

Bingo! We found rangeId 38.
As `offers` is empty, so is index `offers@offers_token_idx`, and thus there is just one range for that table and if you have a join operation going on, inevitably CockroachDB will always want to access that range to do the join, causing the hotspot.

We need to ask our customer:

- why is a join operation sent against an empty table;
- why is the table empty.

If the table were full, you'd have multiple ranges spread across the cluster and the load would be balanced, removing the hotspot on the node. Let's prove our theory.

The customer provides you with some sample data, below.

```text
16,fcbd04c3-4021-4ef7-8ca5-a5a19e4d6e3c,cd447e35-b8b6-48fe-842e-3d437204e52d,2021-08-28 16:28:06,2020-06-15 23:52:12
13,b4862b21-fb97-4435-8856-1712e8e5216a,1a2b8f1f-f1fd-42a2-9755-d4c13a902931,2020-09-30 06:04:12,2020-06-17 04:51:46
26,259f4329-e6f4-490b-9a16-4106cf6a659e,05b6e6e3-07d4-4edc-9143-1193e6c3f339,2021-09-16 21:42:15,2021-07-05 22:38:42
```

Stop the running workload, then, like for `credits`, generate the dataset and import it into `offers`.
On the host terminal, connect again to a cluster server

```bash
roachprod ssh ${USER}-labs:1

# once connected, create the dataset, 'offers'
# note: we use a seed here so that we can reporduce the same UUIDs used later
# by reusing the same seed, we ensure the field id and code match between the 2 tables
carota -r 10000 -t "int::start=1,end=28,seed=0; uuid::seed=0; uuid::seed=1; date; date" -o o.csv
# then we append some more random data
carota -r 2000000 -t "int::start=0,end=100,seed=5; uuid::seed=5; uuid::seed=6; date; date" -o o.csv --append

sudo mv o.csv /mnt/data1/cockroach/extern/
```

In your SQL terminal

```sql
IMPORT INTO offers CSV DATA ('nodelocal://1/o.csv');
```

You should now have 2 million rows in `offers`.

If you rerun the workload, however, you'd still see the spike because the `token` value to search is hardcoded to `c744250a-1377-4cdf-a1f4-5b85a4d29aaa`, so you'd still hit the same range over and over.

Instead, let's pick `token` values that are located at specific intervals in the KV store of the index, so we know we will hit different ranges.

```sql
SELECT token FROM offers@offers_token_idx LIMIT 1 OFFSET 1;
SELECT token FROM offers@offers_token_idx LIMIT 1 OFFSET 700000;
SELECT token FROM offers@offers_token_idx LIMIT 1 OFFSET 1400000;
```

We can use this data to create a new workload file, `q2.sql`. Scroll below text to the right to see the tokens.
Notice they are in lexicographical order.

```sql
-- scroll to the right!
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2021-11-20' AND c.start_date <= '2021-11-30' AND o.token = '00000276-014e-4ecc-9c99-0b59d80f1973';
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2021-11-20' AND c.start_date <= '2021-11-30' AND o.token = '591ee2d4-dc7c-4a54-bbc0-4c42ff12d809';
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2021-11-20' AND c.start_date <= '2021-11-30' AND o.token = 'b240d258-b3e9-4e67-b026-85041f58c8e3';
```

Run workload `q2.sql` for a while, at least 5 minutes to give time to Cockroach to reassign leaseholders around the ranges of the cluster.

```bash
./run_q2_workload.sh
```

Check the **Hardware** dashboard again

We still have problem with one of the nodes. Let's check which range is hot.

```bash
roachprod ssh ${USER}-labs:1
$ python3 hot.py --numtop 10 --host ${USER}-labs-0001.roachprod.crdb.io --adminport 26258 --dbport 26257  
rank  rangeId	       QPS	     Nodes	 leaseHolder	DBname, TableName, IndexName
  1:       54	1900.036883	 [1, 3, 2]	           3	['defaultdb', 'offers', 'offers_token_idx']
  2:       53	1826.161180	 [1, 3, 2]	           1	['defaultdb', 'offers', 'offers_token_idx']
  3:       51	1817.083473	 [1, 3, 2]	           1	['defaultdb', 'offers', 'offers_token_idx']
  4:       70	1547.721000	 [1, 3, 2]	           3	['defaultdb', 'credits', 'credits_code_id_idx']
  5:       67	1541.936345	 [1, 3, 2]	           2	['defaultdb', 'credits', 'credits_code_id_idx']
  6:       46	498.688315	 [1, 3, 2]	           2	['defaultdb', 'credits', 'credits_code_id_idx']
  7:        6	  4.056923	 [1, 3, 2]	           2	['', '', '']
  8:        4	  1.880647	 [1, 3, 2]	           2	['', '', '']
  9:       35	  1.519837	 [1, 3, 2]	           2	['system', 'sqlliveness', '']
 10:       11	  1.026539	 [1, 3, 2]	           2	['system', 'jobs', '']
```

Looks even enough. We just have too much throughput. Let's check to see if ranges are evenly distributed. 

```sql
SELECT lease_holder, lease_holder_locality FROM [SHOW RANGES FROM INDEX offers@offers_token_idx];
```

```text
  lease_holder |           lease_holder_locality
---------------+--------------------------------------------
             3 | cloud=gce,region=us-east1,zone=us-east1-b
             1 | cloud=gce,region=us-east1,zone=us-east1-b
             1 | cloud=gce,region=us-east1,zone=us-east1-b
             3 | cloud=gce,region=us-east1,zone=us-east1-b
             2 | cloud=gce,region=us-east1,zone=us-east1-b
(5 rows)
```

Looks good!

## Lab 6 - Addressing the Latency - Optimize the table primary and secondary indexes

Let's optimize the first part of Q1 by removing the need to join with `credits@primary`.
We need to create an index similar to `credits@credits_pid_idx` that stores the fields required by the query.
Also, index `credits@credits_code_id_idx` seems to be redundant, so we drop it.

```sql
DROP INDEX credits@credits_code_id_idx;
DROP INDEX credits@credits_pid_idx;
CREATE INDEX credits_pid_idx ON credits(pid ASC) STORING (channel, end_date, status, start_date);
```

Pull the query plan to confirm no join is required

```sql
EXPLAIN (VERBOSE) SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date
FROM credits AS c
WHERE c.status = 'A'
  AND c.end_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '12';
```

```text
                                               info
--------------------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • project
  │ columns: (id, code, channel, status, end_date, start_date)
  │ estimated row count: 0
  │
  └── • filter
      │ columns: (id, code, channel, pid, end_date, status, start_date)
      │ estimated row count: 0
      │ filter: ((status = 'A') AND (end_date >= '2020-11-20')) AND (start_date <= '2020-11-20')
      │
      └── • scan
            columns: (id, code, channel, pid, end_date, status, start_date)
            estimated row count: 0 (<0.01% of the table; stats collected 35 minutes ago)
            table: credits@credits_pid_idx
            spans: /12-/13
(17 rows)
```

Good stuff, we eliminated a join operation!

As per Q2, we see that the optimizer is never using `offers@primary`. Let's alter the primary key of that table to make it similar to index `offers@offers_token_idx`.

```sql
DROP INDEX offers_token_idx;
-- this will take some time as we're basically rewriting the entire table
BEGIN;
ALTER TABLE offers DROP CONSTRAINT "primary";
ALTER TABLE offers ADD CONSTRAINT "primary" PRIMARY KEY (token, id, code);
COMMIT;
```

Review the schema after these changes.

```sql
SHOW CREATE TABLE offers;
```

```text
  table_name |                          create_statement
-------------+----------------------------------------------------------------------
  offers     | CREATE TABLE public.offers (
             |     id INT4 NOT NULL,
             |     code UUID NOT NULL,
             |     token UUID NOT NULL,
             |     start_date DATE NULL,
             |     end_date DATE NULL,
             |     CONSTRAINT "primary" PRIMARY KEY (token ASC, id ASC, code ASC),
             |     FAMILY "primary" (id, code, token, start_date, end_date)
             | )
(1 row)
```

### Run final test
Mind, the workload still has the hardcoded values. Review and create file `final.sql` which should be closer to the real workflow, with real `offers.token` and `credits.id|code` values

```sql
-- final.sql
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3132039537') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '9530fef8-ced9-47a7-bed3-53bf1eb5e1fe')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'd554a4cf-6c83-454e-83f4-38f019cf4734';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '1279') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'd0b3bbd2-e69c-4484-b4c3-50ce0d68a9e3')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '7ffb8711-669f-4ca2-bf22-af047bd188be';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2743109489') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '59787eba-7709-4f0f-9fb3-7532180e5e38')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '3baa519e-c21d-47ae-99c3-a25c649ebaa2';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3002738477') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'b2f3e754-2b50-490d-944d-c41fb73c90c4')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '59787eba-7709-4f0f-9fb3-7532180e5e38';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2189670715') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '00000276-014e-4ecc-9c99-0b59d80f1973')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '77516bf5-af2c-4042-8917-4d5b408908ed';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2737195593') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '7ffb8711-669f-4ca2-bf22-af047bd188be')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'ee8452d1-858e-4f27-b77a-f3c81d764b6a';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2936320808') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '77516bf5-af2c-4042-8917-4d5b408908ed')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '1dd9dbb7-ac42-43d0-ab04-a37ddc7536cc';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2579495379') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'ee8452d1-858e-4f27-b77a-f3c81d764b6a')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'b2f3e754-2b50-490d-944d-c41fb73c90c4';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3050862498') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '1dd9dbb7-ac42-43d0-ab04-a37ddc7536cc')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '00000276-014e-4ecc-9c99-0b59d80f1973';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3050862498') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'd554a4cf-6c83-454e-83f4-38f019cf4734')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '9530fef8-ced9-47a7-bed3-53bf1eb5e1fe';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c WHERE (((c.status = 'A') AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3050862498') UNION SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.end_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '3baa519e-c21d-47ae-99c3-a25c649ebaa2')
SELECT c.id, c.code, c.channel, c.status, c.end_date, c.start_date FROM credits AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.end_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'd0b3bbd2-e69c-4484-b4c3-50ce0d68a9e3';
```

```text
rank  rangeId	       QPS	     Nodes	 leaseHolder	DBname, TableName, IndexName
  1:       65	1679.604965	 [1, 3, 2]	           3	['defaultdb', 'offers', '']
  2:       63	1679.415212	 [1, 3, 2]	           3	['defaultdb', 'offers', '']
  3:       42	422.603694	 [1, 3, 2]	           2	['defaultdb', 'credits', '']
  4:       62	422.482290	 [1, 3, 2]	           2	['defaultdb', 'offers', '']
  5:       73	375.020176	 [1, 3, 2]	           1	['defaultdb', 'credits', 'credits_pid_idx']
  6:       57	322.823851	 [1, 3, 2]	           1	['defaultdb', 'credits', '']
  7:       64	242.086966	 [1, 3, 2]	           1	['defaultdb', 'offers', '']
  8:       72	211.325086	 [1, 3, 2]	           2	['defaultdb', 'credits', 'credits_pid_idx']
  9:        6	  4.192709	 [1, 3, 2]	           2	['', '', '']
 10:        4	  3.082733	 [1, 3, 2]	           1	['', '', '']
```

Compare to the initial result: huge improvement in performance! We doubled the QPS and halved the Lantency!

![final](https://github.com/cockroachlabs/workshop_labs/blob/master/troubleshooting/media/final.png)

Congratulations, you reached the end of the Troubleshooting workshop! We hope you have now a better understanding on the process of troubleshoot an underperforming cluster.

