# JSON Optimization - Student Labs

## Overview

CockroachDB supports operation on JSON objects. In these labs, we will get familiar with working with the JSONB data type, as well as with ways to optimize queries with JSONB objects.

## Labs Prerequisites

1. Build the single region dev cluster following [these instructions](/infrastructure/single-region-local-docker-cluster.md).

2. You also need:

    - a modern web browser,
    - a SQL client:
      - [Cockroach SQL client](https://www.cockroachlabs.com/docs/stable/install-cockroachdb-linux)
      - `psql`
      - [DBeaver Community edition](https://dbeaver.io/download/) (SQL tool with built-in CockroachDB plugin)

## Lab 1 - Import TABLE with big JSON object

Connect to the database to confirm it loaded successfully

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure

# or use the --url param for any another host:
cockroach sql --url "postgresql://localhost:26257/defaultdb?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root defaultdb
```

Create a table by importing a CSV file from a cloud storage bucket.

```sql
IMPORT TABLE jblob (
    id INT PRIMARY KEY,
    myblob JSONB
) CSV DATA ('https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/data/raw_test_blob.tsv')
WITH
    delimiter = e'\t';
```

Check how many JSON objects were imported:

```text
        job_id       |  status   | fraction_completed | rows | index_entries | bytes
---------------------+-----------+--------------------+------+---------------+---------
  624769960352055297 | succeeded |                  1 |    1 |             0 | 261102
(1 row)

Time: 504ms total (execution 503ms / network 1ms)
```

Just 1 row! The entire blob has been added to just 1 row, how useful is this within a database? Not much, but we can use it to test the built-in JSONB functions

## Lab 2 - JSONB Functions

Let's practice with some JSONB built-in functions.

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
      "c_iattr07": 116663385,
      "c_iattr08": 907154685,
      "c_iattr09": 15899371,
      "c_iattr10": 648717549,
      "c_iattr11": 724567744,
      "c_iattr12": 1051370766,
      "c_iattr13": 50210225,
      "c_iattr14": 451755713,
      "c_iattr15": 982547218,
      "c_iattr16": 543188731,
      "c_iattr17": 564981351,
      "c_iattr18": 471058604,
      "c_iattr19": 759207747,
      "c_id": 54043195528453770,
      "c_id_str": 54043195528453770,
      "c_sattr00": "whtzcyuhoywdeigoqvrivmlhedp",
      "c_sattr01": "xkqenedl",
      "c_sattr02": "ppbphg",
      "c_sattr03": "alxslwmk",
      "c_sattr04": "xovvm",
      "c_sattr05": "xkj",
      "c_sattr06": "tfywzzd",
      "c_sattr07": "jpry",
      "c_sattr08": "nvlbkmg",
      "c_sattr09": "lrxjgzd",
      "c_sattr10": "otolyrq",
      "c_sattr11": "znzk",
      "c_sattr12": "viyqtkm",
      "c_sattr13": "cujp",
      "c_sattr14": "kutbaoda",
      "c_sattr15": "nbuuodbh",
      "c_sattr16": "hdvftpl",
      "c_sattr17": "n",
      "c_sattr18": "ri",
      "c_sattr19": "yukz",
      "f_al_id": 363,
      "f_arrive_ap_id": 16,
      "f_arrive_time": "2020-01-06 17:10:20.962+00:00",
      "f_base_price": 258,
      "f_depart_ap_id": 192,
      "f_depart_time": "2019-10-15 09:10:20.962+00:00",
      "f_iattr00": 8520160,
      "f_iattr01": 675846595,
      "f_iattr02": 504955969,
      "f_iattr03": 767109370,
      "f_iattr04": 707645173,
      "f_iattr05": 340637155,
      "f_iattr06": 304036642,
      "f_iattr07": 421641226,
      "f_iattr08": 440205470,
      "f_iattr09": 413668930,
      "f_iattr10": 712127756,
      "f_iattr11": 51274104,
      "f_iattr12": 641344442,
      "f_iattr13": 862018850,
      "f_iattr14": 386515711,
      "f_iattr15": 840809361,
      "f_iattr16": 916318900,
      "f_iattr17": 418637645,
      "f_iattr18": 515763995,
      "f_iattr19": 967932899,
      "f_iattr20": 586772453,
      "f_iattr21": 713528331,
      "f_iattr22": 993065765,
      "f_iattr23": 234788091,
      "f_iattr24": 343690263,
      "f_iattr25": 289777773,
      "f_iattr26": 1066280989,
      "f_iattr27": 842571001,
      "f_iattr28": 506399830,
      "f_iattr29": 637903749,
      "f_id": 422229648081259,
      "f_seats_left": 147,
      "f_seats_total": 150,
      "f_status": 0,
      "r_c_id": 54043195528453770,
      "r_f_id": 422229648081259,
      "r_iattr00": 673352173,
      "r_iattr01": 355513020,
      "r_iattr02": 209823742,
      "r_iattr03": 772737207,
      "r_iattr04": 199858911,
      "r_iattr05": 737503122,
      "r_iattr06": 945498537,
      "r_iattr07": 824685761,
      "r_iattr08": 810968743,
      "r_id": 2259,
      "r_price": 978,
      "r_seat": 1
  }
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

## Lab 3 - Import Table with Flattened JSON objects

Create a table with FLATTENED JSONB objects by importing a CSV file from a cloud storage bucket.
This CSV file was pre-processed to read the JSON file and extract all values into rows, below the code for reference

```python
import json

# will work only if you have enough Memory to read the entire file
with open('file.json') as f:
    data = json.load(f)

with open('file.tsv', 'w') as f:
    [f.write('{}\t{}\n'.format(i, json.dumps(data[i], separators=(',', ':')))) for i in range(len(data))]
```

At the SQL prompt, import the data

```sql
IMPORT TABLE jflat (
    id INT PRIMARY KEY,
    myflat JSONB
) CSV DATA ('https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/data/raw_test_flat.tsv')
WITH
    delimiter = e'\t';
```

```text
        job_id       |  status   | fraction_completed | rows | index_entries | bytes
---------------------+-----------+--------------------+------+---------------+---------
  624770775819517953 | succeeded |                  1 |  110 |             0 | 262051
```

The flat file has a total of 110 rows.

## Lab 4 - Practice with the operators

Let's create a query that counts the number with the same `c_base_ap_id`.

Use the operator `->>` to access a JSONB field and returning a string.

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

Import more data into the `jflat` table:

```sql
IMPORT INTO jflat (id, myflat)
CSV DATA (
    'https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/data/raw_test_flat2.tsv'
)
WITH
    delimiter = e'\t';
```

Let's review how many rows we have now in total

```sql
SELECT COUNT(*) FROM jflat;
```

```text
  count
---------
  15939
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
---------
   3358
   3944
   4179
   6475
  16007
  16501
(6 rows)

Time: 557ms total (execution 554ms / network 2ms)
```

557ms, a bit too slow. Check the query plan

```sql
EXPLAIN (VERBOSE) SELECT id FROM jflat WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
```

```text
       tree      |        field        |              description              |   columns    | ordering
-----------------+---------------------+---------------------------------------+--------------+-----------
                 | distribution        | full                                  |              |
                 | vectorized          | true                                  |              |
  project        |                     |                                       | (id)         |
   │             | estimated row count | 1771                                  |              |
   └── filter    |                     |                                       | (id, myflat) |
        │        | estimated row count | 1771                                  |              |
        │        | filter              | myflat @> '{"c_sattr19": "momjzdfu"}' |              |
        └── scan |                     |                                       | (id, myflat) |
                 | estimated row count | 15939                                 |              |
                 | table               | jflat@primary                         |              |
                 | spans               | FULL SCAN                             |              |

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
  tree |        field        |                        description                        | columns | ordering
-------+---------------------+-----------------------------------------------------------+---------+-----------
       | distribution        | local                                                     |         |
       | vectorized          | true                                                      |         |
  scan |                     |                                                           | (id)    |
       | estimated row count | 1771                                                      |         |
       | table               | jflat@idx_json_inverted                                   |         |
       | spans               | /"c_sattr19"/"momjzdfu"-/"c_sattr19"/"momjzdfu"/PrefixEnd |         |
```

Good, it's leveraging the inverted index. Run the query gain

```sql
SELECT id FROM jflat WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
```

```text
   id
---------
   3358
   3944
   4179
   6475
  16007
  16501
(6 rows)

Time: 1ms total (execution 13ms / network 1ms)
```

1ms! Great improvement!

## Lab 6 - Optimize Aggregrate Performance with Computed Columns

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
  momjzdfu | 0    |     3 | 1747
  momjzdfu | 2    |     1 |  865
(3 rows)

Time: 76ms total (execution 74ms / network 1ms)
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
         tree         |        field        |             description             |          columns           | ordering
----------------------+---------------------+-------------------------------------+----------------------------+-----------
                      | distribution        | full                                |                            |
                      | vectorized          | true                                |                            |
  group               |                     |                                     | (attr19, seat, count, sum) |
   │                  | estimated row count | 5313                                |                            |
   │                  | aggregate 0         | count_rows()                        |                            |
   │                  | aggregate 1         | sum(column7)                        |                            |
   │                  | group by            | attr19, seat                        |                            |
   └── render         |                     |                                     | (column7, attr19, seat)    |
        │             | estimated row count | 5313                                |                            |
        │             | render 0            | (myflat->>'r_price')::INT8          |                            |
        │             | render 1            | myflat->>'c_sattr19'                |                            |
        │             | render 2            | myflat->>'r_seat'                   |                            |
        └── filter    |                     |                                     | (myflat)                   |
             │        | estimated row count | 5313                                |                            |
             │        | filter              | (myflat->>'c_sattr19') LIKE '%mom%' |                            |
             └── scan |                     |                                     | (myflat)                   |
                      | estimated row count | 15939                               |                            |
                      | table               | jflat@primary                       |                            |
                      | spans               | FULL SCAN                           |                            |

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
       tree      |        field        |          description           |           columns            | ordering
-----------------+---------------------+--------------------------------+------------------------------+-----------
                 | distribution        | full                           |                              |
                 | vectorized          | true                           |                              |
  group          |                     |                                | (attr19, r_seat, count, sum) |
   │             | estimated row count | 4111                           |                              |
   │             | aggregate 0         | count_rows()                   |                              |
   │             | aggregate 1         | sum(r_price)                   |                              |
   │             | group by            | r_seat, attr19                 |                              |
   │             | ordered             | +attr19                        |                              |
   └── filter    |                     |                                | (r_seat, attr19, r_price)    | +attr19
        │        | estimated row count | 5313                           |                              |
        │        | filter              | attr19 LIKE '%mom%'            |                              |
        └── scan |                     |                                | (r_seat, attr19, r_price)    | +attr19
                 | estimated row count | 15939                          |                              |
                 | table               | jflat_new@jflat_new_attr19_idx |                              |
                 | spans               | /!NULL-                        |                              |

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
  momjzdfu | 0      |     3 | 1747
  momjzdfu | 1      |     2 | 1091
  momjzdfu | 2      |     1 |  865
(3 rows)

Time: 10ms total (execution 9ms / network 1ms)
```

Very good, from 76ms down to 10ms, good job!

## Lab 7 - Compare RT

Consider the following queries, which yield the same result

```sql
SELECT id FROM jflat WHERE myflat @> '{"c_sattr19": "momjzdfu"}';
SELECT id FROM jflat_new WHERE attr19 = 'momjzdfu';
```

```text
   id
---------
   3358
   3944
   4179
   6475
  16007
  16501
(6 rows)

Time: 15ms total (execution 14ms / network 2ms)

   id
---------
   3944
   6475
  16501
   3358
   4179
  16007
(6 rows)

Time: 2ms total (execution 1ms / network 1ms)
```

It's very clear that the query that leverage the computed columns + index is far more performant than the Inverted index option.

## References

Official Docs:

- [JSON Support](https://www.cockroachlabs.com/docs/stable/demo-json-support.html)
- [JSONB data type](https://www.cockroachlabs.com/docs/stable/jsonb.html)
- [Inverted Indexes](https://www.cockroachlabs.com/docs/stable/inverted-indexes.html)
- [Computed Columns](https://www.cockroachlabs.com/docs/stable/computed-columns.html)

Blogs

- [Demystifying JSON with CockroachDB](https://glennfawcett.wpcomstaging.com/2020/02/11/demystifying-json-with-cockroachdb-import-index-and-computed-columns/)
