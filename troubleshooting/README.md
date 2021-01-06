# Troubleshooting Workshop - Student labs

This workshop walks through the process of troubleshooting a problematic cluster.

## Lab 0 - Understanding the Problem

The customer complains about high latency and spike in CPU usage for some nodes during their load test.
They ask for your help to lower latencies and improve CPU utilization to achieve higher throughput.

You ask the DBA to provide you with the required information to replicate the issue on your side:

- the cluster configuration: CPUs, MEM, Storage, Networking, location, CockroachDB version, etc.
- the data, in form of a database backup file.
- the workload run, in form of SQL queries.

The customer informs you the UAT environment runs on 12 nodes across 4 datacenters in 2 regions, US East and US West.
They are using CockroachDB v20.2.x on 4 vCPUs/16GB Mem instances with standard storage.

The customer sent you :

1. a sample of the data

    ```text
    # table coupons ~7.5mio rows
    17,f5da34d7-6c8a-4c1c-af05-e09d41f9fca2,O,2223248,2020-12-10 02:05:14,A,2020-12-25 02:39:30
    21,496bffa4-57d9-4c00-a038-1677ab00384c,R,1966446,2020-12-22 00:22:05,A,2020-04-28 12:57:07
    19,d64858e1-f43e-4983-924d-68087e384995,R,180638,2020-12-20 16:58:00,A,2020-10-02 22:00:17
    ```

2. the schema:

    ```sql
    CREATE TABLE coupons (
        id INT2 NOT NULL,
        code UUID NOT NULL,
        channel STRING(1) NOT NULL,
        pid INT4 NOT NULL,
        exp_date DATE NOT NULL,
        status STRING(1) NOT NULL,
        start_date DATE NOT NULL,
        CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC),
        INDEX coupons_pid_idx (pid ASC),
        INDEX coupons_code_id_idx (code ASC, id ASC) STORING (channel, status, exp_date, start_date),
        FAMILY "primary" (id, code, channel, pid, exp_date, status, start_date)
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
    SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
    -- Q2
    SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
    ```

## Lab 1 - Recreate the customer environment

### Create the CockroachDB cluster

Create the CockroachDB cluster. You can use [roachprod](https://github.com/cockroachdb/cockroach/tree/master/pkg/cmd/roachprod) or your favorite DevOps tool.

```bash
# default machine type is n1-standard-4 (4 vCPUs / 16GB MEM)
roachprod create ${USER}-labs -c gce -n 12 --gce-zones us-east1-b,us-east1-c,us-west1-b,us-west1-c --gce-image ubuntu-2004-focal-v20201211
roachprod stage ${USER}-labs release v20.2.2
roachprod start ${USER}-labs
roachprod adminurl ${USER}-labs
```

Open Admin UI and confirm nodes are grouped into 4 zones, and zones are grouped into 2 regions.

![localities](media/localities.png)

Check the latency: should be minimal within zones of the same region.

![network-latency](media/network-latency.png)

### Recreate the dataset

We use [carota](https://pypi.org/project/carota/) to generate the random datasets. SSH into one of the servers

```bash
roachprod ssh ${USER}-labs:1
```

Once connected, install `pip3` if not already available, and create the dataset.

```bash
# install pip3
sudo apt-get update && sudo apt-get install python3-pip -y
# install carota
pip3 install --user --upgrade pip carota
export PATH=/home/ubuntu/.local/bin:$PATH
# create the dataset 'coupons' with 7,500,000 rows
carota -r 7500000 -t "int::start=1,end=28,seed=0; uuid::seed=0; choices::list=O R,weights=9 1,seed=0; int::start=1,end=3572420,seed=0; date::start=2020-12-15,delta=7,seed=0; choices::list=A R,weights=99 1,seed=0; date::start=2020-10-10,delta=180,seed=0" -o c.csv
```

Creating the dataset might take a few minutes. Once completed, we move the csv into the `extern` folder, used by CockroachDB to look for files to import.

```bash
sudo mkdir -p /mnt/data1/cockroach/extern/
sudo mv c.csv /mnt/data1/cockroach/extern/
```

Now you can exit from the box and connect to the database using your SQL client.

```bash
roachprod sql ${USER}-labs:1
```

At the SQL prompt, create the schema and import the data

```sql
-- add enterprise license
SET CLUSTER SETTING cluster.organization = 'ABC Corp';
SET CLUSTER SETTING enterprise.license = 'xxxx-yyyy-zzzz';

-- create the schema
CREATE TABLE coupons (
    id INT2 NOT NULL,
    code UUID NOT NULL,
    channel STRING(1) NOT NULL,
    pid INT4 NOT NULL,
    exp_date DATE NOT NULL,
    status STRING(1) NOT NULL,
    start_date DATE NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC),
    INDEX coupons_pid_idx (pid ASC),
    INDEX coupons_code_id_idx (code ASC, id ASC) STORING (channel, status, exp_date, start_date),
    FAMILY "primary" (id, code, channel, pid, exp_date, status, start_date)
);

CREATE TABLE offers (
    id INT4 NOT NULL,
    code UUID NOT NULL,
    token UUID NOT NULL,
    start_date DATE,
    end_date DATE,
    CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC, token ASC),
    INDEX offers_token_idx (token ASC),
    FAMILY "primary" (id, code, token)
);

-- import the dataset
IMPORT INTO coupons CSV DATA ('nodelocal://1/c.csv');
```

You can monitor the import in the DB Console in the **Jobs** page

![import-jop](media/import-job.png)

Cool, you've successfully created the cluster as per customer specifications, recreated the database schema and imported the dataset of dummy data into the database!

### Create the jumpbox server

Next, open a new terminal window. We will refer to this terminal as the **Jumpbox Terminal**.
Let's create a Jumpbox server from which to run the workload to simulate the App.

```bash
# simple ubuntu box on a starndard 4cpu/16 mem VM
roachprod create ${USER}-jump -c gce -n 1
# install cockroachdb just to have the sql client
roachprod stage ${USER}-jump release v20.2.2
# get the internal IP of one of the cluster nodes
roachprod ip ${USER}-labs:1
# ssh into the jumpbox
roachprod ssh ${USER}-jump:1
```

In the jumpbox, download the standalone `workload` binary, used to run the load test.

```bash
wget https://edge-binaries.cockroachdb.com/cockroach/workload.LATEST -O workload; chmod 755 workload
```

Test connection to CockroachDB, make sure to substitute the IP address accordingly

```bash
./cockroach sql -e "SHOW TABLES;" --url 'postgres://root@<ip>:26257?sslmode=disable'
```

You should see below output:

```text
  schema_name | table_name | type  | estimated_row_count
--------------+------------+-------+----------------------
  public      | coupons    | table |             7500000
  public      | offers     | table |                   0
(2 rows)

Time: 677ms
```

Good, the Jumpbox can connect to the cluster!

## Lab 2 - Analyse the CockroachDB cluster

Before running the workload, let's review the database we just imported, as well as analyze the SQL queries in the workload.

Open a new Terminal, the **SQL Terminal**, and connect to n1

```bash
roachprod sql ${USER}-labs:1
```

We've imported 2 tables, let's see what they look like in terms of size, columns, ranges, indexes. You can view these details using the AdminUI and/or with the `SHOW RANGES` command.

![databases](media/databases.png)

```sql
SHOW CREATE TABLE coupons;
SHOW RANGES FROM TABLE coupons;
```

`coupons` has 2 secondary indexes. Notice how the leaseholder of the ranges are spread across both regions (check the `lease_holder_locality` column).

```text
  table_name |                                         create_statement
-------------+----------------------------------------------------------------------------------------------------
  coupons    | CREATE TABLE public.coupons (
             |     id INT2 NOT NULL,
             |     code UUID NOT NULL,
             |     channel STRING(1) NOT NULL,
             |     pid INT4 NOT NULL,
             |     exp_date DATE NOT NULL,
             |     status STRING(1) NOT NULL,
             |     start_date DATE NOT NULL,
             |     CONSTRAINT "primary" PRIMARY KEY (id ASC, code ASC),
             |     INDEX coupons_pid_idx (pid ASC),
             |     INDEX coupons_code_id_idx (code ASC, id ASC) STORING (channel, status, exp_date, start_date),
             |     FAMILY "primary" (id, code, channel, pid, exp_date, status, start_date)
             | )
(1 row)

Time: 2.702s total (execution 2.702s / network 0.000s)

                        start_key                       |                        end_key                        | range_id | range_size_mb | lease_holder |           lease_holder_locality           | replicas |                                                          replica_localities
--------------------------------------------------------+-------------------------------------------------------+----------+---------------+--------------+-------------------------------------------+----------+----------------------------------------------------------------------------------------------------------------------------------------
  NULL                                                  | /1/"\x00\x05\x16\x80\xf7\xcbL䣵w\x81\x1a\x1d\xd6\xf6" |       38 |      0.000728 |            3 | cloud=gce,region=us-east1,zone=us-east1-b | {3,4,8}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-c","cloud=gce,region=us-west1,zone=us-west1-b"}
  /1/"\x00\x05\x16\x80\xf7\xcbL䣵w\x81\x1a\x1d\xd6\xf6" | /15/"\x15\xd3\xe7\xb3_\xa9A\"\xb5p\xa2\xf5\xb9Ba'"    |       40 |    225.468243 |            3 | cloud=gce,region=us-east1,zone=us-east1-b | {3,4,10} | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-c","cloud=gce,region=us-west1,zone=us-west1-c"}
  /15/"\x15\xd3\xe7\xb3_\xa9A\"\xb5p\xa2\xf5\xb9Ba'"    | NULL                                                  |       41 |    222.721298 |            4 | cloud=gce,region=us-east1,zone=us-east1-c | {3,4,8}  | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-c","cloud=gce,region=us-west1,zone=us-west1-b"}
(3 rows)

Time: 2.559s total (execution 2.558s / network 0.000s)
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
  NULL      | NULL    |       37 |             0 |            3 | cloud=gce,region=us-east1,zone=us-east1-b | {3,4,12} | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-c","cloud=gce,region=us-west1,zone=us-west1-c"}
(1 row)

Time: 2.557s total (execution 2.557s / network 0.000s)
```

Notice how table `offers` has 1 secondary index, and the table is empty (`range_size_mb` is 0).

Now, let's inspect the workload that's run against this database. Here's a formatted view of the 2 queries in `workload.sql`.

Please note, `000000` and `c744250a-1377-4cdf-a1f4-5b85a4d29aaa` are just placeholders for real variables: the customer has not supplied those so we hardcoded them.

```sql
-- Q1
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c
WHERE c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '000000'

UNION

SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c, offers AS o
WHERE c.id = o.id
  AND c.code = o.code
  AND c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';

-- Q2
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c, offers AS o
WHERE c.id = o.id
  AND c.code = o.code
  AND c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

So Q2 is basically the second part of Q1, and it's a join query between the 2 tables. Q1 also has a `SELECT DISTINCT` part, too.

## Lab 3 - Simulate the load test

Back to your host, get the full list of DB URLs. Save it for later.

```bash
$ roachprod pgurl ${USER}-labs
'postgres://root@10.150.0.108:26257?sslmode=disable' 'postgres://root@10.150.0.109:26257?sslmode=disable' 'postgres://root@10.150.0.107:26257?sslmode=disable' 'postgres://root@10.150.0.105:26257?sslmode=disable' 'postgres://root@10.150.0.106:26257?sslmode=disable' 'postgres://root@10.150.0.110:26257?sslmode=disable' 'postgres://root@10.138.0.23:26257?sslmode=disable' 'postgres://root@10.138.0.15:26257?sslmode=disable' 'postgres://root@10.138.0.24:26257?sslmode=disable' 'postgres://root@10.138.0.28:26257?sslmode=disable' 'postgres://root@10.138.0.27:26257?sslmode=disable' 'postgres://root@10.138.0.31:26257?sslmode=disable'
```

In the Jumpbox Terminal, run the workload simulation passing all URLs. We are running this workload with 512 active connections, which is far more than the cluster is designed for, which is approximately 12 nodes \* 4 vCPUs \* 4 Active Connections per vCPU = 192 Active Connections. We do so to simulate the highest load.

Create file `workload.sql` with the queries given by the customer

```sql
-- Q1
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
-- Q2
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

Then run the workload passing the file `workload.sql`.

```bash
./workload run querybench --query-file workload.sql --db=defaultdb --concurrency=512 'postgres://root@10.150.0.110:26257?sslmode=disable' 'postgres://root@10.150.0.95:26257?sslmode=disable' 'postgres://root@10.150.0.111:26257?sslmode=disable' 'postgres://root@10.150.0.109:26257?sslmode=disable' 'postgres://root@10.150.0.92:26257?sslmode=disable' 'postgres://root@10.150.0.93:26257?sslmode=disable' 'postgres://root@10.138.0.2:26257?sslmode=disable' 'postgres://root@10.138.0.8:26257?sslmode=disable' 'postgres://root@10.138.0.9:26257?sslmode=disable' 'postgres://root@10.138.0.18:26257?sslmode=disable' 'postgres://root@10.138.0.10:26257?sslmode=disable' 'postgres://root@10.138.0.39:26257?sslmode=disable'
```

You should see the output similar to below:

```text
_elapsed___errors__ops/sec(inst)___ops/sec(cum)__p50(ms)__p95(ms)__p99(ms)_pMax(ms)
   21.0s        0         1965.5         1980.8    109.1    302.0    402.7    419.4  1: SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
   21.0s        0         2011.5         1970.6     92.3    268.4    302.0    402.7  2: SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
   22.0s        0         2005.0         1981.9    104.9    302.0    385.9    436.2  1: SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
   22.0s        0         2001.1         1972.0     92.3    251.7    352.3    385.9  2: SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

While it runs, check the Metrics in the AdminUI. Open the **Hardware** dashboard to see if you can replicate the spike in high CPU usage.

![cpu](media/cpu.png)

Notice how 2 nodes have very high CPU usage compared to all other nodes. Take notice in the **Summary** of the values for QPS - 4046 - and P99 latency - 402ms -, too.

Check the latency for these 2 queries. Open the **Statements** page or review the scrolling stats in your terminal.

![stmt-latency](media/stmt-latency.png)

Check also **Service Latency** charts in the **SQL** dashboard for a better understanding.

![sql-p99](media/sql-p99.png)

Stop the workload now. You can definitely replicate the customer scenario: high CPU spikes and high latency.

## Lab 4 - Analyze the Queries

Switch to the SQL Terminal. We want to pull the query plan for each query

### Q1 Query Plan

Let's start with Q1, and let's break it down into 2 parts, and let's pull the plan for the 1st part. Again, here the value `000000` is a placeholder for a value passed by the application.

```sql
EXPLAIN (VERBOSE) SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c
WHERE c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '000000';
```

```text
          tree         |        field        |                                   description                                    |                        columns                         | ordering
-----------------------+---------------------+----------------------------------------------------------------------------------+--------------------------------------------------------+-----------
                       | distribution        | local                                                                            |                                                        |
                       | vectorized          | false                                                                            |                                                        |
  project              |                     |                                                                                  | (id, code, channel, status, exp_date, start_date)      |
   │                   | estimated row count | 0                                                                                |                                                        |
   └── filter          |                     |                                                                                  | (id, code, channel, pid, exp_date, status, start_date) |
        │              | estimated row count | 0                                                                                |                                                        |
        │              | filter              | ((status = 'A') AND (exp_date >= '2020-11-20')) AND (start_date <= '2020-11-20') |                                                        |
        └── index join |                     |                                                                                  | (id, code, channel, pid, exp_date, status, start_date) |
             │         | estimated row count | 0                                                                                |                                                        |
             │         | table               | coupons@primary                                                                  |                                                        |
             │         | key columns         | id, code                                                                         |                                                        |
             └── scan  |                     |                                                                                  | (id, code, pid)                                        |
                       | estimated row count | 0                                                                                |                                                        |
                       | table               | coupons@coupons_pid_idx                                                          |                                                        |
                       | spans               | /0-/1                                                                            |                                                        |
(15 rows)

Time: 77ms total (execution 77ms / network 0ms)
```

So the optimizer is leveraging index `coupons@coupons_pid_idx` to filter rows that have that specific `pid`, but then it has to do a join with `primary` to fetch `status`, `exp_date` and `start_date` to finish the rest of the `WHERE`, and `SELECT`, clauses.

Wouldn't it be better if it didn't have to do this join and instead accessing just 1 index?

### Q2 Query Plan

Let's now pull the plan for Q2.

```sql
EXPLAIN (VERBOSE) SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c, offers AS o
WHERE c.id = o.id
  AND c.code = o.code
  AND c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
```

```text
            tree           |         field         |                                     description                                     |                              columns                               | ordering
---------------------------+-----------------------+-------------------------------------------------------------------------------------+--------------------------------------------------------------------+-----------
                           | distribution          | full                                                                                |                                                                    |
                           | vectorized            | false                                                                               |                                                                    |
  project                  |                       |                                                                                     | (id, code, channel, status, exp_date, start_date)                  |
   │                       | estimated row count   | 0                                                                                   |                                                                    |
   └── lookup join (inner) |                       |                                                                                     | (id, code, token, id, code, channel, exp_date, status, start_date) |
        │                  | estimated row count   | 0                                                                                   |                                                                    |
        │                  | table                 | coupons@coupons_code_id_idx                                                         |                                                                    |
        │                  | equality              | (code, id) = (code,id)                                                              |                                                                    |
        │                  | equality cols are key |                                                                                     |                                                                    |
        │                  | pred                  | ((status = 'A') AND (exp_date >= '2020-11-20')) AND (start_date <= '2020-11-20')    |                                                                    |
        └── scan           |                       |                                                                                     | (id, code, token)                                                  |
                           | estimated row count   | 1                                                                                   |                                                                    |
                           | table                 | offers@offers_token_idx                                                             |                                                                    |
                           | spans                 | /"\xc7D%\n\x13wLߡ\xf4[\x85\xa4Қ\xaa"-/"\xc7D%\n\x13wLߡ\xf4[\x85\xa4Қ\xaa"/PrefixEnd |                                                                    |
```

Here we see that the optimizer is choosing an index to filter from the `offers` table and join with `coupons`, which is fine.

## Lab 5 - Addressing the Hotspot

Let's tackle the high CPU usage issue first. Why is it so, why is a node, n3 in this case, using all the CPU?

We can try to isolate the issue by running only Q2 in our workload, and let's see if the problem persist.

Switch to the Jumpbox Terminal and edit file `workload.sql` to comment Q1 out, then restart the workload. Give it a couple of minutes, and you should see that n3 is hot again, so we know that Q2 is the culprit.

![hot-n3](media/hot-n3.png)

Let's see if we have a hot range.

Upload file `hot.py` to the jumpbox, or run it locally on a new terminal if you prefer

```bash
$ python3 hot.py --numtop 10 --host ${USER}-labs-0001.roachprod.crdb.io --adminport 26258 --dbport 26257  
rank  rangeId          QPS           Nodes       leaseHolder    DBname, TableName, IndexName
  1:       37   2006.722472     [4, 3, 12]                 3    ['defaultdb', 'offers', '']
  2:       39   857.900812       [5, 2, 8]                 5    ['defaultdb', 'coupons', 'coupons_pid_idx']
  3:        6    48.688882      [1, 6, 3, 11, 9]                   9    ['', '', '']
  4:       26    17.644921      [1, 4, 11, 12, 7]                  4    ['system', 'namespace2', '']
  5:        4    15.409775      [1, 9, 12]                12    ['', '', '']
  6:       35    12.764951      [4, 3, 9, 8, 10]                  10    ['system', 'sqlliveness', '']
  7:       11     3.369730      [6, 2, 9, 12, 10]                  2    ['system', 'jobs', '']
  8:        2     2.697347      [1, 5, 3, 12, 7]                  12    ['', '', '']
  9:        3     1.976292      [6, 4, 3, 11, 7]                   6    ['', '', '']
 10:        7     1.373621      [1, 2, 4, 12, 7]                   4    ['system', 'lease', '']
```

So it looks like rangeId 37 on n3 is hot. What's in that range, why that range?

Back to your SQL terminal, show the ranges for `offers@offers_token_idx`, since the query plan showed it's using this index

```sql
SHOW RANGES FROM INDEX offers@offers_token_idx;
```

```text
  start_key | end_key | range_id | range_size_mb | lease_holder |           lease_holder_locality           | replicas |                                                          replica_localities
------------+---------+----------+---------------+--------------+-------------------------------------------+----------+----------------------------------------------------------------------------------------------------------------------------------------
  NULL      | NULL    |       37 |             0 |            3 | cloud=gce,region=us-east1,zone=us-east1-b | {3,4,12} | {"cloud=gce,region=us-east1,zone=us-east1-b","cloud=gce,region=us-east1,zone=us-east1-c","cloud=gce,region=us-west1,zone=us-west1-c"}
(1 row)

Time: 2.517s total (execution 2.516s / network 0.000s)
```

Bingo! We found rangeId 37.
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

Stop the running workload, then, like for `coupons`, generate the dataset and import it into `offers`.
On the host terminal, connect again to a cluster server

```bash
roachprod ssh ${USER}-labs:1

# once connected, create the dataset, 'offers'
# note: we use a seed here so that we can reporduce the same UUIDs used later
# by reusing the same seed, we ensure the field id and code match between the 2 tables
carota -r 10000 -t "int::start=1,end=28,seed=0; uuid::seed=0; uuid::seed=1; date; date" -o o.csv
# then we append some more random data
carota -r 6000000 -t "int::start=0,end=100,seed=5; uuid::seed=5; uuid::seed=6; date; date" -o o.csv --append

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
SELECT token FROM offers@offers_token_idx LIMIT 1 OFFSET 1; -- then increment of ~700,000
```

We can use this data to create a new workload file, `q2.sql`. Scroll below text to the right to see the tokens.
Notice they are in lexicographical order.

```sql
-- scroll to the right!
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '00000276-014e-4ecc-9c99-0b59d80f1973';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '77516bf5-af2c-4042-8917-4d5b408908ed';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'b2f3e754-2b50-490d-944d-c41fb73c90c4';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '3baa519e-c21d-47ae-99c3-a25c649ebaa2';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'ee8452d1-858e-4f27-b77a-f3c81d764b6a';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '9530fef8-ced9-47a7-bed3-53bf1eb5e1fe';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '59787eba-7709-4f0f-9fb3-7532180e5e38';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'd0b3bbd2-e69c-4484-b4c3-50ce0d68a9e3';
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '1dd9dbb7-ac42-43d0-ab04-a37ddc7536cc';
```

Run workload `q2.sql` for a while, at least 5 minutes to give time to Cockroach to reassign leaseholders around the ranges of the cluster.
Check the **Hardware** dashboard again

![cpu-even](media/cpu-even.png)

Much better, good job! Let's see how the ranges for the index are spread out:

```sql
SELECT lease_holder, lease_holder_locality FROM [SHOW RANGES FROM INDEX offers@offers_token_idx];
```

```text
  lease_holder |           lease_holder_locality
---------------+--------------------------------------------
             5 | cloud=gce,region=us-east1,zone=us-east1-c
             4 | cloud=gce,region=us-east1,zone=us-east1-c
             3 | cloud=gce,region=us-east1,zone=us-east1-b
             2 | cloud=gce,region=us-east1,zone=us-east1-b
```

Better! On average we can expect the load to be spread across 4 ranges in 4 different nodes.

## Lab 6 - Addressing the Latency

### Understanding where the latency comes from

On the SQL Terminal, let's run a few queries and see the Response Time. Mind, in your cluster the Response Time might vary as ranges can be located on different zones.

Show my locality first

```sql
SHOW LOCALITY;
```

```text
                  locality
---------------------------------------------
  cloud=gce,region=us-east1,zone=us-east1-b
(1 row)

Time: 2ms total (execution 1ms / network 0ms)
```

Ok, I'm in US East. Let's run the first part of Q1 using a randomly picked valid `c.pid`.

```sql
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c
WHERE c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '1109619';
```

```text
  id |                 code                 | channel | status |         exp_date          |        start_date
-----+--------------------------------------+---------+--------+---------------------------+----------------------------
   9 | f99e6553-18fb-475b-910e-eae4287e7ffa | O       | A      | 2020-12-19 00:00:00+00:00 | 2020-05-04 00:00:00+00:00
(1 row)

Time: 67ms total (execution 67ms / network 0ms)
```

Response Time is 69ms, a little too much. Why is it so? Let's check where the range that has this row is located.

From the query plan we pulled above, we see that it's using index `coupons_pid_idx`. Find the key of the index

```sql
SHOW INDEX FROM coupons;
```

```text
  table_name |     index_name      | non_unique | seq_in_index | column_name | direction | storing | implicit
-------------+---------------------+------------+--------------+-------------+-----------+---------+-----------
  coupons    | primary             |   false    |            1 | id          | ASC       |  false  |  false
  coupons    | primary             |   false    |            2 | code        | ASC       |  false  |  false
  
  coupons    | coupons_pid_idx     |    true    |            1 | pid         | ASC       |  false  |  false
  coupons    | coupons_pid_idx     |    true    |            2 | id          | ASC       |  false  |   true
  coupons    | coupons_pid_idx     |    true    |            3 | code        | ASC       |  false  |   true
  
  coupons    | coupons_code_id_idx |    true    |            1 | code        | ASC       |  false  |  false
  coupons    | coupons_code_id_idx |    true    |            2 | id          | ASC       |  false  |  false
  coupons    | coupons_code_id_idx |    true    |            3 | channel     | N/A       |  true   |  false
  coupons    | coupons_code_id_idx |    true    |            4 | status      | N/A       |  true   |  false
  coupons    | coupons_code_id_idx |    true    |            5 | exp_date    | N/A       |  true   |  false
  coupons    | coupons_code_id_idx |    true    |            6 | start_date  | N/A       |  true   |  false
```

Cool, for `coupons@coupons_pid_idx` the key is `pid id code`.
Let's pull the correct range

```sql
SELECT lease_holder_locality FROM [SHOW RANGE FROM INDEX coupons@coupons_pid_idx FOR ROW(1109619, 9, 'f99e6553-18fb-475b-910e-eae4287e7ffa')];
```

```text
            lease_holder_locality
---------------------------------------------
  cloud=gce,region=us-east1,zone=us-east1-b
```

Ok, the range is local (us-east-1), this should only take 1ms.. From the query plan we see that there is a join with `coupons@primary` to fetch the other columns.
Let's see how long that takes

```sql
SELECT * FROM  coupons@primary WHERE id = 9 AND code = 'f99e6553-18fb-475b-910e-eae4287e7ffa';
```

```text
  id |                 code                 | channel |   pid   |         exp_date          | status |        start_date
-----+--------------------------------------+---------+---------+---------------------------+--------+----------------------------
   9 | f99e6553-18fb-475b-910e-eae4287e7ffa | O       | 1109619 | 2020-12-19 00:00:00+00:00 | A      | 2020-05-04 00:00:00+00:00
(1 row)

Time: 66ms total (execution 66ms / network 0ms)
```

66ms! Let's do the same exercise as before and find out where this range is located.

```sql
SELECT lease_holder_locality FROM [SHOW RANGE FROM TABLE coupons FOR ROW(9, 'f99e6553-18fb-475b-910e-eae4287e7ffa')];
```

```text
           lease_holder_locality           
-------------------------------------------
 cloud=gce,region=us-west1,zone=us-west1-c 
```

A-ha! This table is in US West, so we're paying the latency price to go to the other region to fetch the data.

The problem is twofold: sub-optimal tables/indexes, cross-regional reads.

### Part 1 - Optimize the table primary and secondary indexes

Let's optimize the first part of Q1 by removing the need to join with `coupons@primary`.
We need to create an index similar to `coupons@coupons_pid_idx` that stores the fields required by the query.
Also, index `coupons@coupons_code_id_idx` seems to be redundant, so we drop it.

```sql
DROP INDEX coupons@coupons_code_id_idx;
DROP INDEX coupons@coupons_pid_idx;
CREATE INDEX coupons_pid_idx ON coupons(pid ASC) STORING (channel, exp_date, status, start_date);
```

Pull the query plan to confirm no join is required

```sql
EXPLAIN (VERBOSE) SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c
WHERE c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '12';
```

```text
       tree      |        field        |                                   description                                    |                        columns                         | ordering
-----------------+---------------------+----------------------------------------------------------------------------------+--------------------------------------------------------+-----------
                 | distribution        | local                                                                            |                                                        |
                 | vectorized          | false                                                                            |                                                        |
  project        |                     |                                                                                  | (id, code, channel, status, exp_date, start_date)      |
   │             | estimated row count | 0                                                                                |                                                        |
   └── filter    |                     |                                                                                  | (id, code, channel, pid, exp_date, status, start_date) |
        │        | estimated row count | 0                                                                                |                                                        |
        │        | filter              | ((status = 'A') AND (exp_date >= '2020-11-20')) AND (start_date <= '2020-11-20') |                                                        |
        └── scan |                     |                                                                                  | (id, code, channel, pid, exp_date, status, start_date) |
                 | estimated row count | 0                                                                                |                                                        |
                 | table               | coupons@coupons_pid_idx                                                          |                                                        |
                 | spans               | /12-/13                                                                          |                                                        |
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
```

### Part 2 - Create duplicate indexes and pin to region

Now that we have our tables well organized, we need to resolve the latency issue.
We need our read latency to be the same regardless of where the query originates.
The customer told us they cannot change the App, so the Follower Reads pattern  is unfortunately not available.
The best solution thus is to follow the Duplicate Index pattern: we create a copy of each index and table.
Then, we pin Tables to US West and Indexes to US East.

Create indexes first

```sql
-- copy of coupons@primary
CREATE INDEX primary_copy ON coupons(id ASC, code ASC) STORING (channel, pid, exp_date, status, start_date);
-- copy of coupons_pid_idx
CREATE INDEX coupons_pid_idx_copy on coupons(pid ASC) STORING (channel, exp_date, status, start_date);

-- copy of offers@primary
CREATE INDEX primary_copy ON offers(token ASC, id ASC, code ASC) STORING (start_date, end_date);
```

Good stuff, we have now a copy of each index (`primary` included).
Next, pin a copy to East, and another to West.

```sql
-- coupons
--   pin to East
ALTER TABLE coupons CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-east1: 1}',
  lease_preferences = '[[+region=us-east1]]';

ALTER INDEX coupons@coupons_pid_idx CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-east1: 1}',
  lease_preferences = '[[+region=us-east1]]';

--   pin to West
ALTER INDEX coupons@primary_copy CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-west1: 1}',
  lease_preferences = '[[+region=us-west1]]';

ALTER INDEX coupons@coupons_pid_idx_copy CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-west1: 1}',
  lease_preferences = '[[+region=us-west1]]';

-- offers
--    pin to East
ALTER TABLE offers CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-east1: 1}',
  lease_preferences = '[[+region=us-east1]]';

--    pin to West
ALTER INDEX offers@primary_copy CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{+region=us-west1: 1}',
  lease_preferences = '[[+region=us-west1]]';
```

### Part 3 - Validate the theory

Re run the first part of query Q1 from both regions. Check the query plan using `EXPLAIN (VERBOSE)`.

From node 1 (US East region):

```sql
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c
WHERE c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '12';
```

```text
  id |                 code                 | channel | status |         exp_date          |        start_date
-----+--------------------------------------+---------+--------+---------------------------+----------------------------
  19 | 468750f4-cb58-4707-9fd3-bd5f99111855 | O       | A      | 2020-12-18 00:00:00+00:00 | 2020-09-21 00:00:00+00:00
(1 row)

Time: 1ms total (execution 1ms / network 0ms)
```

```sql
EXPLAIN (VERBOSE) SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date
FROM coupons AS c
WHERE c.status = 'A'
  AND c.exp_date >= '2020-11-20'
  AND c.start_date <= '2020-11-20'
  AND c.pid = '12';
```

```text
       tree      |        field        |                                      description                                      |                        columns                         | ordering
-----------------+---------------------+---------------------------------------------------------------------------------------+--------------------------------------------------------+-----------
                 | distribution        | local                                                                                 |                                                        |
                 | vectorized          | false                                                                                 |                                                        |
  project        |                     |                                                                                       | (id, code, channel, status, exp_date, start_date)      |
   │             | estimated row count | 0                                                                                     |                                                        |
   └── filter    |                     |                                                                                       | (id, code, channel, pid, exp_date, status, start_date) |
        │        | estimated row count | 0                                                                                     |                                                        |
        │        | filter              | ((status = 'A') AND (exp_date >= '2020-11-20')) AND (start_date <= '2020-11-20') |                                                        |
        └── scan |                     |                                                                                       | (id, code, channel, pid, exp_date, status, start_date) |
                 | estimated row count | 0                                                                                     |                                                        |
                 | table               | coupons@coupons_pid_idx                                                               |                                                        |
                 | spans               | /3124791208-/3124791209                                                               |                                                        |                                                        |                                                        |
```

Same queries above run on node 12 (US West region):

```text
  id |                 code                 | channel | status |         exp_date          |        start_date
-----+--------------------------------------+---------+--------+---------------------------+----------------------------
  19 | 468750f4-cb58-4707-9fd3-bd5f99111855 | O       | A      | 2020-12-18 00:00:00+00:00 | 2020-09-21 00:00:00+00:00
(1 row)

Time: 2ms total (execution 1ms / network 0ms)
```

```text
       tree      |        field        |                                      description                                      |                        columns                         | ordering
-----------------+---------------------+---------------------------------------------------------------------------------------+--------------------------------------------------------+-----------
                 | distribution        | local                                                                                 |                                                        |
                 | vectorized          | false                                                                                 |                                                        |
  project        |                     |                                                                                       | (id, code, channel, status, exp_date, start_date)      |
   │             | estimated row count | 1                                                                                     |                                                        |
   └── filter    |                     |                                                                                       | (id, code, channel, pid, exp_date, status, start_date) |
        │        | estimated row count | 1                                                                                     |                                                        |
        │        | filter              | ((status = 'A') AND (exp_date >= '2020-11-19')) AND (start_date <= '2020-11-19') |                                                        |
        └── scan |                     |                                                                                       | (id, code, channel, pid, exp_date, status, start_date) |
                 | estimated row count | 2                                                                                     |                                                        |
                 | table               | coupons@coupons_pid_idx_copy                                                          |                                                        |
                 | spans               | /3124791208-/3124791209                                                               |                                                        |
```

Perfect, we've low latency from both regions! Now start the workload again and let's measure the overall latency.

Mind, the workload still has the hardcoded values. Review and create file `final.sql` which should be closer to the real workflow, with real `offers.token` and `coupons.id|code` values

```sql
-- final.sql
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3132039537') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '9530fef8-ced9-47a7-bed3-53bf1eb5e1fe')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'd554a4cf-6c83-454e-83f4-38f019cf4734';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '1279') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'd0b3bbd2-e69c-4484-b4c3-50ce0d68a9e3')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '7ffb8711-669f-4ca2-bf22-af047bd188be';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2743109489') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '59787eba-7709-4f0f-9fb3-7532180e5e38')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '3baa519e-c21d-47ae-99c3-a25c649ebaa2';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3002738477') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'b2f3e754-2b50-490d-944d-c41fb73c90c4')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '59787eba-7709-4f0f-9fb3-7532180e5e38';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2189670715') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '00000276-014e-4ecc-9c99-0b59d80f1973')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '77516bf5-af2c-4042-8917-4d5b408908ed';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2737195593') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '7ffb8711-669f-4ca2-bf22-af047bd188be')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'ee8452d1-858e-4f27-b77a-f3c81d764b6a';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2936320808') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '77516bf5-af2c-4042-8917-4d5b408908ed')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '1dd9dbb7-ac42-43d0-ab04-a37ddc7536cc';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2579495379') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'ee8452d1-858e-4f27-b77a-f3c81d764b6a')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'b2f3e754-2b50-490d-944d-c41fb73c90c4';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3050862498') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '1dd9dbb7-ac42-43d0-ab04-a37ddc7536cc')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '00000276-014e-4ecc-9c99-0b59d80f1973';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3050862498') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = 'd554a4cf-6c83-454e-83f4-38f019cf4734')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = '9530fef8-ced9-47a7-bed3-53bf1eb5e1fe';

SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '3050862498') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '3baa519e-c21d-47ae-99c3-a25c649ebaa2')
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'd0b3bbd2-e69c-4484-b4c3-50ce0d68a9e3';
```

```text
_elapsed___errors__ops/sec(inst)___ops/sec(cum)__p50(ms)__p95(ms)__p99(ms)_pMax(ms)
  339.0s        0          361.8          365.4     88.1    151.0    167.8    192.9  9: SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE (((c.status = 'A') AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (c.pid = '2737195593') UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '7fdcaac7-6f19-1599-a476-934cf7cd061a')
      0          406.8          364.9     48.2    130.0    184.5    192.9 16: SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE (((((c.id = o.id) AND (c.code = o.code)) AND (c.status = 'A')) AND (c.exp_date >= '2020-11-20')) AND (c.start_date <= '2020-11-20')) AND (o.token = '1fde0504-6a32-0578-75f0-7d25b87996b4');
```

Compare to the initial result: huge improvement in performance! We doubled the QPS and halved the Lantency!

![final](media/final.png)

Congratulations, you reached the end of the Troubleshooting workshop! We hope you have now a better understanding on the process of troubleshoot an underperforming cluster.

## Extras

Head over [here](exercise.md) for another example you can run from your desktop computer!
