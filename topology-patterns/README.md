# Topology Patterns - Student Labs

In these labs we will work with CockroachDB [Topology Patterns](https://www.cockroachlabs.com/docs/stable/topology-patterns.html) and understand the use cases, pros and cons for each one.

## Overview

There are 6 recommended topology patterns:

| Topology                                                                                                             | Description | Pros | Cons |
|----------------------------------------------------------------------------------------------------------------------|-------------|------|------|
| [Basic Production](https://www.cockroachlabs.com/docs/stable/topology-basic-production.html)                         | Single region deployment | Fast r/w | Can't survive region failure |
| [Geo-Partitioned Replicas](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-replicas.html)         | Multi-region deployment where data is partitioned and pinned to a specific region, ideal for GDPR or similar legal compliance | Fast r/w if client is connected to the region which holds the data is querying | Locked data can't survive region failure - it would require multiple regions in the same country|
| [Geo-Partitioned Leaseholders](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-leaseholders.html) | Multi-region deployment where leaseholder is pinned to a specific region | Fast reads if client connects to region which holds the data; can survive region failure | Slightly slower writes as leaseholder has to seek consensus outside its region |
| [Duplicate Indexes](https://www.cockroachlabs.com/docs/stable/topology-duplicate-indexes.html)                       | Most used indexes are duplicated by the amount of regions and the index leaseholders are pinned 1 per region; ideal for data that doesn't frequently updates  | Fast reads from any region | Slower writes as every index needs to be updated; duplicate data increases storage |
| [Follower Reads](https://www.cockroachlabs.com/docs/stable/topology-follower-reads.html)                             | Special feature that enables reading from any of the replicas | fast reads as the closest replica can be queried instead of the leaseholder, which can be in another region; no added storage cost | data can be slightly historical |
| [Follow-the-Workload](https://www.cockroachlabs.com/docs/stable/topology-follow-the-workload.html)                   | Default topology. Leaseholder moves automatically to the region where most of the queries originate | - | - |

## Labs Prerequisites

### Local Deployment

1. Build the dev cluster following [these instructions](https://dev.to/cockroachlabs/simulating-a-multi-region-cockroachdb-cluster-on-localhost-with-docker-59f6).

2. You also need:

    - a modern web browser,
    - a SQL client:
      - [Cockroach SQL client](https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux)
      - `psql`
      - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

### Shared Cluster Deployment

SSH into the Jumpbox using the IP address provided by the Instructor.

## Lab 0 - Create database and load data

### Local Deployment

Connect to any node and run the [workload simulator](https://www.cockroachlabs.com/docs/stable/cockroach-workload.html). Please note that loading the data can take up to 5 minutes.

```bash
docker exec -it roach-newyork-1 bash -c "./cockroach workload init movr --drop --db movr postgres://root@127.0.0.1:26257?sslmode=disable --num-histories 50000 --num-rides 50000 --num-users 1000 --num-vehicles 100"
```

Connect to the database to confirm it loaded successfully

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure -d movr

# or use the --url param for any another host:
# port mapping:
# 26257 --> us-west2 (Seattle)
# 26258 --> us-east4 (New York)
# 26259 --> eu-west2 (London)
cockroach sql --url "postgresql://localhost:26258/movr?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root movr
```

### Shared Cluster Deployment

Connect to the database

```bash
cockroach sql --insecure
```

At the SQL prompt, create your database by restoring a backup copy

```sql
CREATE DATABASE <your-name>;
USE <your-name>;
RESTORE movr.* FROM 's3://fabiog1901qq/movr?AUTH=implicit' WITH into_db = '<your-name>';
```

```text
        job_id       |  status   | fraction_completed |  rows  | index_entries |  bytes
---------------------+-----------+--------------------+--------+---------------+-----------
  636129471147835397 | succeeded |                  1 | 102100 |        100100 | 19724117
(1 row)

Time: 2.938s total (execution 2.938s / network 0.001s)
```

## Lab 1 - Explore Range distribution

Confirm data loaded successfully

```sql
SHOW TABLES;
```

```text
          table_name
------------------------------
  promo_codes
  rides
  user_promo_codes
  users
  vehicle_location_histories
  vehicles
(6 rows)

Time: 133.429ms
```

Open the DB Console at <http://localhost:8080>. Check the **Advanced Debug > Localities** page to see the localities associated with your nodes.

![localities](media/localities.png)

Also, you can see the distribution of your node using the **Map View**.

![map](media/map.png)

Now that you have imported the data, review how the ranges are distributed in the `rides` table. We create our own view to only project columns of interest. Feel free to modify as you see fit.

```sql
CREATE VIEW ridesranges AS
  SELECT SUBSTRING(start_key, 2, 15) AS start_key, SUBSTRING(end_key, 2, 15) AS end_key, lease_holder AS lh, lease_holder_locality, replicas, replica_localities
  FROM [SHOW RANGES FROM TABLE rides]
  WHERE start_key IS NOT NULL AND start_key NOT LIKE '%Prefix%';

SELECT * FROM ridesranges;
```

```text
     start_key    |     end_key     | lh | lease_holder_locality  | replicas |                              replica_localities
------------------+-----------------+----+------------------------+----------+-------------------------------------------------------------------------------
  "seattle"/"q\xc | "washington dc" |  1 | region=us-east4,zone=a | {1,6,7}  | {"region=us-east4,zone=a","region=us-west2,zone=b","region=eu-west2,zone=a"}
  "washington dc" | NULL            |  1 | region=us-east4,zone=a | {1,6,7}  | {"region=us-east4,zone=a","region=us-west2,zone=b","region=eu-west2,zone=a"}
  "amsterdam"/"\x | "boston"/"8\xe2 |  4 | region=us-west2,zone=a | {2,4,7}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "boston"/"8\xe2 | "los angeles"/" |  4 | region=us-west2,zone=a | {1,4,7}  | {"region=us-east4,zone=a","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "paris"/"\xe3\x | "san francisco" |  6 | region=us-west2,zone=b | {3,6,8}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=b"}
  "san francisco" | "seattle"/"q\xc |  6 | region=us-west2,zone=b | {3,6,7}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=a"}
  "los angeles"/" | "new york"/"\x1 |  7 | region=eu-west2,zone=a | {1,5,7}  | {"region=us-east4,zone=a","region=us-west2,zone=c","region=eu-west2,zone=a"}
  "new york"/"\x1 | "paris"/"\xe3\x |  7 | region=eu-west2,zone=a | {1,4,7}  | {"region=us-east4,zone=a","region=us-west2,zone=a","region=eu-west2,zone=a"}
```

Each range has been replicated in each region, check the `replicas` and `replica_localities` columns.

Review how indexes are distributed on the `movr.rides`

```sql
SHOW CREATE TABLE rides;
```

```text
 table_name |                                                        create_statement
------------+----------------------------------------------------------------------------------------------------------------------------------
 rides      | CREATE TABLE rides (
            |     id UUID NOT NULL,
            |     city VARCHAR NOT NULL,
            |     vehicle_city VARCHAR NULL,
            |     rider_id UUID NULL,
            |     vehicle_id UUID NULL,
            |     start_address VARCHAR NULL,
            |     end_address VARCHAR NULL,
            |     start_time TIMESTAMP NULL,
            |     end_time TIMESTAMP NULL,
            |     revenue DECIMAL(10,2) NULL,
            |     CONSTRAINT "primary" PRIMARY KEY (city ASC, id ASC),
            |     CONSTRAINT fk_city_ref_users FOREIGN KEY (city, rider_id) REFERENCES users(city, id),
            |     CONSTRAINT fk_vehicle_city_ref_vehicles FOREIGN KEY (vehicle_city, vehicle_id) REFERENCES vehicles(city, id),
            |     INDEX rides_auto_index_fk_city_ref_users (city ASC, rider_id ASC),
            |     INDEX rides_auto_index_fk_vehicle_city_ref_vehicles (vehicle_city ASC, vehicle_id ASC),
            |     FAMILY "primary" (id, city, vehicle_city, rider_id, vehicle_id, start_address, end_address, start_time, end_time, revenue),
            |     CONSTRAINT check_vehicle_city_city CHECK (vehicle_city = city)
            | )
```

Show ranges from one of the indexes

```sql
SHOW RANGES FROM INDEX rides_auto_index_fk_city_ref_users;
```

```text
  start_key | end_key | range_id | range_size_mb | lease_holder |   lease_holder_locality    | replicas |                                replica_localities
------------+---------+----------+---------------+--------------+----------------------------+----------+-----------------------------------------------------------------------------------
  NULL      | NULL    |      143 |      8.888912 |            9 | region=eu-west2,zone=c | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=c"}
```

Again, the index replicas are also spread across regions.

## Lab 2 - Geo-Partitioned Replicas

Read how you can tune the performance of the database using [partitioning](https://www.cockroachlabs.com/docs/stable/partitioning.html). You can read the docs about [configuring replication zones](https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html) with some examples [here](https://www.cockroachlabs.com/docs/stable/configure-replication-zones.html#create-a-replication-zone-for-a-partition).

Partition the `rides` table by column `city` to the appropriate regions (`us-west2`, `us-east4`, `eu-west2`).

```sql
ALTER TABLE rides PARTITION BY LIST (city) (
  PARTITION us_west2 VALUES IN ('los angeles', 'seattle', 'san francisco'),
  PARTITION us_east4 VALUES IN ('new york','boston', 'washington dc'),
  PARTITION eu_west2 VALUES IN ('paris','rome','amsterdam')
);
```

Confirm the partition job was successful

```sql
SHOW PARTITIONS FROM TABLE rides;
```

```text
  database_name | table_name | partition_name | parent_partition | column_names |  index_name   |                 partition_value                 | zone_config |       full_zone_config
----------------+------------+----------------+------------------+--------------+---------------+-------------------------------------------------+-------------+-------------------------------
  movr          | rides      | us_west2       | NULL             | city         | rides@primary | ('los angeles'), ('seattle'), ('san francisco') | NULL        | range_min_bytes = 134217728,
                |            |                |                  |              |               |                                                 |             | range_max_bytes = 536870912,
                |            |                |                  |              |               |                                                 |             | gc.ttlseconds = 90000,
                |            |                |                  |              |               |                                                 |             | num_replicas = 3,
                |            |                |                  |              |               |                                                 |             | constraints = '[]',
                |            |                |                  |              |               |                                                 |             | lease_preferences = '[]'
  movr          | rides      | us_east4       | NULL             | city         | rides@primary | ('new york'), ('boston'), ('washington dc')     | NULL        | range_min_bytes = 134217728,
                |            |                |                  |              |               |                                                 |             | range_max_bytes = 536870912,
                |            |                |                  |              |               |                                                 |             | gc.ttlseconds = 90000,
                |            |                |                  |              |               |                                                 |             | num_replicas = 3,
                |            |                |                  |              |               |                                                 |             | constraints = '[]',
                |            |                |                  |              |               |                                                 |             | lease_preferences = '[]'
  movr          | rides      | eu_west2       | NULL             | city         | rides@primary | ('paris'), ('rome'), ('amsterdam')              | NULL        | range_min_bytes = 134217728,
                |            |                |                  |              |               |                                                 |             | range_max_bytes = 536870912,
                |            |                |                  |              |               |                                                 |             | gc.ttlseconds = 90000,
                |            |                |                  |              |               |                                                 |             | num_replicas = 3,
                |            |                |                  |              |               |                                                 |             | constraints = '[]',
                |            |                |                  |              |               |                                                 |             | lease_preferences = '[]'
```

Perfect! Let us assume we have a regulatory EU requirement that imposes EU data to stay within the EU (inluding the UK).
Currently we are not compliant as Rome, Paris and Amsterdam data is replicated in the US East and US West regions.

With the [Geo-Partitioned Replicas](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-replicas.html) topology pattern, we can pin all replicas to a particular region/area.

Pros:

- fast read and writes from in-region requests
- Able to comply with legal regulations.

Cons:

- As data is pinned to a single region we can't survive region failure or we need a more complex setup (e.g: more regions within the same country)

Pinning data to nodes is very easy, it all depends on what labels you passed to the `--locality` flag when you run the CockroachDB process.
For our cluster, we passed `--locality=region=eu-west2,zone=a|b|c` so we will use `region` to pin partitions to the correct place.

The `lease_preferences` will be set to the target region and the `constaints` will be set to place **all** replicas in the same region as the leaseholder.

```sql
ALTER PARTITION eu_west2 OF INDEX rides@*
CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{"+region=eu-west2"}',
  lease_preferences = '[[+region=eu-west2]]';
```

After few minutes, verify all replicas for the European cities are in the `eu-west2` region

```sql
SELECT * FROM ridesranges;
```

```text
     start_key    |     end_key     | lh | lease_holder_locality  | replicas |                              replica_localities
------------------+-----------------+----+------------------------+----------+-------------------------------------------------------------------------------
  "boston"/"8\xe2 | "los angeles"/" |  2 | region=us-east4,zone=c | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=a","region=eu-west2,zone=c"}
  "los angeles"/" | "new york"/"\x1 |  2 | region=us-east4,zone=c | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=a","region=eu-west2,zone=c"}
  "new york"/"\x1 | "paris"         |  2 | region=us-east4,zone=c | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=a","region=eu-west2,zone=c"}
  "washington dc" | NULL            |  4 | region=us-west2,zone=a | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=a","region=eu-west2,zone=c"}
  "amsterdam"     | "amsterdam"/"\x |  7 | region=eu-west2,zone=a | {7,8,9}  | {"region=eu-west2,zone=a","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "amsterdam"/"\x | "amsterdam"/Pre |  7 | region=eu-west2,zone=a | {7,8,9}  | {"region=eu-west2,zone=a","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "san francisco" | "seattle"/"q\xc |  7 | region=eu-west2,zone=a | {2,4,7}  | {"region=us-east4,zone=c","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "paris"         | "paris"/"\xe3\x |  8 | region=eu-west2,zone=c | {7,8,9}  | {"region=eu-west2,zone=a","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "paris"/"\xe3\x | "paris"/PrefixE |  8 | region=eu-west2,zone=c | {7,8,9}  | {"region=eu-west2,zone=a","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "rome"          | "rome"/PrefixEn |  8 | region=eu-west2,zone=c | {7,8,9}  | {"region=eu-west2,zone=a","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "seattle"/"q\xc | "washington dc" |  8 | region=eu-west2,zone=c | {3,4,8}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=c"}
```

As expected! European cities are pinned to region `eu-west2` - a tag you passed when you create the cluster. You can have multiple layer of tags (area/region/zone/datacenter) for a finer control on where you'd like to pin your data. Let Geo-Partitioned Replicas help you comply with your legal requirements for data locality and regulation like GDPR. You can read more on our [blog](https://www.cockroachlabs.com/blog/gdpr-compliance-for-my-database/).

### What you can survive

Check the `replica_localities`: with the above configuration, you can survive the region failure of either `us-west2` or `us-east4` and you'd still have enough replicas to keep your database running.
As all replicas of the European cities are located in region `eu-west2`, a loss of that region will make the European cities data unavailable, however, you can tolerate the loss of a region **zone**. Either case, you would still be able to access US cities data.

## Lab 3 - Geo-Partitioned Leaseholders

In this lab, we implement the [Geo Partitioned Leaseholder](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-leaseholders.html) topology pattern, where we pin the leaseholder to the region to match the cities, as we anticipate majority of the queries involving these cities originate from the region itself.

Pros:

- fast read response from in-region reads
- we can still tolerate a region failure.

Cons:

- slower writes as leaseholder has to reach to other regions for quorum.

The `lease_preferences` will be set to the target region and the `constaints` will be set to require **one** replica in the same region as the leaseholder.

```sql
ALTER PARTITION us_west2 OF INDEX rides@*
CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{"+region=us-west2":1}',
  lease_preferences = '[[+region=us-west2]]';

ALTER PARTITION us_east4 OF INDEX rides@*
CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{"+region=us-east4":1}',
  lease_preferences = '[[+region=us-east4]]';  

ALTER PARTITION eu_west2 OF INDEX rides@*
CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{"+region=eu-west2":1}',
  lease_preferences = '[[+region=eu-west2]]';  
```

This job will take about 5 minutes to complete, as ranges are shuffled around the cluster to land on the requested `ZONE` i.e. region.

Review how the ranges are distributed in the `rides` table after pinning. Confirm the leaseholder for each city is in the same region of the city itself.
  
```sql
SELECT * FROM ridesranges;
```

```text
     start_key    |     end_key     | lh | lease_holder_locality  | replicas |                              replica_localities
------------------+-----------------+----+------------------------+----------+-------------------------------------------------------------------------------
  "new york"      | "new york"/"\x1 |  1 | region=us-east4,zone=a | {1,5,7}  | {"region=us-east4,zone=a","region=us-west2,zone=c","region=eu-west2,zone=a"}
  "washington dc" | "washington dc" |  1 | region=us-east4,zone=a | {1,6,7}  | {"region=us-east4,zone=a","region=us-west2,zone=b","region=eu-west2,zone=a"}
  "boston"        | "boston"/"8\xe2 |  2 | region=us-east4,zone=b | {2,4,7}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "boston"/"8\xe2 | "boston"/Prefix |  2 | region=us-east4,zone=b | {2,4,7}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "new york"/"\x1 | "new york"/Pref |  2 | region=us-east4,zone=b | {2,4,7}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "washington dc" | "washington dc" |  2 | region=us-east4,zone=b | {2,6,7}  | {"region=us-east4,zone=b","region=us-west2,zone=b","region=eu-west2,zone=a"}
  
  "los angeles"   | "los angeles"/" |  4 | region=us-west2,zone=a | {1,4,7}  | {"region=us-east4,zone=a","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "los angeles"/" | "los angeles"/P |  5 | region=us-west2,zone=c | {1,5,7}  | {"region=us-east4,zone=a","region=us-west2,zone=c","region=eu-west2,zone=a"}
  "san francisco" | "san francisco" |  6 | region=us-west2,zone=b | {3,6,8}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=b"}
  "san francisco" | "san francisco" |  6 | region=us-west2,zone=b | {3,6,7}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=a"}
  "seattle"       | "seattle"/"q\xc |  6 | region=us-west2,zone=b | {3,6,7}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=a"}
  "seattle"/"q\xc | "seattle"/Prefi |  6 | region=us-west2,zone=b | {1,6,7}  | {"region=us-east4,zone=a","region=us-west2,zone=b","region=eu-west2,zone=a"}
  
  "amsterdam"     | "amsterdam"/"\x |  7 | region=eu-west2,zone=a | {1,4,7}  | {"region=us-east4,zone=a","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "paris"         | "paris"/"\xe3\x |  7 | region=eu-west2,zone=a | {1,4,7}  | {"region=us-east4,zone=a","region=us-west2,zone=a","region=eu-west2,zone=a"}
  "paris"/"\xe3\x | "paris"/PrefixE |  8 | region=eu-west2,zone=b | {3,6,8}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=b"}
  "rome"          | "rome"/PrefixEn |  8 | region=eu-west2,zone=b | {3,6,8}  | {"region=us-east4,zone=c","region=us-west2,zone=b","region=eu-west2,zone=b"}
  "amsterdam"/"\x | "amsterdam"/Pre |  9 | region=eu-west2,zone=c | {2,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=c"}
```

Good, as expected! The leaseholder is now located in the same region the cities belong to. Let's see next what happens when we run queries against each region.

Experiment running the same queries in **all** regions and observe the **Time**, printed at the bottom.

Open 2 more terminals and connect with separate SQL connections to each region.  Run the following queries in each (in this example, I only show the result from the `us-east4` node, **New York**).

Please note, you might need to run the queries a few times before you get the expected latency as the gateway node has to refresh the metadata table with the addresses of the leaseholders for the range requested.

```sql
-- confirm location for the current node
SHOW LOCALITY;
-- query data from other regions will incur latency as the leaseholders are in the other regions
SELECT id, start_address, 'us-west2' AS region FROM rides WHERE city = 'seattle' LIMIT 1;
SELECT id, start_address, 'us-east4' as region FROM rides WHERE city = 'new york' LIMIT 1;
SELECT id, start_address, 'eu-west2' AS region FROM rides WHERE city = 'rome' LIMIT 1;
```

```text
         locality
--------------------------
  region=us-east4,zone=a
(1 row)

Time: 1.847ms

                   id                  |        start_address        |  region
---------------------------------------+-----------------------------+-----------
  5555c52e-72da-4400-8000-00000000411b | 25783 Kelly Fields Suite 75 | us-west2
(1 row)

Time: 67.662ms

                   id                  |    start_address     |  region
---------------------------------------+----------------------+-----------
  00000000-0000-4000-8000-000000000000 | 99176 Anderson Mills | us-east4
(1 row)

Time: 1.921ms

                   id                  |   start_address    |  region
---------------------------------------+--------------------+-----------
  e38ef34d-6a16-4000-8000-00000000ad9d | 12651 Haley Square | eu-west2
(1 row)

Time: 128.969ms
```

As expected, we get fast responses when we query local data, but the delay is noticeable when the gateway node has to reach out to leaseholders in other regions to get their data.

Connect to the DB Console and go to the **Network Latency** tab on the left. Compare the latency measured with your findings running SQL queries.

With the Geo-Partitioned Leaseholders topology you were able to achieve fast local reads and still be able to survive a region failure.

### What you can survive

Check the `replica_localities`: as you have a replica of each range in each region, you can survive a region failure and still be in business.

## Lab 4 - Follower Reads

With [Follower Reads](https://www.cockroachlabs.com/docs/stable/topology-follower-reads.html), you can get fast response times on reads from any of the replicas.

Pros:

- fast response time if any of the replicas is local - no need to reach out to the leaseholder
- no need to duplicate data, e.g. duplicate indexes

Cons:

- data is slightly historical

There are 2 ways to use the Follower Reads functionality: the first is by using `follower_read_timestamp()`. Run these queries on all your regions:

```sql
SHOW LOCALITY;

SELECT id, start_address, 'us-west2' as region
FROM rides AS OF SYSTEM TIME follower_read_timestamp()
WHERE city = 'seattle' LIMIT 1;

SELECT id, start_address, 'us-east4' as region
FROM rides AS OF SYSTEM TIME follower_read_timestamp()
WHERE city = 'new york' LIMIT 1;

SELECT id, start_address, 'eu-west2' as region
FROM rides AS OF SYSTEM TIME follower_read_timestamp()
WHERE city = 'rome' LIMIT 1;
```

```text
         locality
--------------------------
  region=us-east4,zone=b
(1 row)

Time: 2.47ms

                   id                  |        start_address        |  region
---------------------------------------+-----------------------------+-----------
  5555c52e-72da-4400-8000-00000000411b | 25783 Kelly Fields Suite 75 | us-west2
(1 row)

Time: 1.933ms

                   id                  |    start_address     |  region
---------------------------------------+----------------------+-----------
  00000000-0000-4000-8000-000000000000 | 99176 Anderson Mills | us-east4
(1 row)

Time: 2.546ms

                   id                  |   start_address    |  region
---------------------------------------+--------------------+-----------
  e38ef34d-6a16-4000-8000-00000000ad9d | 12651 Haley Square | eu-west2
(1 row)

Time: 1.896ms
```

The second way is by explicitly setting a time interval using `AS OF SYSTEM TIME INTERVAL '-1m'`

```sql
SHOW LOCALITY;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1m'
WHERE city = 'seattle' LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1m'
WHERE city = 'new york' LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1m'
WHERE city = 'rome' LIMIT 1;
```

You should see that the response times for each city is comparable to the local city response time (single digit ms response time). What is happening, the database is querying the local replica of that range - remember each region has a replica of every range.

Try using with an interval of `-2s`. Response times will go back the same as prior to using Follower Reads. This is because the time interval is not long enough to pickup the copy at that interval and the query is therefore routed to the leaseholder.

You can use `AS OF SYSTEM TIME follower_read_timestamp()` to ensure Follower Reads queries use local ranges with the least time lag.

With the Follower Read topology, albeit slightly historical, you get fast reads cheaply. This is ideal for some scheduled reporting, for examples, sales in the past hour/minutes, etc.

## Lab 5 - Duplicate Indexes

Run the following query in every regions:

```sql
SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='seattle'
GROUP BY 1,2;

SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='new york'
GROUP BY 1,2;

SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='rome'
GROUP BY 1,2;
```

```text
  vehicle_city |              vehicle_id              | count
---------------+--------------------------------------+--------
  seattle      | 570a3d70-a3d7-4c00-8000-000000000022 |   537
  seattle      | 6147ae14-7ae1-4800-8000-000000000026 |   507
  seattle      | 6b851eb8-51eb-4400-8000-00000000002a |   491
  seattle      | 66666666-6666-4800-8000-000000000028 |   492
  seattle      | 68f5c28f-5c28-4400-8000-000000000029 |   549
  seattle      | 59999999-9999-4800-8000-000000000023 |   505
  seattle      | 63d70a3d-70a3-4800-8000-000000000027 |   493
  seattle      | 5c28f5c2-8f5c-4800-8000-000000000024 |   465
  seattle      | 5eb851eb-851e-4800-8000-000000000025 |   515
  seattle      | 6e147ae1-47ae-4400-8000-00000000002b |   503
  seattle      | 70a3d70a-3d70-4400-8000-00000000002c |   499
(11 rows)

Time: 72.714ms

  vehicle_city |              vehicle_id              | count
---------------+--------------------------------------+--------
  new york     | 19999999-9999-4a00-8000-00000000000a |   445
  new york     | 170a3d70-a3d7-4a00-8000-000000000009 |   461
  new york     | 147ae147-ae14-4b00-8000-000000000008 |   459
  new york     | 051eb851-eb85-4ec0-8000-000000000002 |   486
  new york     | 0ccccccc-cccc-4d00-8000-000000000005 |   480
  new york     | 1c28f5c2-8f5c-4900-8000-00000000000b |   430
  new york     | 028f5c28-f5c2-4f60-8000-000000000001 |   474
  new york     | 0a3d70a3-d70a-4d80-8000-000000000004 |   455
  new york     | 0f5c28f5-c28f-4c00-8000-000000000006 |   478
  new york     | 07ae147a-e147-4e00-8000-000000000003 |   461
  new york     | 00000000-0000-4000-8000-000000000000 |   470
  new york     | 11eb851e-b851-4c00-8000-000000000007 |   457
(12 rows)

Time: 8.811ms

  vehicle_city |              vehicle_id              | count
---------------+--------------------------------------+--------
  rome         | e3d70a3d-70a3-4800-8000-000000000059 |   488
  rome         | ee147ae1-47ae-4800-8000-00000000005d |   517
  rome         | fd70a3d7-0a3d-4000-8000-000000000063 |   540
  rome         | e6666666-6666-4800-8000-00000000005a |   482
  rome         | f0a3d70a-3d70-4000-8000-00000000005e |   481
  rome         | eb851eb8-51eb-4800-8000-00000000005c |   507
  rome         | e8f5c28f-5c28-4800-8000-00000000005b |   498
  rome         | f3333333-3333-4000-8000-00000000005f |   498
  rome         | f5c28f5c-28f5-4000-8000-000000000060 |   505
  rome         | fae147ae-147a-4000-8000-000000000062 |   519
  rome         | f851eb85-1eb8-4000-8000-000000000061 |   520
(11 rows)

Time: 131.337ms
```

As expected, you get slow responses from queries that have to fetch data from other regions. You can use the [Duplicate Indexes](https://www.cockroachlabs.com/docs/stable/topology-duplicate-indexes.html) topology to get fast response times on reads.

Pros:

- Fast response time for reads
- unlike with Follower Reads, data is the latest

Cons:

- slightly slower writes as more indexes have to be updated
- more storage used as indexes create duplicate data

Create 3 indexes, one for each region.

```sql
CREATE index idx_us_west_rides ON rides(city) STORING (vehicle_city, vehicle_id);
CREATE index idx_us_east_rides ON rides(city) STORING (vehicle_city, vehicle_id);
CREATE index idx_eu_west_rides ON rides(city) STORING (vehicle_city, vehicle_id);
```

We then pin one index leaseholder per region - this enables fast reads.

```sql
ALTER INDEX idx_us_west_rides CONFIGURE ZONE USING
      num_replicas = 3,
      constraints = '{+region=us-west2: 1}',
      lease_preferences = '[[+region=us-west2]]';

ALTER INDEX idx_us_east_rides CONFIGURE ZONE USING
      num_replicas = 3,
      constraints = '{+region=us-east4: 1}',
      lease_preferences = '[[+region=us-east4]]';

ALTER INDEX idx_eu_west_rides CONFIGURE ZONE USING
      num_replicas = 3,
      constraints = '{+region=eu-west2: 1}',
      lease_preferences = '[[+region=eu-west2]]';
```

Wait few minutes for the new indexes ranges to shuffle to the right regions.

Run the queries again, always on all 3 regions. The response times should be similar across all regions for all cities.

```sql
SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='seattle'
GROUP BY 1,2;

SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='new york'
GROUP BY 1,2;

SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='rome'
GROUP BY 1,2;
```

```text
  vehicle_city |              vehicle_id              | count
---------------+--------------------------------------+--------
  seattle      | 6b851eb8-51eb-4400-8000-00000000002a |   491
  seattle      | 66666666-6666-4800-8000-000000000028 |   492
  seattle      | 6147ae14-7ae1-4800-8000-000000000026 |   507
  seattle      | 5eb851eb-851e-4800-8000-000000000025 |   515
  seattle      | 68f5c28f-5c28-4400-8000-000000000029 |   549
  seattle      | 59999999-9999-4800-8000-000000000023 |   505
  seattle      | 63d70a3d-70a3-4800-8000-000000000027 |   493
  seattle      | 5c28f5c2-8f5c-4800-8000-000000000024 |   465
  seattle      | 570a3d70-a3d7-4c00-8000-000000000022 |   537
  seattle      | 6e147ae1-47ae-4400-8000-00000000002b |   503
  seattle      | 70a3d70a-3d70-4400-8000-00000000002c |   499
(11 rows)

Time: 8.182ms

  vehicle_city |              vehicle_id              | count
---------------+--------------------------------------+--------
  new york     | 07ae147a-e147-4e00-8000-000000000003 |   461
  new york     | 00000000-0000-4000-8000-000000000000 |   470
  new york     | 1c28f5c2-8f5c-4900-8000-00000000000b |   430
  new york     | 0ccccccc-cccc-4d00-8000-000000000005 |   480
  new york     | 028f5c28-f5c2-4f60-8000-000000000001 |   474
  new york     | 19999999-9999-4a00-8000-00000000000a |   445
  new york     | 170a3d70-a3d7-4a00-8000-000000000009 |   461
  new york     | 0a3d70a3-d70a-4d80-8000-000000000004 |   455
  new york     | 147ae147-ae14-4b00-8000-000000000008 |   459
  new york     | 0f5c28f5-c28f-4c00-8000-000000000006 |   478
  new york     | 051eb851-eb85-4ec0-8000-000000000002 |   486
  new york     | 11eb851e-b851-4c00-8000-000000000007 |   457
(12 rows)

Time: 7.377ms

  vehicle_city |              vehicle_id              | count
---------------+--------------------------------------+--------
  rome         | f0a3d70a-3d70-4000-8000-00000000005e |   481
  rome         | eb851eb8-51eb-4800-8000-00000000005c |   507
  rome         | e8f5c28f-5c28-4800-8000-00000000005b |   498
  rome         | e3d70a3d-70a3-4800-8000-000000000059 |   488
  rome         | f3333333-3333-4000-8000-00000000005f |   498
  rome         | fd70a3d7-0a3d-4000-8000-000000000063 |   540
  rome         | e6666666-6666-4800-8000-00000000005a |   482
  rome         | ee147ae1-47ae-4800-8000-00000000005d |   517
  rome         | f5c28f5c-28f5-4000-8000-000000000060 |   505
  rome         | fae147ae-147a-4000-8000-000000000062 |   519
  rome         | f851eb85-1eb8-4000-8000-000000000061 |   520
(11 rows)

Time: 6.767ms
```

Great! Use `EXPLAIN` to confirm that the optimizer is using the index whose leaseholder is local to the region.

In below example, we are in the US East region and the optimizer is leveraging the `idx_us_east_rides` index to retrieve Rome data.

```sql
SHOW LOCALITY;

EXPLAIN SELECT vehicle_city, vehicle_id, COUNT(*)
FROM rides
WHERE city='rome'
GROUP BY 1,2;
```

```text
         locality
--------------------------
  region=us-east4,zone=a
(1 row)

Time: 2.115ms

       tree      |    field    |        description
-----------------+-------------+----------------------------
                 | distributed | true
                 | vectorized  | false
  group          |             |
   │             | aggregate 0 | vehicle_city
   │             | aggregate 1 | vehicle_id
   │             | aggregate 2 | count_rows()
   │             | group by    | vehicle_city, vehicle_id
   └── render    |             |
        └── scan |             |
                 | table       | rides@idx_us_east_rides
                 | spans       | /"rome"-/"rome"/PrefixEnd
```

You can always check the index ranges to find out where the leaseholder is located

```sql
SHOW RANGES FROM INDEX idx_us_east_rides;
```

```text
  start_key | end_key | range_id | range_size_mb | lease_holder | lease_holder_locality  | replicas |                                replica_localities
------------+---------+----------+---------------+--------------+------------------------+----------+-----------------------------------------------------------------------------------
  NULL      | NULL    |      141 |      4.244041 |            3 | region=us-east4,zone=b | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=c"}
(1 row)
```

Check the `lease_holder_locality` column, the index is local! We can now delete the indexes

```sql
DROP INDEX idx_us_west_rides;
DROP INDEX idx_us_east_rides;
DROP INDEX idx_eu_west_rides;
```

The Duplicate Indexes topology is ideal for data that is used very frequently (for joins for example) but doesn't change much. Think ZIP codes, national IDs, warehouse location information, etc..

## Lab 6 - Survive region failure and scale out

Suppose we have a deployment such that:

- our main region is US West and most of our queries go through that region.
- The leaseholder is local, and thus
- reads are very fast
- writes, while the `eu-west2` region is far (180ms roundtrip), region `us-east4` is relatively close (60ms roundtrip) so the Raft consensus quorum is achieved as soon as the replica in `us-east4` confirms.

Imagine that region `us-west2` becomes unavailable due to a power outage:

- Networking is such that traffic from US West clients must be routed to EU West - 180ms roundtrip.
- The node in EU West realizes the leaseholder for the range the client is querying has moved to US East: 125ms roundtrip.
- the leaseholder node in US East seek for Raft consensus from the EU West replica: 125ms rountrip.

The total latency for the query is 180 + 125 + 125 = 430ms. To temporarely remedy this problem and decrease the overall response time, we have 2 options:

- move all former US West ranges from region US East to region EU West - but that means we can't survive if EU West goes down as we'd have all replicas in that region;
- scale out the Cockroach cluster and deploy nodes on a **new** datacenter close to EU West, so that the Raft consensus is achieved quicker and we can still survive another region failure.

In this lab we decide for the second option, being the safest. First, reduce the time CRDB considers nodes dead down from 5 to 1.15 minutes, the lowest.

```sql
SET CLUSTER SETTING server.time_until_store_dead = '75s';
```

Simulate region failure. Ensure to run all following `docker` commands on a new terminal, on localhost.

```bash
docker stop haproxy-seattle roach-seattle-1 roach-seattle-2 roach-seattle-3
```

Check the DB Console: the website is down as the node that serves port 8080 died. **Use port 8180 instead**.

In a little over a minute, 3 nodes will be set to **Dead**, and CockroachDB will start replicating the ranges into the remaining regions.

![dead-nodes](media/dead-nodes.png)

```sql
SELECT * FROM ridesranges;
```

```text
     start_key    |     end_key     | lh | lease_holder_locality  | replicas |                              replica_localities
------------------+-----------------+----+------------------------+----------+-------------------------------------------------------------------------------
  "los angeles"   | "los angeles"/" |  1 | region=us-east4,zone=a | {1,8,9}  | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "san francisco" | "san francisco" |  2 | region=us-east4,zone=b | {2,7,8}  | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-west2,zone=c"}
  "seattle"/"q\xc | "seattle"/Prefi |  2 | region=us-east4,zone=b | {2,3,9}  | {"region=us-east4,zone=b","region=us-east4,zone=c","region=eu-west2,zone=b"}
  "washington dc" | "washington dc" |  2 | region=us-east4,zone=b | {2,3,9}  | {"region=us-east4,zone=b","region=us-east4,zone=c","region=eu-west2,zone=b"}
  "boston"        | "boston"/"8\xe2 |  3 | region=us-east4,zone=c | {3,8,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "boston"/"8\xe2 | "boston"/Prefix |  3 | region=us-east4,zone=c | {3,8,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "los angeles"/" | "los angeles"/P |  3 | region=us-east4,zone=c | {3,7,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-west2,zone=b"}
  "new york"      | "new york"/"\x1 |  3 | region=us-east4,zone=c | {3,7,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-west2,zone=b"}
  "new york"/"\x1 | "new york"/Pref |  3 | region=us-east4,zone=c | {1,3,9}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=b"}
  "washington dc" | "washington dc" |  3 | region=us-east4,zone=c | {3,8,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "paris"/"\xe3\x | "paris"/PrefixE |  7 | region=eu-west2,zone=a | {1,2,7}  | {"region=us-east4,zone=a","region=us-east4,zone=b","region=eu-west2,zone=a"}
  "seattle"       | "seattle"/"q\xc |  7 | region=eu-west2,zone=a | {1,2,7}  | {"region=us-east4,zone=a","region=us-east4,zone=b","region=eu-west2,zone=a"}
  "amsterdam"     | "amsterdam"/"\x |  8 | region=eu-west2,zone=c | {3,8,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-west2,zone=b"}
  "paris"         | "paris"/"\xe3\x |  8 | region=eu-west2,zone=c | {3,7,8}  | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-west2,zone=c"}
  "rome"          | "rome"/PrefixEn |  8 | region=eu-west2,zone=c | {1,3,8}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=c"}
  "amsterdam"/"\x | "amsterdam"/Pre |  9 | region=eu-west2,zone=b | {1,3,9}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=b"}
  "san francisco" | "san francisco" |  9 | region=eu-west2,zone=b | {3,8,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-west2,zone=b"}
```

From above table we can see that the US West data was successfully and evenly replicated to across the remaining regions.

Create a new running docker container using the `cockroachdb` image. This will be our SQL client app connecting from Seattle.

```bash
docker run -d --name=seattle-client --hostname=seattle-client --cap-add NET_ADMIN --net=us-west2-net crdb start --insecure --join=fake1,fake2,fake3

# add network connections and latency to seattle-client
docker network connect uswest-useast-net seattle-client
docker network connect uswest-euwest-net seattle-client
docker exec seattle-client tc qdisc add dev eth1 root netem delay 30ms
docker exec seattle-client tc qdisc add dev eth2 root netem delay 90ms

# Connect
docker exec -it seattle-client bash
```

From within `seattle-client`, connect to the database in London.

```bash
cockroach sql --url "postgresql://roach-london-1:26257/movr?sslmode=disable"  
```

Verify you see the ~180ms lantecy to EU West region. Please note that for this simple case, we connect to a cluster node instead of the HAProxy.

```sql
SHOW LOCALITY;
```

```text
         locality
--------------------------
  region=eu-west2,zone=a
(1 row)

Time: 182.096ms
```

Very good, you can now simulate an App in Seattle that is routed to the London endpoint due to the unavailable US West region.

Reading Seattle data will incur the client roundtrip from US West to EU West, ~180ms, plus the roundtrip from EU West to US East (~125ms) for the leaseholder read for a total of ~305ms.

```sql
-- Please note: depending on how your cluster replicated the ranges
-- you might not be able to replicate the result for below commands.
-- I thus suggest you just read along.
SELECT * FROM rides WHERE city = 'seattle' LIMIT 1;
```

```text
                   id                  |  city   | vehicle_city |               rider_id               |              vehicle_id              |    start_address    |    end_address    |        start_time         |         end_time          | revenue
---------------------------------------+---------+--------------+--------------------------------------+--------------------------------------+---------------------+-------------------+---------------------------+---------------------------+----------
  5555c52e-72da-4400-8000-00000000411b | seattle | seattle      | 63958106-24dd-4000-8000-000000000185 | 6147ae14-7ae1-4800-8000-000000000026 | Cockroach Street 50 | 65529 Krystal Via | 2018-12-04 03:04:05+00:00 | 2018-12-04 04:04:05+00:00 |   22.00
(1 row)

Time: 305.2899ms
```

As expected. Let us test with write operations: from the range table we see that

- both Seattle and Los Angeles ranges have the leaseholder in US East
- Seattle replicas are
  - 2 in US East
  - 1 in EU West
- Los Angeles replicas are
  - 1 in US East
  - 2 in EU West  

So we can expect the latency for an `INSERT` to be

- for Seattle: client roundtrip 180ms + gateway-leaseholder roundtrip 125ms = ~305ms. As the closest replica is in the same region of the leaseholder, Raft consensus is achived in single digit millis.
- for Los Angeles: client roundtrip 180ms + gateway-leaseholder roundtrip 125ms + Raft consensus 125ms = ~430ms. As the closest replica is in another region, you need to factor that latency in.

```sql
-- Please note: depending on how your cluster replicated the ranges
-- you might not be able to replicate the result for below commands.
-- I thus suggest you just read along.
INSERT INTO rides VALUES (gen_random_uuid(), 'seattle', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO rides VALUES (gen_random_uuid(), 'los angeles', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
```

```text
INSERT 1

Time: 309.8142ms
INSERT 1

Time: 430.9846ms
```

Cool! You can always check the replicas location for a key as follows:

```sql
SHOW RANGE FROM TABLE rides FOR ROW ('put-uuid-here', 'seattle', null, null, null, null,null, null,null, null);
SHOW RANGE FROM TABLE rides FOR ROW ('5555c52e-72da-4400-8888-000000135882', 'los angeles', null, null, null, null,null, null,null, null);
```

```text
  start_key  |                            end_key                             | range_id | lease_holder | lease_holder_locality  | replicas |                              replica_localities
-------------+----------------------------------------------------------------+----------+--------------+------------------------+----------+-------------------------------------------------------------------------------
  /"seattle" | /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc" |       75 |            1 | region=us-east4,zone=a | {1,3,9}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=c"}
(1 row)

Time: 1.8095131s

    start_key    |                              end_key                               | range_id | lease_holder | lease_holder_locality  | replicas |                              replica_localities
-----------------+--------------------------------------------------------------------+----------+--------------+------------------------+----------+-------------------------------------------------------------------------------
  /"los angeles" | /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822" |       73 |            1 | region=us-east4,zone=a | {1,8,9}  | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-west2,zone=c"}
(1 row)

Time: 1.7808906s
```

We now understand the ramification of a failed region and the toll it takes on the overall latency. We understand that region US West will take several hours to become operational again and we decide to remedy by scaling out the cluster, also because we are afraid another region might go down and the Cockroach cluster would become unavailable, too, as quorum can't be reached with only 1 out of 3 ranges being available.

Provision the datacenter in Frankfurt, Germany. We call this region EU Central

```bash
# create local network eu-central-net
docker network create --driver=bridge --subnet=172.26.0.0/16 --ip-range=172.26.0.0/24 --gateway=172.26.0.1 eu-central-net

# create inter-regional networks
docker network create --driver=bridge --subnet=172.33.0.0/16 --ip-range=172.33.0.0/24 --gateway=172.33.0.1 useast-eucentral-net
docker network create --driver=bridge --subnet=172.34.0.0/16 --ip-range=172.34.0.0/24 --gateway=172.34.0.1 euwest-eucentral-net

# create 3 nodes in Frankfurt - no need for HAProxy...
docker run -d --name=roach-frankfurt-1 --hostname=roach-frankfurt-1 --ip=172.26.0.11 --cap-add NET_ADMIN --net=eu-central-net --add-host=roach-frankfurt-1:172.26.0.11 --add-host=roach-frankfurt-2:172.26.0.12 --add-host=roach-frankfurt-3:172.26.0.13 -p 8480:8080 -v "roach-frankfurt-1-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-central,zone=a
docker run -d --name=roach-frankfurt-2 --hostname=roach-frankfurt-2 --ip=172.26.0.12 --cap-add NET_ADMIN --net=eu-central-net --add-host=roach-frankfurt-1:172.26.0.11 --add-host=roach-frankfurt-2:172.26.0.12 --add-host=roach-frankfurt-3:172.26.0.13 -p 8481:8080 -v "roach-frankfurt-2-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-central,zone=b
docker run -d --name=roach-frankfurt-3 --hostname=roach-frankfurt-3 --ip=172.26.0.13 --cap-add NET_ADMIN --net=eu-central-net --add-host=roach-frankfurt-1:172.26.0.11 --add-host=roach-frankfurt-2:172.26.0.12 --add-host=roach-frankfurt-3:172.26.0.13 -p 8482:8080 -v "roach-frankfurt-3-data:/cockroach/cockroach-data" crdb start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-central,zone=c

# attach networks and add latency
# Frankfurt
for j in 1 2 3
do
    docker network connect useast-eucentral-net roach-frankfurt-$j
    docker network connect euwest-eucentral-net roach-frankfurt-$j
    docker exec roach-frankfurt-$j tc qdisc add dev eth1 root netem delay 62ms
    docker exec roach-frankfurt-$j tc qdisc add dev eth2 root netem delay 5ms
done
# New York
for j in 1 2 3
do
    docker network connect useast-eucentral-net roach-newyork-$j
    docker exec roach-newyork-$j tc qdisc add dev eth3 root netem delay 59ms
done
# London
for j in 1 2 3
do
    docker network connect euwest-eucentral-net roach-london-$j
    docker exec roach-london-$j tc qdisc add dev eth3 root netem delay 5ms
done
```

Update the location map with the geo location for our new region

```sql
INSERT into system.locations VALUES ('region', 'eu-central', 50.110922, 8.682127);
```

Check the DB Console: slowly, you should see the live nodes increasing from 6 to 9. If you refresh the map, you should see the Frankfurt datacenter.

![eu-central-map](media/eu-central-map.png)

Confirm the latency in the Network Latency page is ~12ms between London and Frankfurt, and ~120ms between Frankfurt and NY.

![eu-central-latency](media/eu-central-latency.png)

Ranges have been automatically shuffled around to the new datacenter. Check what it looks like:

```sql
SELECT * FROM ridesranges;
```

```text
     start_key    |     end_key     | lh |  lease_holder_locality   | replicas |                               replica_localities
------------------+-----------------+----+--------------------------+----------+---------------------------------------------------------------------------------
  "new york"/"\x1 | "new york"/Pref |  1 | region=us-east4,zone=a   | {1,9,11} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  "boston"        | "boston"/"8\xe2 |  3 | region=us-east4,zone=c   | {3,9,11} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=a"}
  "boston"/"8\xe2 | "boston"/Prefix |  3 | region=us-east4,zone=c   | {3,9,10} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=c"}
  "new york"      | "new york"/"\x1 |  3 | region=us-east4,zone=c   | {3,7,11} | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-central,zone=a"}
  "washington dc" | "washington dc" |  3 | region=us-east4,zone=c   | {3,9,10} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=c"}
  "washington dc" | "washington dc" |  3 | region=us-east4,zone=c   | {3,8,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  "paris"         | "paris"/"\xe3\x |  7 | region=eu-west2,zone=a   | {3,7,12} | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-central,zone=b"}
  "paris"/"\xe3\x | "paris"/PrefixE |  7 | region=eu-west2,zone=a   | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=c"}
  "amsterdam"     | "amsterdam"/"\x |  8 | region=eu-west2,zone=c   | {3,8,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  "rome"          | "rome"/PrefixEn |  8 | region=eu-west2,zone=c   | {3,8,10} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=c"}
  "amsterdam"/"\x | "amsterdam"/Pre |  9 | region=eu-west2,zone=b   | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  "san francisco" | "san francisco" | 10 | region=eu-central,zone=c | {2,8,10} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=c"}
  "seattle"       | "seattle"/"q\xc | 10 | region=eu-central,zone=c | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=c"}
  "seattle"/"q\xc | "seattle"/Prefi | 10 | region=eu-central,zone=c | {2,9,10} | {"region=us-east4,zone=b","region=eu-west2,zone=b","region=eu-central,zone=c"}
  "los angeles"   | "los angeles"/" | 11 | region=eu-central,zone=a | {1,9,11} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  "san francisco" | "san francisco" | 11 | region=eu-central,zone=a | {3,8,11} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=a"}
  "los angeles"/" | "los angeles"/P | 12 | region=eu-central,zone=b | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
```

Perfect, ranges have been spread across all 3 regions equally. Let's pin partition `us_west2` to region EU West, so we get the fastest reads.

```sql
ALTER PARTITION us_west2 OF INDEX rides@*
CONFIGURE ZONE USING
  num_replicas = 3,
  constraints = '{"+region=eu-west2":1}',
  lease_preferences = '[[+region=eu-west2]]';
```

Wait few minutes, then confirm the leaseholder has moved to EU West and that 1 replica is in EU West.

```sql
SELECT * FROM ridesranges;
```

```text
     start_key    |     end_key     | lh | lease_holder_locality  | replicas |                               replica_localities
------------------+-----------------+----+------------------------+----------+---------------------------------------------------------------------------------
  "new york"/"\x1 | "new york"/Pref |  1 | region=us-east4,zone=a | {1,9,11} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  "boston"        | "boston"/"8\xe2 |  3 | region=us-east4,zone=c | {3,9,11} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=a"}
  "boston"/"8\xe2 | "boston"/Prefix |  3 | region=us-east4,zone=c | {3,9,10} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=c"}
  "new york"      | "new york"/"\x1 |  3 | region=us-east4,zone=c | {3,7,11} | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-central,zone=a"}
  "washington dc" | "washington dc" |  3 | region=us-east4,zone=c | {3,9,10} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=c"}
  "washington dc" | "washington dc" |  3 | region=us-east4,zone=c | {3,8,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}

  "paris"         | "paris"/"\xe3\x |  7 | region=eu-west2,zone=a | {3,7,12} | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-central,zone=b"}
  "paris"/"\xe3\x | "paris"/PrefixE |  7 | region=eu-west2,zone=a | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=c"}
  "seattle"       | "seattle"/"q\xc |  7 | region=eu-west2,zone=a | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=c"}
  "amsterdam"     | "amsterdam"/"\x |  8 | region=eu-west2,zone=c | {3,8,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  "rome"          | "rome"/PrefixEn |  8 | region=eu-west2,zone=c | {3,8,10} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=c"}
  "san francisco" | "san francisco" |  8 | region=eu-west2,zone=c | {3,8,11} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=a"}
  "san francisco" | "san francisco" |  8 | region=eu-west2,zone=c | {2,8,10} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=c"}
  "amsterdam"/"\x | "amsterdam"/Pre |  9 | region=eu-west2,zone=b | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  "los angeles"   | "los angeles"/" |  9 | region=eu-west2,zone=b | {1,9,11} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  "los angeles"/" | "los angeles"/P |  9 | region=eu-west2,zone=b | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  "seattle"/"q\xc | "seattle"/Prefi |  9 | region=eu-west2,zone=b | {2,9,10} | {"region=us-east4,zone=b","region=eu-west2,zone=b","region=eu-central,zone=c"}
```

Good job! Let's review the latency. We now expect latency for reads to be the sum of the SQL client rooundtrip (180ms) and just millis as the leaseholder is in region.

```sql
SELECT * FROM rides WHERE city = 'seattle' LIMIT 1;
SELECT * FROM rides WHERE city = 'san francisco' LIMIT 1;
SELECT * FROM rides WHERE city = 'los angeles' LIMIT 1;
```

```text
                   id                  |  city   | vehicle_city |               rider_id               |              vehicle_id              |    start_address    |    end_address    |        start_time         |         end_time          | revenue
---------------------------------------+---------+--------------+--------------------------------------+--------------------------------------+---------------------+-------------------+---------------------------+---------------------------+----------
  5555c52e-72da-4400-8000-00000000411b | seattle | seattle      | 63958106-24dd-4000-8000-000000000185 | 6147ae14-7ae1-4800-8000-000000000026 | Cockroach Street 50 | 65529 Krystal Via | 2018-12-04 03:04:05+00:00 | 2018-12-04 04:04:05+00:00 |   22.00
(1 row)

Time: 183.4579ms

                   id                  |     city      | vehicle_city | rider_id | vehicle_id | start_address | end_address | start_time | end_time | revenue
---------------------------------------+---------------+--------------+----------+------------+---------------+-------------+------------+----------+----------
  5555c52e-72da-4400-8888-100000135882 | san francisco | NULL         | NULL     | NULL       | NULL          | NULL        | NULL       | NULL     | NULL
(1 row)

Time: 180.5738ms

                   id                  |    city     | vehicle_city | rider_id | vehicle_id | start_address | end_address | start_time | end_time | revenue
---------------------------------------+-------------+--------------+----------+------------+---------------+-------------+------------+----------+----------
  5555c52e-72da-4400-8888-000000105882 | los angeles | NULL         | NULL     | NULL       | NULL          | NULL        | NULL       | NULL     | NULL
(1 row)

Time: 181.8124ms
```

Very nice! We have reduced overall read latency from ~305ms to ~180ms as we moved the leaseholder from US East and EU Central to the region where the client endpoint connects.

Let's test with writes. We expect latency to be the sum of the SQL client roundtrip (~180ms), the Raft consensus roundtrip (15ms - to Frankfurt) for a total of ~195ms. Remember the leaseholder has been pinned to the region the client app connects to and Frankfurt is very close.

```sql
-- gen_random_uuid() creates a new UUID for us, very handy!
INSERT INTO rides VALUES (gen_random_uuid(), 'seattle', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO rides VALUES (gen_random_uuid(), 'los angeles', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO rides VALUES (gen_random_uuid(), 'san francisco', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
```

```text
INSERT 1

Time: 195.0875ms

INSERT 1

Time: 197.0922ms

INSERT 1

Time: 197.0458ms
```

Awesome! Not too bad for an other-side-of-the-world ACID transaction!

## Final thoughts

We played with the different Topology Patterns, learning the use cases for each and what are their strenghts and limitations.

We explored how easy it is to respond to a region failure by quickly scaling out the cluster and by intelligently placing ranges and leaseholders to get best performance.

We have done so while maintaining both availability, transactions consistency and durability: no downtime, no conflicts and no data loss.

We have reacted manually to a region failure, but we could have easely automated the process using any of the popular DevOps tools (Ansible, Terraform, etc.).
