# Architecture workshop

The following labs will take you through various query tuning scenarios and allow you to discover various ways to observe, diagnose, and optimize query performance with CockroachDB.

## Labs Prerequisites

1. Docker compose
2. Cockroach binary on Mac or Windows
3. A modern web browser
4. A commandline client:
    - Terminal (MacOS/Linux)
    - Powershell (Windows)

## Lab 0 - Start up a cluster
Go to infrastructure/single-region-dockercompose-cluster directory
Update cockroach version and license information in docker.sh then start Cockroach cluster on docker via docker compose
```bash
./docker-up.sh
```

## Lab 1 - Validate cluster regions and the node that we connected to

Connect to the database

```bash
cockroach sql --insecure --url postgres://localhost:26257
```

At the SQL prompt, validate regions and zones our cluster runs on
```sql
show regions;
```
We shall see
```text
root@localhost:26257/arch_workshop> show regions;
  region  |            zones             | database_names | primary_region_of
----------+------------------------------+----------------+--------------------
  us-east | {us-east1,us-east2,us-east3} | {}             | {}
(1 row)


Time: 17ms total (execution 15ms / network 2ms)
```
We'll talk about what more about primary region in Multi-region workshop.
```sql
show locality;
```
We see that we connected to us-east1 node. If you use a different port number, you can connect to another node
```text
            locality
--------------------------------
  region=us-east,zone=us-east1
(1 row)


Time: 6ms total (execution 5ms / network 1ms)


```

## Lab 2 - Create database and load data

At the SQL prompt, create your database
```sql
CREATE DATABASE arch_workshop;
USE arch_workshop;
CREATE TABLE inventory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_name STRING,
  quantity INT8
);
INSERT INTO inventory (product_name, quantity)
SELECT concat('product', generate_series(1, 1000000)::String), 10000.0*random()::INT8;
```

```text
INSERT 1000000


Time: 27.058s total (execution 27.052s / network 0.006s)
```
We just created 1M test data in the table in a single transaction. This is an example that a big transaction has long latency. Big transactions also creates contention, which could further slow down performance. We'll discuss it in Query Optimization & Serializable workshops. <br>

Now let's look at the table. 
```sql
SHOW TABLES;
```

```text
  schema_name | table_name | type  | owner | estimated_row_count | locality
--------------+------------+-------+-------+---------------------+-----------
  public      | inventory  | table | root  |             1000000 | NULL
(1 row)


Time: 42ms total (execution 41ms / network 1ms)
```

## Lab 3 - Ranges, Replicas and Leaseholder

Let's look at the Replication Layer elements on this table

```sql
SHOW RANGES FROM TABLE inventory;
```

```text
  start_key | end_key | range_id | range_size_mb | lease_holder |    lease_holder_locality     | replicas |                                       replica_localities
------------+---------+----------+---------------+--------------+------------------------------+----------+-------------------------------------------------------------------------------------------------
  NULL      | NULL    |       37 |     56.943683 |            4 | region=us-east,zone=us-east3 | {1,3,4}  | {"region=us-east,zone=us-east1","region=us-east,zone=us-east4","region=us-east,zone=us-east3"}
(1 row)
Time: 26ms total (execution 25ms / network 1ms)
```
The table has one range.
Questions: 
 - What's the range id? 
 - What's the size of the range?
 - How many replicas do we have for the range and which nodes are they located?
 - Which replicas is the leaseholder?
 - What's the default size of maximum range size?
 
## Lab 4 - Ranges Splits
CockroachDB splits and merges ranges depending on range size, load, etc.
In this lab we'll manually split a range to simulate an event.
```sql
SELECT * FROM inventory LIMIT 1 OFFSET 500000;
ALTER TABLE inventory SPLIT AT SELECT id FROM inventory LIMIT 1 OFFSET 500000;
```

```text
                                   key                                  |                        pretty                         |    split_enforced_until
------------------------------------------------------------------------+-------------------------------------------------------+-----------------------------
  \xbd\x89\x12\x80"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14\x00\x01 | /"\x80\"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14" | 2262-04-11 23:47:16.854776
(1 row)


Time: 636ms total (execution 634ms / network 1ms)
```
Questions:
- What's value of split_enforced_until column?

Now let's look at the ranges of this table again. 
```sql
SHOW RANGES FROM TABLE inventory;
```

```text
                        start_key                       |                        end_key                        | range_id | range_size_mb | lease_holder |    lease_holder_locality     | replicas |                                       replica_localities
--------------------------------------------------------+-------------------------------------------------------+----------+---------------+--------------+------------------------------+----------+-------------------------------------------------------------------------------------------------
  NULL                                                  | /"\x80\"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14" |       37 |     28.473971 |            3 | region=us-east,zone=us-east4 | {1,3,4}  | {"region=us-east,zone=us-east1","region=us-east,zone=us-east4","region=us-east,zone=us-east3"}
  /"\x80\"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14" | NULL                                                  |       38 |     28.469712 |            4 | region=us-east,zone=us-east3 | {1,3,4}  | {"region=us-east,zone=us-east1","region=us-east,zone=us-east4","region=us-east,zone=us-east3"}
(2 rows)


Time: 21ms total (execution 20ms / network 1ms)
```
Questions:
- How many ranges do we have now? what's the size of each?
- Which range does the row we split at belong to? If you don't know the answer proceed to Lab 5.

###Lab 5 Find out range for a specific row
We can also look at range for a specific row:
```sql
SELECT * FROM inventory LIMIT 1 OFFSET 500000;
SHOW RANGE FROM TABLE inventory FOR ROW ('[Use the same id as the SPLIT AT id]');
```
```text
                        start_key                       | end_key | range_id | lease_holder |    lease_holder_locality     | replicas |                                       replica_localities
--------------------------------------------------------+---------+----------+--------------+------------------------------+----------+-------------------------------------------------------------------------------------------------
  /"\x80\"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14" | NULL    |       38 |            4 | region=us-east,zone=us-east3 | {1,3,4}  | {"region=us-east,zone=us-east1","region=us-east,zone=us-east4","region=us-east,zone=us-east3"}


Time: 17ms total (execution 16ms / network 1ms)
```
From results above, we know a range includes its start key but not its end key.

### Lab 6 Cluster resiliency
Now open browser and `http://localhost:8081/`, note all nodes on Overview page has 'Live' status
If a node fails to send heart beat, the cluster waits for 5 minutes before it considers the node dead.
The duration is configurable via a cluster setting. Let's confirm the default value.
```sql
SHOW CLUSTER SETTING server.time_until_store_dead;
```
```text
  server.time_until_store_dead
--------------------------------
  00:05:00
(1 row)


Time: 2ms total (execution 1ms / network 1ms)
```
Now let's change it to mininum amount before we stop a node.
```sql
SET CLUSTER SETTING server.time_until_store_dead='1m15s';
```
```text
SET CLUSTER SETTING


Time: 30ms total (execution 29ms / network 1ms)
```
Now choose a node w/ replicas of inventory table. n3 or n4)
```bash
docker compose stop us-east4
```
What's the status of node in us-east4? (WARNING)
Wait for 1 minutes 15 seconds, and what's the status now? (DEAD)
Let's look at the ranges again.
```sql
SHOW RANGES FROM TABLE inventory;
```
```text
                        start_key                       |                        end_key                        | range_id | range_size_mb | lease_holder |    lease_holder_locality     | replicas |                                       replica_localities
--------------------------------------------------------+-------------------------------------------------------+----------+---------------+--------------+------------------------------+----------+-------------------------------------------------------------------------------------------------
NULL                                                  | /"\x80\"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14" |       37 |     28.473971 |            4 | region=us-east,zone=us-east3 | {1,2,4}  | {"region=us-east,zone=us-east1","region=us-east,zone=us-east2","region=us-east,zone=us-east3"}
/"\x80\"\x8b/\x19\xa2H5\xa8S\xf8\x1e\xae\xdc\xd2\x14" | NULL                                                  |       38 |     28.469712 |            4 | region=us-east,zone=us-east3 | {1,2,4}  | {"region=us-east,zone=us-east1","region=us-east,zone=us-east2","region=us-east,zone=us-east3"}
(2 rows)


Time: 28ms total (execution 24ms / network 3ms)
```
Question: Which nodes are the replicas located now?


```sql
SELECT * FROM inventory limit 10 OFFSET 200000;
```
Question: 
- Can you read / write to the table now?
- What if we take down another node? Try it yourself using `docker compose stop us-east[1-4]`. When you like to bring the nodes back online, use ` docker compose up us-east[1-4] --detach`


## Final thoughts

Congratulations! You have completed the labs for Architecture workshop, you have a deeper understanding of the architecture 

Some suggested material to further expand on this topic are found in our docs:

- [Architecture Overview](https://www.cockroachlabs.com/docs/v21.2/architecture/overview.html)

Blog:
- [The Architecture of a Distributed SQL Database Pt 1:Converting SQL to a KV Store](https://www.cockroachlabs.com/blog/distributed-sql-key-value-store/)
