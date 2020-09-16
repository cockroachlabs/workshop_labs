# Topology Patterns - Student Labs

## Prerequisites

- Modern web browser
- SQL client:
  - `cockroach sql`
  - `psql`
  - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

## Lab 0 - Create database and load data

Connect to any node and run the workload simulator. Please note that loading the data can take up to 5 minutes.

```bash
# connect into one of the nodes, then run the command to build the database
./cockroach workload init movr --drop --db movr postgres://root@127.0.0.1:26257?sslmode=disable --num-histories 50000 --num-rides 50000 --num-users 1000 --num-vehicles 100
```

Connect to the database to confirm it loaded successfully

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure

# or use the --url param for another host:
cockroach sql --url "postgresql://localhost:26258/defaultdb?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root defaultdb

# example using cockroach sql client
cockroach sql --url "postgresql://localhost:26257/movr?sslmode=disable"

# example using psql
psql "postgresql://root@localhost:26258/movr?sslmode=disable"
```

```bash
sql> SHOW TABLES;
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

Now that you have imported the data, review how the ranges are distributed in the `movr.rides` table

```sql
sql> SHOW RANGES FROM TABLE movr.rides;
                                start_key                                |                                end_key                                 | range_id | range_size_mb | lease_holder |   lease_holder_locality    | replicas |                                replica_localities
-------------------------------------------------------------------------+------------------------------------------------------------------------+----------+---------------+--------------+----------------------------+----------+-----------------------------------------------------------------------------------
  NULL                                                                   | /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" |       56 |       0.95766 |            3 | region=us-east4,zone=b     | {3,4,8}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=europe-west2,zone=a"}
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" | /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             |       71 |      0.926262 |            3 | region=us-east4,zone=b     | {3,4,8}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=europe-west2,zone=a"}
  /"boston"/"8\xe2\x19e+\xd3D\x00\x80\x00\x00\x00\x00\x00+f"             | /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     |       69 |      0.980734 |            2 | region=us-east4,zone=c     | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=c","region=europe-west2,zone=a"}
  /"los angeles"/"\xaa\xa6L/\x83{H\x00\x80\x00\x00\x00\x00\x00\x822"     | /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" |       68 |      0.947365 |            3 | region=us-east4,zone=b     | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=europe-west2,zone=c"}
  /"new york"/"\x1cq\f\xb2\x95\xe9B\x00\x80\x00\x00\x00\x00\x00\x15\xb3" | /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     |      133 |      0.914187 |            3 | region=us-east4,zone=b     | {3,5,9}  | {"region=us-east4,zone=b","region=us-west2,zone=a","region=europe-west2,zone=c"}
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     | /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" |       66 |      1.907463 |            4 | region=us-west2,zone=c     | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=c","region=europe-west2,zone=a"}
  /"san francisco"/"\x8e5?|\xed\x91H\x00\x80\x00\x00\x00\x00\x00l\u007f" | /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         |       70 |      0.937071 |            4 | region=us-west2,zone=c     | {2,4,8}  | {"region=us-east4,zone=c","region=us-west2,zone=c","region=europe-west2,zone=a"}
  /"seattle"/"q\xc42\xcaW\xa7H\x00\x80\x00\x00\x00\x00\x00V\xcc"         | /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   |       67 |      1.003183 |            9 | region=europe-west2,zone=c | {1,4,9}  | {"region=us-east4,zone=a","region=us-west2,zone=c","region=europe-west2,zone=c"}
  /"washington dc"/"US&\x17\xc1\xbdD\x00\x80\x00\x00\x00\x00\x00A\x19"   | NULL                                                                   |      143 |      8.888912 |            9 | region=europe-west2,zone=c | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=europe-west2,zone=c"}
(9 rows)

Time: 1.534383s
```

Each range has been replicated in each region, check the `replicas` and `replica_localities` columns.

Review how indexes are distributed on the `movr.rides`

```sql
-- show index from table rides
sql> SHOW CREATE TABLE rides;
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
(1 row)

Time: 738.587ms

-- show ranges from one of the indexes
sql> SHOW RANGES FROM INDEX rides_auto_index_fk_city_ref_users;
  start_key | end_key | range_id | range_size_mb | lease_holder |   lease_holder_locality    | replicas |                                replica_localities
------------+---------+----------+---------------+--------------+----------------------------+----------+-----------------------------------------------------------------------------------
  NULL      | NULL    |      143 |      8.888912 |            9 | region=europe-west2,zone=c | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=europe-west2,zone=c"}
(1 row)

Time: 656.225ms
```

Again, the index replicas are also spread across regions.

## Lab 2 - Partition the rides table

Partition the `movr.rides` table by **city** to the appropriate regions (`us-west1`, `us-east4`, `eu-west2`).

```sql
ALTER TABLE rides PARTITION BY LIST (city) (
  PARTITION us_west1 VALUES IN ('los angeles', 'seattle', 'san francisco'),
  PARTITION us_east4 VALUES IN ('new york','boston', 'washington dc'),
  PARTITION eu_west2 VALUES IN ('paris','rome','amsterdam')
);
```

Confirm the partition job was successful

```sql
sql> SHOW PARTITIONS FROM TABLE rides;
  database_name | table_name | partition_name | parent_partition | column_names |  index_name   |                 partition_value                 | zone_config |       full_zone_config
----------------+------------+----------------+------------------+--------------+---------------+-------------------------------------------------+-------------+-------------------------------
  movr          | rides      | us_west1       | NULL             | city         | rides@primary | ('los angeles'), ('seattle'), ('san francisco') | NULL        | range_min_bytes = 134217728,
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
(3 rows)

Time: 3.672802s
```

Perfect!

## Lab 3 - Pin leaseholder to region

In this lab, we implement the [Geo Partitioned Leaseholder](https://www.cockroachlabs.com/docs/stable/topology-geo-partitioned-leaseholders.html) topology pattern, where we pin the leaseholder to the region to match the cities.

Pros:

- fast read response from in-region reads
- we can still tolerate a region failure.

Cons:

- slower writes as leaseholder has to reach to other regions for quorum.

The `lease_preferences` will be set to the target region and the `constaints` will be set to require **one** replica in the same region as the lease holder.

```sql
ALTER PARTITION us_west1 OF INDEX rides@*
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
  constraints = '{"+region=europe-west2":1}',
  lease_preferences = '[[+region=europe-west2]]';  
```

This job will take about 5 minutes to complete, as ranges are shuffled around the cluster to land on the requested `ZONE` i.e. region.

Review how the ranges are distributed in the `movr.rides` table after pinning. Confirm the leaseholder for each city is in the same region of the city itself.
  
```sql
SELECT start_key, lease_holder, lease_holder_locality, replicas, replica_localities
FROM [SHOW RANGES FROM TABLE rides]
  WHERE "start_key" IS NOT NULL
  AND "start_key" NOT LIKE '%Prefix%';

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

  /"amsterdam"                                                           | region=europe-west2,zone=b
  /"paris"/"\xe3\x88e\x94\xafO@\x00\x80\x00\x00\x00\x00\x00\xad\x98"     | region=europe-west2,zone=b
  /"amsterdam"/"\xc7\x17X\xe2\x19eH\x00\x80\x00\x00\x00\x00\x00\x97\xe5" | region=europe-west2,zone=a
  /"rome"                                                                | region=europe-west2,zone=a
  /"paris"                                                               | region=europe-west2,zone=c
(17 rows)

Time: 1.484839s
```

## Lab 4 - Run Queries across ALL regions

Experiment running the same queries in **all** regions and observe the behavior.

Connect with separate SQL connections to each region.  Run the following queries in each:

```sql
-- confirm location for the current node
sql> show locality;
         locality
--------------------------
  region=us-east4,zone=a
(1 row)

Time: 1.892ms

-- data served from the region will be fast, as the leaseholder is local to us
sql> SELECT id, start_address
FROM rides
WHERE city = 'new york'
LIMIT 1;
                   id                  |    start_address
---------------------------------------+-----------------------
  00000000-0000-4000-8000-000000000000 | 99176 Anderson Mills
(1 row)

Time: 2.616ms

-- query data from other regions will incur latency as the leaseholders are in the other regions
sql> SELECT id, start_address
FROM rides
WHERE city = 'seattle'
LIMIT 1;
                   id                  |        start_address
---------------------------------------+------------------------------
  5555c52e-72da-4400-8000-00000000411b | 25783 Kelly Fields Suite 75
(1 row)

Time: 67.682ms

sql> SELECT id, start_address
FROM rides
WHERE city = 'rome'
LIMIT 1;
                   id                  |   start_address
---------------------------------------+---------------------
  e38ef34d-6a16-4000-8000-00000000ad9d | 12651 Haley Square
(1 row)

Time: 126.282ms
```

Connect to the Admin UI and go to the **Network Latency** tab on the left. Compare the latency measured with your findings running SQL queries.

## Lab 5 -  Configuring Follower Reads

Confirm Follower Reads are enabled in the cluster.

```sql
SHOW CLUSTER SETTING kv.closed_timestamp.follower_reads_enabled;
  kv.closed_timestamp.follower_reads_enabled
+--------------------------------------------+
                    true
```

If disable, you can enable with

```sql
SET CLUSTER SETTING kv.closed_timestamp.follower_reads_enabled='true';
```

## Lab 6 - Observing Multi-Region Performance with Follower Reads

With [Follower Reads](https://www.cockroachlabs.com/docs/stable/topology-follower-reads.html), you can get fast response times on reads from any of the replicas.

Re-run the previous test using Follower Reads

- **using `experimental_follower_read_timestamp()`**

```sql
SHOW LOCALITY;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME experimental_follower_read_timestamp()
WHERE city = 'seattle'
LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME experimental_follower_read_timestamp()
WHERE city = 'new york'
LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME experimental_follower_read_timestamp()
WHERE city = 'rome'
LIMIT 1;
```

**using `AS OF SYSTEM TIME INTERVAL '-1h'`**

```sql
SHOW LOCALITY;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1h'
WHERE city = 'seattle'
LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1h'
WHERE city = 'new york'
LIMIT 1;

SELECT id, start_address
FROM rides AS OF SYSTEM TIME INTERVAL '-1h'
WHERE city = 'rome'
LIMIT 1;
```

Try using with an interval of `-2s`. Response times will go back the same as prior to using Follower Reads. This is because the time interval is not long enough to pickup the copy at that interval.

You can use `AS OF SYSTEM TIME experimental_follower_read_timestamp()` to ensure Follower Reads queries use local ranges with the least time lag.

## Lab 7 - Duplicate Indexes

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
WHERE city='paris'
GROUP BY 1,2;
```

As expected, you get slow responses from queries that have to be fetched from other regions.

You can use the [Duplicate Indexes](https://www.cockroachlabs.com/docs/stable/topology-duplicate-indexes.html) topology to get fast reponse times on reads, without using follower reads.

```sql
create index idx_us_west_rides on rides(city) storing (vehicle_city, vehicle_id);
create index idx_us_east_rides on rides(city) storing (vehicle_city, vehicle_id);
create index idx_europe_west_rides on rides(city) storing (vehicle_city, vehicle_id);

ALTER INDEX idx_us_west_rides CONFIGURE ZONE USING
      num_replicas = 3,
      constraints = '{+region=us-west2: 1}',
      lease_preferences = '[[+region=us-west2]]';

ALTER INDEX idx_us_east_rides CONFIGURE ZONE USING
      num_replicas = 3,
      constraints = '{+region=us-east4: 1}',
      lease_preferences = '[[+region=us-east4]]';

ALTER INDEX idx_europe_west_rides CONFIGURE ZONE USING
      num_replicas = 3,
      constraints = '{+region=europe-west2: 1}',
      lease_preferences = '[[+region=europe-west2]]';
```

Wait few minutes for the ranges to shuffle to the right regions.

Run the same query again, this time response times should be similar across all regions for all cities.

Use `EXPLAIN` to confirm that the optimizer is using the index whose leaseholder is local to the region.

In below example, we are in the US East region and the optimizer is leveraging the `idx_us_east_rides` index.

```sql
sql> show locality;
         locality
--------------------------
  region=us-east4,zone=b
(1 row)

Time: 2.248ms

sql> EXPLAIN SELECT vehicle_city, vehicle_id, count(*)
FROM rides
WHERE city='paris'
GROUP BY 1,2;
       tree      |    field    |         description
-----------------+-------------+------------------------------
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
                 | spans       | /"paris"-/"paris"/PrefixEnd
(11 rows)

Time: 2.425ms
```

You can always check the index ranges to find out where the leaseholder is located

```sql
sql> show ranges from index idx_us_east_rides;
  start_key | end_key | range_id | range_size_mb | lease_holder | lease_holder_locality  | replicas |                                replica_localities
------------+---------+----------+---------------+--------------+------------------------+----------+-----------------------------------------------------------------------------------
  NULL      | NULL    |      141 |      4.244041 |            3 | region=us-east4,zone=b | {3,4,9}  | {"region=us-east4,zone=b","region=us-west2,zone=c","region=europe-west2,zone=c"}
(1 row)
```
