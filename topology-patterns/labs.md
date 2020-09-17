# Topology Patterns - Student Labs

In these labs we will work with CockroachDB [Topology Patterns](https://www.cockroachlabs.com/docs/stable/topology-patterns.html) and understand the use cases, pros and cons for each one.

## Overview

There are 6 recommended topology patterns:

| topology | description | pros | cons|
|-|-|-|-|
| [Basic Production](https://www.cockroachlabs.com/docs/stable/topology-basic-production.html) | Single region deployment | fast r/w | can't survive region failure|
| [Geo-Partitioned Replicas](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-replicas.html) | multi region deployment, however data is partitioned and pinned to a specific region | GDPR or similar legal compliance, fast r/w if client is connected to the region which holds the data is querying | locked data can't survive region failure - it would require multiple regions in the same country|
| [Geo-Partitioned Leaseholders](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-leaseholders.html) | multi-region deployment where leaseholder is pinned to a specific region | fast reads if client connects to region which holds the data; can survive region failure | slighly slower writes as leasholder has to seek consensus outsite its region |
| [Duplicate Indexes](https://www.cockroachlabs.com/docs/stable/topology-duplicate-indexes.html) | Most used indeces are duplicated by the amount of regions and the leaseholders are pinned 1 per region; ideal for data that doesn't frequently updates  | fast reads from every region the client connects to | slower writes as transactions need to also update every index; duplicate data increases storage |
| [Follower Reads](https://www.cockroachlabs.com/docs/stable/topology-follower-reads.html) | special feature that enables reading from any of the replicas | fast reads as the closest replica can be queried instead of the leaseholder, which can be in another region | data read can be slightly historical |
| [Follow-the-Workload](https://www.cockroachlabs.com/docs/stable/topology-follow-the-workload.html) | default setup when no other topology pattern has been implemented | - | - |

## Labs Prerequisites

1. Build the dev cluster following [these instructions](/infrastructure/build-local-docker-cluster.md).

2. You also need:

    - a modern web browser,
    - a SQL client:
      - [Cockroach SQL client]((https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux))
      - `psql`
      - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

## Lab 0 - Create database and load data

Connect to any node and run the workload simulator. Please note that loading the data can take up to 5 minutes.

```bash
docker exec -it roach-newyork-1 cockroach workload init movr --drop --db movr postgres://root@127.0.0.1:26257?sslmode=disable --num-histories 50000 --num-rides 50000 --num-users 1000 --num-vehicles 100
```

Connect to the database to confirm it loaded successfully

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure -d movr

# or use the --url param for another host:
cockroach sql --url "postgresql://localhost:26258/movr?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root movr

# example using cockroach sql client
cockroach sql --url "postgresql://localhost:26257/movr?sslmode=disable"

# example using psql
psql "postgresql://root@localhost:26258/movr?sslmode=disable"
```

```sql
SHOW TABLES;
```

```bash
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

## Lab 1 - Explore Range distribution

Now that you have imported the data, review how the ranges are distributed in the `rides` table

TODO

```sql
SHOW RANGES FROM TABLE rides;
```

```bash
                                start_key                                |                                end_key                                 | range_id | range_size_mb | lease_holder |   lease_holder_locality    | replicas |                                replica_localities
-------------------------------------------------------------------------+------------------------------------------------------------------------+----------+---------------+--------------+----------------------------+----------+-----------------------------------------------------------------------------------
  NULL                                                                   | /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" |       56 |       0.95766 |            3 | region=us-east4,zone=b     | {3,4,8}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=a"}
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" | /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             |       71 |      0.926262 |            3 | region=us-east4,zone=b     | {3,4,8}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=a"}
  /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             | /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     |       69 |      0.980734 |            2 | region=us-east4,zone=c     | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=c","region=eu-west2,zone=a"}
  /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     | /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" |       68 |      0.947365 |            3 | region=us-east4,zone=b     | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=c"}
  /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" | /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     |      133 |      0.914187 |            3 | region=us-east4,zone=b     | {3,5,9}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=eu-west2,zone=c"}
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     | /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" |       66 |      1.907463 |            4 | region=us-west2,zone=c     | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=c","region=eu-west2,zone=a"}
  /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" | /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         |       70 |      0.937071 |            4 | region=us-west2,zone=c     | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=c","region=eu-west2,zone=a"}
  /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         | /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   |       67 |      1.003183 |            9 | region=eu-west2,zone=c | {1,4,9}  | {"region=us-east4,zone=a","region=us-west2,zone=c","region=eu-west2,zone=c"}
  /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   | NULL                                                                   |      143 |      8.888912 |            9 | region=eu-west2,zone=c | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=c"}
(9 rows)

Time: 1.534383s
```

Each range has been replicated in each region, check the `replicas` and `replica_localities` columns.

Review how indexes are distributed on the `movr.rides`

```sql
SHOW CREATE TABLE rides;
```

```bash
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

```bash
  start_key | end_key | range_id | range_size_mb | lease_holder |   lease_holder_locality    | replicas |                                replica_localities
------------+---------+----------+---------------+--------------+----------------------------+----------+-----------------------------------------------------------------------------------
  NULL      | NULL    |      143 |      8.888912 |            9 | region=eu-west2,zone=c | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=c"}
```

Again, the index replicas are also spread across regions.

## Lab 2 - Partition the `rides` table

Read how you can tune the performance of the database using [partitioning](https://www.cockroachlabs.com/docs/v20.1/performance-tuning.html#step-13-partition-data-by-city). [Here](https://www.cockroachlabs.com/docs/v20.1/configure-replication-zones.html#create-a-replication-zone-for-a-partition) you can find information on replication zones with some examples.

Partition the `movr.rides` table by column `movr.city` to the appropriate regions (`us-west1`, `us-east4`, `eu-west2`).

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

```bash
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

Perfect!

## Lab 3 - Geo-Partitioned Leaseholders

In this lab, we implement the [Geo Partitioned Leaseholder](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-leaseholders.html) topology pattern, where we pin the leaseholder to the region to match the cities.

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

Review how the ranges are distributed in the `movr.rides` table after pinning. Confirm the leaseholder for each city is in the same region of the city itself.
  
TODO

```sql
SELECT start_key, lease_holder, lease_holder_locality, replicas, replica_localities
FROM [SHOW RANGES FROM TABLE rides]
WHERE "start_key" IS NOT NULL
AND "start_key" NOT LIKE '%Prefix%';
```

```bash
                                start_key                                |   lease_holder_locality
-------------------------------------------------------------------------+-----------------------------
  /"washington dc"                                                       | region=us-east4,zone=a
  /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             | region=us-east4,zone=c
  /"boston"                                                              | region=us-east4,zone=b
  /"new york"                                                            | region=us-east4,zone=b
  /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" | region=us-east4,zone=b
  /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   | region=us-east4,zone=b

  /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     | region=us-west2,zone=c
  /"san francisco"                                                       | region=us-west2,zone=c
  /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         | region=us-west2,zone=c
  /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" | region=us-west2,zone=a
  /"seattle"                                                             | region=us-west2,zone=a
  /"los angeles"                                                         | region=us-west2,zone=b

  /"amsterdam"                                                           | region=eu-west2,zone=b
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     | region=eu-west2,zone=b
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" | region=eu-west2,zone=a
  /"rome"                                                                | region=eu-west2,zone=a
  /"paris"                                                               | region=eu-west2,zone=c
(17 rows)

Time: 1.484839s
```

Good, as expected! Let's see next what happens when we run queries against each region.

Experiment running the same queries in **all** regions and observe the **Time**, printed at the bottom.

Connect with separate SQL connections to each region. Use iTerm2 with broadcast, or just open 3 terminals.  Run the following queries in each (in this example, I only show the result from the `roach-newyork-1` node)

```sql
-- confirm location for the current node
SHOW LOCALITY;
-- query data from other regions will incur latency as the leaseholders are in the other regions
SELECT id, start_address, 'seattle' AS city
FROM rides
WHERE city = 'seattle'
LIMIT 1;
SELECT id, start_address, 'new york' as city
FROM rides
WHERE city = 'new york'
LIMIT 1;
SELECT id, start_address, 'rome' AS city
FROM rides
WHERE city = 'rome'
LIMIT 1;
```

```bash
         locality
--------------------------
  region=us-east4,zone=a
(1 row)

Time: 1.847ms

                   id                  |        start_address        |  city
---------------------------------------+-----------------------------+----------
  5555c52e-72da-4400-8000-00000000411b | 25783 Kelly Fields Suite 75 | seattle
(1 row)

Time: 67.662ms

                   id                  |    start_address     |   city
---------------------------------------+----------------------+-----------
  00000000-0000-4000-8000-000000000000 | 99176 Anderson Mills | new york
(1 row)

Time: 1.921ms

                   id                  |   start_address    | city
---------------------------------------+--------------------+-------
  e38ef34d-6a16-4000-8000-00000000ad9d | 12651 Haley Square | rome
(1 row)

Time: 128.969ms
```

As expected, when from a `us-east4` based node I query data in the region, I get a fast response, but the delay is noticeable when the node has to reach out to the leaseholder in the other regions to get the data for the other regions.

Connect to the Admin UI and go to the **Network Latency** tab on the left. Compare the latency measured with your findings running SQL queries.

## Lab 4 - Follower Reads

With [Follower Reads](https://www.cockroachlabs.com/docs/stable/topology-follower-reads.html), you can get fast response times on reads from any of the replicas.

Pros:

- fast response time if any of the replicas is local - no need to reach out to the leaseholder
- no need to duplicate data, e.g. duplicate indexes

Cons:

- data is slightly historical

There are 2 ways to use the Follower Reads functionality: the first is by using `experimental_follower_read_timestamp()`. Run these queries on all your regions:

```sql
SHOW LOCALITY;

SELECT id, start_address, 'seattle' as city
FROM rides AS OF SYSTEM TIME experimental_follower_read_timestamp()
WHERE city = 'seattle'
LIMIT 1;

SELECT id, start_address, 'new york' as city
FROM rides AS OF SYSTEM TIME experimental_follower_read_timestamp()
WHERE city = 'new york'
LIMIT 1;

SELECT id, start_address, 'rome' as city
FROM rides AS OF SYSTEM TIME experimental_follower_read_timestamp()
WHERE city = 'rome'
LIMIT 1;
```

```bash
         locality
--------------------------
  region=us-east4,zone=b
(1 row)

Time: 2.47ms

                   id                  |        start_address        |  city
---------------------------------------+-----------------------------+----------
  5555c52e-72da-4400-8000-00000000411b | 25783 Kelly Fields Suite 75 | seattle
(1 row)

Time: 1.933ms

                   id                  |    start_address     |   city
---------------------------------------+----------------------+-----------
  00000000-0000-4000-8000-000000000000 | 99176 Anderson Mills | new york
(1 row)

Time: 2.546ms

                   id                  |   start_address    | city
---------------------------------------+--------------------+-------
  e38ef34d-6a16-4000-8000-00000000ad9d | 12651 Haley Square | rome
(1 row)

Time: 1.896ms
```

The second way is by explicitly setting a time interval using `AS OF SYSTEM TIME INTERVAL '-1m'`

```sql
SHOW LOCALITY;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1m'
WHERE city = 'seattle'
LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1m'
WHERE city = 'new york'
LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1m'
WHERE city = 'rome'
LIMIT 1;
```

You should see that the response times for each city is comparable to the local city response time (single digit ms response time). What is happening, the database is querying the local replica of that range - remember each region has a replica of every range.

Try using with an interval of `-2s`. Response times will go back the same as prior to using Follower Reads. This is because the time interval is not long enough to pickup the copy at that interval.

You can use `AS OF SYSTEM TIME experimental_follower_read_timestamp()` to ensure Follower Reads queries use local ranges with the least time lag.

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

```bash
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

```bash
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

EXPLAIN SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='rome'
GROUP BY 1,2;
```

```bash
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
show ranges from index idx_us_east_rides;
```

```bash
  start_key | end_key | range_id | range_size_mb | lease_holder | lease_holder_locality  | replicas |                                replica_localities
------------+---------+----------+---------------+--------------+------------------------+----------+-----------------------------------------------------------------------------------
  NULL      | NULL    |      141 |      4.244041 |            3 | region=us-east4,zone=b | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=eu-west2,zone=c"}
(1 row)
```

Awesome! We can now delete the indexes

```sql
DROP INDEX idx_us_west_rides;
DROP INDEX idx_us_east_rides;
DROP INDEX idx_eu_west_rides;
```

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

The total latency for the query is 180 + 125 + 125 = 430ms.

To temporarely remedy this problem and decrease the overall response time, we have 2 options:

- move all former US West ranges from region US East to region EU West - but that means we can't survive if EU West goes down as we'd have all replicas in that region;
- scale out the Cockroach cluster and deploy nodes on a **new** datacenter close to EU West, so that the Raft consensus is achieved quicker and can still survive should US East region become unavailable.

Reduce the time CRDB considers nodes dead down from 5 to 2 minutes

```sql
SET CLUSTER SETTING server.time_until_store_dead = '2m';
```

Simulate region failure. Ensure to run all following `docker` commands on a new terminal, on localhost.

```bash
docker stop haproxy-seattle roach-seattle-1 roach-seattle-2 roach-seattle-3
```

Check the Admin UI - you might have to use a different port as the host bound to port 8080 died. Use port 8180 instead.
In 2 minutes, 3 nodes will be set to **Dead**, and CockroachDB will start replicating the ranges into the remaining regions.

![dead-nodes](/media/dead-nodes.png)

```sql
SELECT start_key, lease_holder, lease_holder_locality, replicas, replica_localities
FROM [SHOW RANGES FROM TABLE rides]
WHERE "start_key" IS NOT NULL
AND "start_key" NOT LIKE '%Prefix%';
```

```bash
                                start_key                                | lease_holder | lease_holder_locality  | replicas |                              replica_localities
-------------------------------------------------------------------------+--------------+------------------------+----------+-------------------------------------------------------------------------------
  /"boston"                                                              |            1 | region=us-east4,zone=a | {1,7,9}  | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-west2,zone=c"}
  /"los angeles"                                                         |            1 | region=us-east4,zone=a | {1,8,9}  | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-west2,zone=c"}
  /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     |            1 | region=us-east4,zone=a | {1,2,7}  | {"region=us-east4,zone=a","region=us-east4,zone=b","region=eu-west2,zone=b"}
  /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" |            1 | region=us-east4,zone=a | {1,2,9}  | {"region=us-east4,zone=a","region=us-east4,zone=b","region=eu-west2,zone=c"}
  /"seattle"                                                             |            1 | region=us-east4,zone=a | {1,3,9}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=c"}
  /"washington dc"                                                       |            1 | region=us-east4,zone=a | {1,3,9}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=c"}
  /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             |            2 | region=us-east4,zone=b | {2,3,8}  | {"region=us-east4,zone=b","region=us-east4,zone=c","region=eu-west2,zone=a"}
  /"new york"                                                            |            2 | region=us-east4,zone=b | {1,2,7}  | {"region=us-east4,zone=a","region=us-east4,zone=b","region=eu-west2,zone=b"}
  /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         |            3 | region=us-east4,zone=c | {2,3,8}  | {"region=us-east4,zone=b","region=us-east4,zone=c","region=eu-west2,zone=a"}
  /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   |            3 | region=us-east4,zone=c | {3,8,9}  | {"region=us-east4,zone=c","region=eu-west2,zone=a","region=eu-west2,zone=c"}
  
  /"paris"                                                               |            7 | region=eu-west2,zone=b | {3,7,8}  | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-west2,zone=a"}
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     |            7 | region=eu-west2,zone=b | {1,2,7}  | {"region=us-east4,zone=a","region=us-east4,zone=b","region=eu-west2,zone=b"}
  /"amsterdam"                                                           |            8 | region=eu-west2,zone=a | {1,3,8}  | {"region=us-east4,zone=a","region=us-east4,zone=c","region=eu-west2,zone=a"}
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" |            8 | region=eu-west2,zone=a | {1,7,8}  | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-west2,zone=a"}
  /"san francisco"                                                       |            8 | region=eu-west2,zone=a | {2,3,8}  | {"region=us-east4,zone=b","region=us-east4,zone=c","region=eu-west2,zone=a"}
  /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" |            8 | region=eu-west2,zone=a | {2,8,9}  | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-west2,zone=c"}
  /"rome"                                                                |            9 | region=eu-west2,zone=c | {2,8,9}  | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-west2,zone=c"}
```

From above table we can see that the Seattle data was replicated to US East. We will therefore try to update a row in those ranges so the EU West gateway node will pass the write request to the US East based leaseholder, and thus get the highest possible latency for our transaction.

Create a new running docker container using the `cockroachdb` image. This will be our SQL client app connecting from Seattle.

```bash
docker run -d --name=seattle-client --hostname=seattle-client --cap-add NET_ADMIN --net=us-west2-net cockroachdb/cockroach:v20.1.5 start --insecure --join=fake1,fake2,fake3

# add network connections and latency to seattle-client
docker network connect uswest-useast-net seattle-client
docker network connect uswest-euwest-net seattle-client
docker exec seattle-client bash -c "apt-get update && apt-get install -y iproute2 iputils-ping dnsutils"
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

```bash
         locality
--------------------------
  region=eu-west2,zone=a
(1 row)

Time: 182.096ms
```

Very good, you can now simulate an App in Seattle that is routed to the London endpoint due to the unavailable US West region.

Let's do some testing: reading Seattle data will incour the client roundtrip from US West to EU West, ~180ms, plus the roundtrip from EU West to US East (~125ms) for the leaseholder read for a total of ~305ms.

```sql
select * from rides where city = 'seattle' limit 1;
```

```bash
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
insert into rides values ('5555c52e-72da-4400-8888-000000125882', 'seattle', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
insert into rides values ('5555c52e-72da-4400-8888-000000135882', 'los angeles', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
```

```bash
INSERT 1

Time: 309.8142ms
INSERT 1

Time: 430.9846ms
```

Cool! You can always check the replicas location for a key as follows:

```sql
SHOW RANGE FROM TABLE rides FOR ROW ('5555c52e-72da-4400-8888-000000125882', 'seattle', null, null, null, null,null, null,null, null);
SHOW RANGE FROM TABLE rides FOR ROW ('5555c52e-72da-4400-8888-000000135882', 'los angeles', null, null, null, null,null, null,null, null);
```

```bash
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

We now understand the ramification of a failed region and the toll it takes on the overall latency. We understand that region US West will take several hours to become operational again and we decide to remedy by scaling out the cluster, also because we are afraid another region might go down and the Cockroach cluster would become unavailable, too, as quorum can't be reached with 1 out of 3 ranges being available.

Provision the datacenter in Frankfurt, Germany. We call this region EU Central

```bash
# create local network eu-central-net
docker network create --driver=bridge --subnet=172.26.0.0/16 --ip-range=172.26.0.0/24 --gateway=172.26.0.1 eu-central-net

# create inter-regional networks
docker network create --driver=bridge --subnet=172.33.0.0/16 --ip-range=172.33.0.0/24 --gateway=172.33.0.1 useast-eucentral-net
docker network create --driver=bridge --subnet=172.34.0.0/16 --ip-range=172.34.0.0/24 --gateway=172.34.0.1 euwest-eucentral-net

# create 3 nodes in Frankfurt - no need for HAProxy...
docker run -d --name=roach-frankfurt-1 --hostname=roach-frankfurt-1 --ip=172.26.0.11 --cap-add NET_ADMIN --net=eu-central-net --add-host=roach-frankfurt-1:172.26.0.11 --add-host=roach-frankfurt-2:172.26.0.12 --add-host=roach-frankfurt-3:172.26.0.13 -p 8480:8080 -v "roach-frankfurt-1-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-central,zone=a
docker run -d --name=roach-frankfurt-2 --hostname=roach-frankfurt-2 --ip=172.26.0.12 --cap-add NET_ADMIN --net=eu-central-net --add-host=roach-frankfurt-1:172.26.0.11 --add-host=roach-frankfurt-2:172.26.0.12 --add-host=roach-frankfurt-3:172.26.0.13 -p 8481:8080 -v "roach-frankfurt-2-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-central,zone=b
docker run -d --name=roach-frankfurt-3 --hostname=roach-frankfurt-3 --ip=172.26.0.13 --cap-add NET_ADMIN --net=eu-central-net --add-host=roach-frankfurt-1:172.26.0.11 --add-host=roach-frankfurt-2:172.26.0.12 --add-host=roach-frankfurt-3:172.26.0.13 -p 8482:8080 -v "roach-frankfurt-3-data:/cockroach/cockroach-data" cockroachdb/cockroach:v20.1.5 start --insecure --join=roach-seattle-1,roach-newyork-1,roach-london-1 --locality=region=eu-central,zone=c

# attach networks and latency
# Frankfurt
for j in 1 2 3
do
    docker network connect useast-eucentral-net roach-frankfurt-$j
    docker network connect euwest-eucentral-net roach-frankfurt-$j
    docker exec roach-frankfurt-$j bash -c "apt-get update && apt-get install -y iproute2 iputils-ping dnsutils"
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

Check the Admin UI: slowly, you should see the live nodes increasing from 6 to 9. If you refresh the map, you should see the Frankfurt datacenter.

![eu-central-map](/media/eu-central-map.png)

Confirm the latency in the Network Latency page is ~12ms between London and Frankfurt, and ~120ms between Frankfurt and NY.

![eu-central-latency](/media/eu-central-latency.png)

Ranges have been automatically shuffled around to the new datacenter. Check what it looks like:

```sql
SHOW RANGES FROM TABLE rides;
```

```bash
                                start_key                                |                                end_key                                 | range_id | range_size_mb | lease_holder |  lease_holder_locality   | replicas |                               replica_localities
-------------------------------------------------------------------------+------------------------------------------------------------------------+----------+---------------+--------------+--------------------------+----------+---------------------------------------------------------------------------------
  NULL                                                                   | /"amsterdam"                                                           |       39 |             0 |            9 | region=eu-west2,zone=c   | {1,9,11} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=c"}
  /"amsterdam"                                                           | /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" |       82 |       0.95766 |            8 | region=eu-west2,zone=a   | {1,8,11} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=c"}
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" | /"amsterdam"/PrefixEnd                                                 |       59 |      0.000695 |            7 | region=eu-west2,zone=b   | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  /"amsterdam"/PrefixEnd                                                 | /"boston"                                                              |      133 |             0 |            1 | region=us-east4,zone=a   | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  /"boston"                                                              | /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             |       79 |      0.925567 |            1 | region=us-east4,zone=a   | {1,7,11} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=c"}
  /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             | /"boston"/PrefixEnd                                                    |       58 |      0.000592 |            2 | region=us-east4,zone=b   | {2,8,10} | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-central,zone=a"}
  /"boston"/PrefixEnd                                                    | /"los angeles"                                                         |       78 |             0 |           12 | region=eu-central,zone=b | {3,7,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  /"los angeles"                                                         | /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     |       73 |      0.982539 |           10 | region=eu-central,zone=a | {1,9,10} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     | /"los angeles"/PrefixEnd                                               |       56 |      0.000709 |           10 | region=eu-central,zone=a | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  /"los angeles"/PrefixEnd                                               | /"new york"                                                            |       72 |             0 |            7 | region=eu-west2,zone=b   | {3,7,11} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=c"}
  /"new york"                                                            | /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" |       77 |      0.946656 |            2 | region=us-east4,zone=b   | {2,7,12} | {"region=us-east4,zone=b","region=eu-west2,zone=b","region=eu-central,zone=b"}
  /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" | /"new york"/PrefixEnd                                                  |       57 |      0.000173 |            1 | region=us-east4,zone=a   | {1,9,12} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"new york"/PrefixEnd                                                  | /"paris"                                                               |      123 |             0 |            1 | region=us-east4,zone=a   | {1,9,10} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"paris"                                                               | /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     |      125 |      0.914014 |            7 | region=eu-west2,zone=b   | {3,7,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     | /"paris"/PrefixEnd                                                     |       93 |      0.000828 |            7 | region=eu-west2,zone=b   | {2,7,11} | {"region=us-east4,zone=b","region=eu-west2,zone=b","region=eu-central,zone=c"}
  /"paris"/PrefixEnd                                                     | /"rome"                                                                |       81 |             0 |           12 | region=eu-central,zone=b | {1,9,12} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"rome"                                                                | /"rome"/PrefixEnd                                                      |      134 |       0.90353 |            9 | region=eu-west2,zone=c   | {2,9,12} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"rome"/PrefixEnd                                                      | /"san francisco"                                                       |      135 |             0 |            2 | region=us-east4,zone=b   | {2,9,10} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"san francisco"                                                       | /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" |       70 |      1.005096 |           12 | region=eu-central,zone=b | {2,8,12} | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-central,zone=b"}
  /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" | /"san francisco"/PrefixEnd                                             |      114 |       0.00055 |           10 | region=eu-central,zone=a | {2,9,10} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"san francisco"/PrefixEnd                                             | /"seattle"                                                             |       74 |             0 |            7 | region=eu-west2,zone=b   | {3,7,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  /"seattle"                                                             | /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         |       75 |      0.946371 |           12 | region=eu-central,zone=b | {1,9,12} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         | /"seattle"/PrefixEnd                                                   |      113 |      0.000506 |           11 | region=eu-central,zone=c | {2,8,11} | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-central,zone=c"}
  /"seattle"/PrefixEnd                                                   | /"washington dc"                                                       |       71 |             0 |           10 | region=eu-central,zone=a | {2,9,10} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"washington dc"                                                       | /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   |       76 |      1.002677 |            3 | region=us-east4,zone=c   | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   | /"washington dc"/PrefixEnd                                             |       69 |      0.000367 |            3 | region=us-east4,zone=c   | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"washington dc"/PrefixEnd                                             | NULL                                                                   |       80 |      8.890417 |            2 | region=us-east4,zone=b   | {2,9,11} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=c"}
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
SELECT start_key, lease_holder_locality, replica_localities
FROM [SHOW RANGES FROM TABLE rides]
WHERE "start_key" IS NOT NULL
AND "start_key" NOT LIKE '%Prefix%';
```

```bash
                                start_key                                | lease_holder | lease_holder_locality  | replicas |                               replica_localities
-------------------------------------------------------------------------+--------------+------------------------+----------+---------------------------------------------------------------------------------
  /"boston"                                                              |            1 | region=us-east4,zone=a | {1,7,11} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=c"}
  /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             |            1 | region=us-east4,zone=a | {1,8,10} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=a"}
  /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" |            1 | region=us-east4,zone=a | {1,9,12} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"new york"                                                            |            2 | region=us-east4,zone=b | {2,7,10} | {"region=us-east4,zone=b","region=eu-west2,zone=b","region=eu-central,zone=a"}
  /"washington dc"                                                       |            3 | region=us-east4,zone=c | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   |            3 | region=us-east4,zone=c | {3,9,12} | {"region=us-east4,zone=c","region=eu-west2,zone=c","region=eu-central,zone=b"}
  
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" |            7 | region=eu-west2,zone=b | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     |            7 | region=eu-west2,zone=b | {1,7,10} | {"region=us-east4,zone=a","region=eu-west2,zone=b","region=eu-central,zone=a"}
  /"paris"                                                               |            7 | region=eu-west2,zone=b | {3,7,12} | {"region=us-east4,zone=c","region=eu-west2,zone=b","region=eu-central,zone=b"}
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     |            7 | region=eu-west2,zone=b | {2,7,11} | {"region=us-east4,zone=b","region=eu-west2,zone=b","region=eu-central,zone=c"}
  /"amsterdam"                                                           |            8 | region=eu-west2,zone=a | {1,8,11} | {"region=us-east4,zone=a","region=eu-west2,zone=a","region=eu-central,zone=c"}
  /"san francisco"                                                       |            8 | region=eu-west2,zone=a | {2,8,12} | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-central,zone=b"}
  /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         |            8 | region=eu-west2,zone=a | {2,8,11} | {"region=us-east4,zone=b","region=eu-west2,zone=a","region=eu-central,zone=c"}
  /"los angeles"                                                         |            9 | region=eu-west2,zone=c | {1,9,10} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"rome"                                                                |            9 | region=eu-west2,zone=c | {2,9,12} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=b"}
  /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" |            9 | region=eu-west2,zone=c | {2,9,10} | {"region=us-east4,zone=b","region=eu-west2,zone=c","region=eu-central,zone=a"}
  /"seattle"                                                             |            9 | region=eu-west2,zone=c | {1,9,12} | {"region=us-east4,zone=a","region=eu-west2,zone=c","region=eu-central,zone=b"}
```

Good job! Let's review the latency. We now expect latency for reads to be the sum of the SQL client rooundtrip (180ms) and just millis as leaseholder is in region, for a total of ~180ms.

```sql
SELECT * FROM rides WHERE city = 'seattle' LIMIT 1;
SELECT * FROM rides WHERE city = 'san francisco' LIMIT 1;
SELECT * FROM rides WHERE city = 'los angeles' LIMIT 1;
```

```bash
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

Very nice! We have reduced overall read latency from ~305ms to ~180ms as we moved the leaseholder from US East and EU Central to the region where the client endpoint connects!

Let's test with writes. We expect latency to be the sum of the SQL client roundtrip (~180ms), the Raft consensus roundtrip (15ms - to Frankfurt) for a total of ~195ms. Remember the leaseholder has been pinned to the region the client app connects to and Frankfurt is very close.

```sql
-- we use different UUIDs from before...
INSERT INTO rides VALUES ('5555c52e-72da-4400-8888-160000125845', 'seattle', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO rides VALUES ('5555c52e-72da-4400-8888-160000135846', 'los angeles', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
INSERT INTO rides VALUES ('5555c52e-72da-4400-8888-160000135847', 'san francisco', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);
```

```bash
INSERT 1

Time: 195.0875ms

INSERT 1

Time: 197.0922ms

INSERT 1

Time: 197.0458ms
```

Awesome! Not too bad for an other-side-of-the-world ACID transaction!
