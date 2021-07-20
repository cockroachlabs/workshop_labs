# JSON Optimization - Cockroach Cloud Free Tier

## Overview

CockroachDB supports operation on JSON objects. In these labs, we will get familiar with working with the JSONB data type, as well as with ways to optimize queries with JSONB objects.

## Labs Prerequisites

1. Connection URL to the Cockroach Cloud Free Tier

2. You also need:

    - a modern web browser,
    - [Cockroach SQL client](https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux)

## Lab 1 - Load table with big JSON object

Connect to the database to confirm it loaded successfully

```bash
# download data files
wget https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/CC-FreeTier/data/json1.sql
wget https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/CC-FreeTier/data/json2.sql
wget https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/CC-FreeTier/data/json3.sql

# load just the first file into the database
cockroach sql --url "postgresql://<yourname>:<password>@[...]" < json1.sql

# now connect to the CockroachDB cluster
cockroach sql --url "postgresql://<yourname>:<password>@[...]"
```

Check how many JSON objects were inserted:

```sql
USE jsondb;

SHOW TABLES;

SELECT count(*) FROM jblob;
```

```text
SET

Time: 32ms total (execution 0ms / network 31ms)

  schema_name | table_name | type  | owner | estimated_row_count | locality
--------------+------------+-------+-------+---------------------+-----------
  public      | jblob      | table | fabio |                   0 | NULL
(1 row)

Time: 67ms total (execution 34ms / network 33ms)

  count
---------
      1
(1 row)

Time: 36ms total (execution 4ms / network 32ms)
```

Just 1 row! The entire blob has been added to just 1 row, how useful is this within a database? Not much, but we can use it to test the built-in JSONB functions

## Lab 2 - JSONB Functions

Let's practice with some JSONB built-in [functions](https://www.cockroachlabs.com/docs/stable/jsonb#functions).

The JSON blob looks like this:

```json
{
  "myjson_blob": [
    {
      "r_id": 2259,
      "r_c_id": 54043195528453770,
      [...]
    },
    {
      "r_id": 1222,
      "r_c_id": 21673573206743750,
      [...]
    },
    {many more such items}
  ]
}
```

### jsonb_pretty()

It's always nice to start by viewing a JSON object nicely formatted, so we know what we're actually dealing with

```sql
-- here we access the item 0 of the json array
SELECT jsonb_pretty(myblob -> 'myjson_blob' -> 0) FROM jblob WHERE id = 0;
```

```json
                      jsonb_pretty
---------------------------------------------------------
  {
      "c_balance": 7122,
      "c_base_ap_id": 192,
      "c_iattr00": 142027308,
      "c_iattr01": 379685059,
      "c_iattr02": 389136665,
      "c_iattr03": 145392585,
      "c_iattr04": 931118926,
      "c_iattr05": 8816575,
      "c_iattr06": 984249473,
      [...]
      "r_id": 2259,
      "r_price": 978,
      "r_seat": 1
  }
(1 row)
```

### jsonb_each()

This function expands the outermost JSONB object into a set of key-value pairs.

```sql
SELECT jsonb_each(myblob -> 'myjson_blob' -> 0) FROM jblob WHERE id = 0;
```

```text
                      jsonb_each
-------------------------------------------------------
  (c_balance,7122)
  (c_base_ap_id,192)
  (c_iattr00,142027308)
  (c_iattr01,379685059)
  (c_iattr02,389136665)
  (c_iattr03,145392585)
  [...]
```

### jsonb_object_keys()

Returns sorted set of keys in the outermost JSONB object.

```sql
SELECT jsonb_object_keys(myblob -> 'myjson_blob' -> 0) FROM jblob WHERE id = 0;
```

```text
  jsonb_object_keys
---------------------
  c_balance
  c_base_ap_id
  c_iattr00
  c_iattr01
  c_iattr02
  c_iattr03
  c_iattr04
  [...]
```

Cool, good job! We can now drop this table

```sql
DROP TABLE IF EXISTS jblob CASCADE;
```

## Lab 3 - Load table with flattened JSON objects

Create a table with FLATTENED JSONB objects.

```bash
# run the second file, json2.sql
cockroach sql --url "postgresql://<yourname>:<password>@[...]" < json2.sql
```

```sql
USE jsondb;

SHOW TABLES;

SELECT count(*) FROM jflat;
```

```text
SET

Time: 32ms total (execution 0ms / network 32ms)

  schema_name | table_name | type  | owner | estimated_row_count | locality
--------------+------------+-------+-------+---------------------+-----------
  public      | jflat      | table | fabio |                   0 | NULL
(1 row)

Time: 67ms total (execution 34ms / network 32ms)

  count
---------
    110
(1 row)

Time: 35ms total (execution 4ms / network 31ms)
```

The flat file has a total of 110 rows.

## Lab 4 - Practice with the operators

Let's create a query that counts the number with the same `c_base_ap_id`.

Use the [operator](https://www.cockroachlabs.com/docs/stable/jsonb#operators) `->>` to access a JSONB field and returning a string.

```sql
SELECT myflat ->> 'c_base_ap_id' AS c_base_ap_id, count(*) 
FROM jflat 
GROUP BY 1
ORDER BY 2 DESC
LIMIT 5;
```

```text
  c_base_ap_id | count
---------------+--------
  16           |    14
  202          |    10
  131          |     7
  78           |     6
  148          |     6
```

Create a query that sums the `r_price` values by `c_base_ap_id` showing the TOP 10 sums of `r_price`.

```sql
SELECT myflat ->> 'c_base_ap_id' AS c_base_ap_id, 
       SUM(CAST(myflat ->> 'r_price' AS INT)) AS price 
FROM jflat 
GROUP BY 1
ORDER BY 2 DESC
LIMIT 10;
```

```text
  c_base_ap_id | price
---------------+--------
  16           |  8364
  202          |  5351
  148          |  3900
  211          |  3429
  131          |  3020
  78           |  2932
  77           |  2340
  149          |  1996
  60           |  1626
  168          |  1616
```

## Lab 5 - Optimize Query Performance with Inverted Indexes

Insert more data into the `jflat` table:

```bash
# run the third file, json3.sql
# this will take about a minute
cockroach sql --url "postgresql://<yourname>:<password>@[...]" < json3.sql
```

Let's review how many rows we have now in total

```sql
USE jsondb;

SELECT COUNT(*) FROM jflat;
```

```text
  count
---------
   5110
```

Very good, we've a lot more data to work with!

Run the following query.
The operator `@>` tests whether the left JSONB field contains the right JSONB field.

```sql
SELECT id
FROM jflat
WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
```

```text
   id
--------
  3358
  3944
  4179
(3 rows)

Time: 2.011s total (execution 1.811s / network 0.200s)
```

2s, a bit too slow. Check the query plan

```sql
EXPLAIN (VERBOSE) SELECT id FROM jflat WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
```

```text
                                            info
--------------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • project
  │ columns: (id)
  │ estimated row count: 457
  │
  └── • filter
      │ columns: (id, myflat)
      │ estimated row count: 457
      │ filter: myflat @> '{"c_sattr19": "momjzdfu"}'
      │
      └── • scan
            columns: (id, myflat)
            estimated row count: 4,110 (100% of the table; stats collected 33 seconds ago)
            table: jflat@primary
            spans: FULL SCAN
```

As expected, it's doing a FULL SCAN on `primary`, which we always want to avoid.

We can improve the Response Time (RT) by creating [inverted indexes](https://www.cockroachlabs.com/docs/stable/inverted-indexes).

```sql
CREATE INVERTED INDEX idx_json_inverted ON jflat(myflat);
```

Once created, pull the query plan again:

```sql
EXPLAIN (VERBOSE) SELECT id FROM jflat WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
```

```text
                                      info
---------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • scan
    columns: (id)
    estimated row count: 568 (11% of the table; stats collected 24 seconds ago)
    table: jflat@idx_json_inverted
    spans: /"c_sattr19"/"momjzdfu"-/"c_sattr19"/"momjzdfu"/PrefixEnd
```

Good, it's leveraging the inverted index. Run the query gain

```sql
SELECT id FROM jflat WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
```

```text
   id
--------
  3358
  3944
  4179
(3 rows)

Time: 33ms total (execution 2ms / network 31ms)
```

33ms! Great improvement!

## Lab 6 - Joins on JSONB objects

Create a simple table out of `jflat`.

```sql
CREATE TABLE price AS SELECT * FROM jflat LIMIT 3;
```

Check the `r_price` of the inserted rows

```sql
SELECT myflat ->> 'r_price' AS price FROM price;
```

```text
  price
---------
  978
  114
  484
(3 rows)
```

Run below query, to confirm you can do joins on JSONB objects.

```sql
SELECT jflat.myflat ->> 'r_price' AS price 
FROM jflat JOIN price
  ON jflat.myflat ->> 'r_price' = price.myflat ->> 'r_price';
```

```text
  price
---------
  978
  114
  484
  978
  114
  114
  114
  114
  484
  114
  978
  114
  978
  114
  114
(15 rows)
```

While joins are possible on JSONB object, it is recommanded to extract the join field into a **computed column** for efficiency.

We discuss computed columns next.

## Lab 7 - Optimize Aggregrate Performance with Computed Columns

Run the following query:

```sql
SELECT myflat ->> 'c_sattr19' AS attr19, 
       myflat ->> 'r_seat' AS seat, 
       count(*), 
       sum(CAST(myflat ->> 'r_price' AS INT)) 
FROM jflat 
WHERE myflat ->> 'c_sattr19' LIKE '%mom%'
GROUP BY 1,2;
```

```text
   attr19  | seat | count | sum
-----------+------+-------+-------
  momjzdfu | 1    |     2 | 1091
  momjzdfu | 0    |     1 |  659
(2 rows)

Time: 518ms total (execution 486ms / network 31ms)
```

Let's pull the query plan

```sql
EXPLAIN (VERBOSE)
SELECT myflat ->> 'c_sattr19' AS attr19, 
       myflat ->> 'r_seat' AS seat, 
       count(*), 
       sum(CAST(myflat ->> 'r_price' AS INT)) 
FROM jflat 
WHERE myflat ->> 'c_sattr19' LIKE '%mom%'
GROUP BY 1,2;
```

```text
                                             info
----------------------------------------------------------------------------------------------
  distribution: local
  vectorized: true

  • group
  │ columns: (attr19, seat, count, sum)
  │ estimated row count: 1,703
  │ aggregate 0: count_rows()
  │ aggregate 1: sum(column7)
  │ group by: attr19, seat
  │
  └── • render
      │ columns: (column7, attr19, seat)
      │ estimated row count: 1,703
      │ render column7: (myflat->>'r_price')::INT8
      │ render attr19: myflat->>'c_sattr19'
      │ render seat: myflat->>'r_seat'
      │
      └── • filter
          │ columns: (myflat)
          │ estimated row count: 1,703
          │ filter: (myflat->>'c_sattr19') LIKE '%mom%'
          │
          └── • scan
                columns: (myflat)
                estimated row count: 5,110 (100% of the table; stats collected 1 minute ago)
                table: jflat@primary
                spans: FULL SCAN
```

As you can see, it's doing a FULL SCAN: the type of filtering requested is not possible with Inverted Indexes.

We can tune the above query by adding [computed columns](https://www.cockroachlabs.com/docs/stable/computed-columns#create-a-table-with-a-jsonb-column-and-a-computed-column) to the table.

Let's create a copy of the table with computed columns, insert the data, then create an index with the fields specified in the WHERE clause

```sql
CREATE TABLE jflat_new (
    id INT PRIMARY KEY,
    myflat JSONB,
    r_seat STRING AS (myflat::JSONB ->> 'r_seat') STORED,
    attr19 STRING AS (myflat::JSONB ->> 'c_sattr19') STORED,
    r_price INT AS (CAST(myflat::JSONB ->> 'r_price' AS INT)) STORED,
    FAMILY "primary" (id, r_seat, attr19, r_price),
    FAMILY "blob" (myflat)
);

INSERT INTO jflat_new SELECT id, myflat from jflat;

CREATE INDEX ON jflat_new(attr19) STORING (r_seat, r_price);
```

Let's review the table again, to confirm

```sql
SHOW CREATE jflat_new;
```

```text
  table_name |                               create_statement
-------------+-------------------------------------------------------------------------------
  jflat_new  | CREATE TABLE public.jflat_new (
             |     id INT8 NOT NULL,
             |     myflat JSONB NULL,
             |     r_seat STRING NULL AS (myflat->>'r_seat':::STRING) STORED,
             |     attr19 STRING NULL AS (myflat->>'c_sattr19':::STRING) STORED,
             |     r_price INT8 NULL AS (CAST(myflat->>'r_price':::STRING AS INT8)) STORED,
             |     CONSTRAINT "primary" PRIMARY KEY (id ASC),
             |     INDEX jflat_new_attr19_idx (attr19 ASC) STORING (r_seat, r_price),
             |     FAMILY "primary" (id, r_seat, attr19, r_price),
             |     FAMILY blob (myflat)
             | )
```

Now, we can rewrite the query and pull the plan to confirm the optimizer uses the newly created index

```sql
EXPLAIN (VERBOSE)
SELECT attr19,
       r_seat,
       count(*),
       sum(r_price)
FROM jflat_new
WHERE attr19 LIKE '%mom%'
GROUP BY 1,2;
```

```text
                         info
------------------------------------------------------
  distribution: local
  vectorized: true

  • group
  │ columns: (attr19, r_seat, count, sum)
  │ estimated row count: 330 (missing stats)
  │ aggregate 0: count_rows()
  │ aggregate 1: sum(r_price)
  │ group by: r_seat, attr19
  │ ordered: +attr19
  │
  └── • filter
      │ columns: (r_seat, attr19, r_price)
      │ ordering: +attr19
      │ estimated row count: 330 (missing stats)
      │ filter: attr19 LIKE '%mom%'
      │
      └── • scan
            columns: (r_seat, attr19, r_price)
            ordering: +attr19
            estimated row count: 990 (missing stats)
            table: jflat_new@jflat_new_attr19_idx
            spans: /!NULL-
```

Very good, the query plan is using the index. Let's run to see if the RT improved

```sql
SELECT attr19,
       r_seat,
       count(*),
       sum(r_price)
FROM jflat_new
WHERE attr19 LIKE '%mom%'
GROUP BY 1,2;
```

```text
   attr19  | r_seat | count | sum
-----------+--------+-------+-------
  momjzdfu | 1      |     2 | 1091
  momjzdfu | 0      |     1 |  659
(2 rows)

Time: 43ms total (execution 10ms / network 34ms)
```

Very good, down to 43ms, good job!

Congratulations, you reached the end of the labs!

## Clean up

Drop the database if you want to return to the previous state

```sql
USE defaultdb;
DROP DATABASE IF EXISTS jsondb CASCADE;
SHOW DATABASES;
```

## References

Official Docs:

- [JSON Support](https://www.cockroachlabs.com/docs/stable/demo-json-support.html)
- [JSONB data type](https://www.cockroachlabs.com/docs/stable/jsonb.html)
- [Inverted Indexes](https://www.cockroachlabs.com/docs/stable/inverted-indexes.html)
- [Computed Columns](https://www.cockroachlabs.com/docs/stable/computed-columns.html)

Blogs

- [Demystifying JSON with CockroachDB](https://glennfawcett.wpcomstaging.com/2020/02/11/demystifying-json-with-cockroachdb-import-index-and-computed-columns/)
