# Extra labs

Here's another troubleshooting exercise.

## Labs Prerequisites

### Local Deployment

Create a [3 node cluster](/infrastructure/single-region-local-docker-cluster.md).

Connect to the database

```bash
# use cockroach sql, defaults to localhost:26257
cockroach sql --insecure

# or use the --url param for any another host:
cockroach sql --url "postgresql://localhost:26257/defaultdb?sslmode=disable"

# or use psql
psql -h localhost -p 26257 -U root defaultdb
```

### Shared Cluster Deployment

SSH into the Jumpbox using the IP address provided by the Instructor.

Connect to the database

```bash
cockroach sql --insecure
```

At the SQL prompt, create and use your database

```sql
CREATE DATABASE <your-name>;
USE <your-name>;
```

## Lab 0

Import the data and load stats

```sql
IMPORT TABLE a (
    id UUID NOT NULL,
    alpha STRING NOT NULL,
    bravo BOOL NOT NULL,
    charlie STRING NULL,
    delta BOOL NOT NULL,
    echo UUID NULL,
    foxtrot STRING NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (id ASC),
    INDEX a_foxtrot_delta_bravo_idx (foxtrot ASC, delta ASC, bravo ASC),
    INDEX a_echo_idx (echo ASC),
    FAMILY "primary" (id, alpha, bravo, charlie, delta, echo, foxtrot)
) CSV DATA (
    'https://github.com/cockroachlabs/workshop_labs/raw/master/troubleshooting/data/a.csv.gz'
) WITH skip = '1';

IMPORT TABLE m (
    echo UUID NOT NULL,
    id UUID NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (echo ASC, id ASC),
    INDEX m_id_echo_idx (id ASC, echo ASC),
    FAMILY "primary" (echo, id)
) CSV DATA (
    'https://github.com/cockroachlabs/workshop_labs/raw/master/troubleshooting/data/m.csv.gz'
) WITH skip = '1';

IMPORT TABLE u (
    id UUID NOT NULL,
    golf STRING NOT NULL,
    CONSTRAINT "primary" PRIMARY KEY (id ASC),
    INDEX u_golf_idx (golf ASC, id ASC),
    FAMILY "primary" (id, golf)
) CSV DATA (
    'https://github.com/cockroachlabs/workshop_labs/raw/master/troubleshooting/data/u.csv.gz'
) WITH skip = '1';

CREATE STATISTICS statu FROM u;
CREATE STATISTICS stata FROM a;
CREATE STATISTICS statm FROM m;
```

Perfect, good job, we've replicated the schema locally with some dummy data.

## Optimization

Below is the query the customer is running. Examine the query plan

```sql
-- very slow query
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = '106718'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN (SELECT echo 
        FROM m
        WHERE id = (SELECT id FROM u WHERE golf = 'N722855')
        );
```

```text
              tree             |        field        |                description                |                  columns                   | ordering
-------------------------------+---------------------+-------------------------------------------+--------------------------------------------+-----------
                               | distribution        | full                                      |                                            |
                               | vectorized          | false                                     |                                            |
  root                         |                     |                                           | (id, charlie)                              |
   ├── project                 |                     |                                           | (id, charlie)                              |
   │    │                      | estimated row count | 1                                         |                                            |
   │    └── lookup join (semi) |                     |                                           | (id, bravo, charlie, delta, echo, foxtrot) |
   │         │                 | estimated row count | 1                                         |                                            |
   │         │                 | table               | m@primary                                 |                                            |
   │         │                 | equality            | (echo) = (echo)                           |                                            |
   │         │                 | pred                | id = @S1                                  |                                            |
   │         └── index join    |                     |                                           | (id, bravo, charlie, delta, echo, foxtrot) |
   │              │            | estimated row count | 1                                         |                                            |
   │              │            | table               | a@primary                                 |                                            |
   │              │            | key columns         | id                                        |                                            |
   │              └── scan     |                     |                                           | (id, bravo, delta, foxtrot)                |
   │                           | estimated row count | 1                                         |                                            |
   │                           | table               | a@a_foxtrot_delta_bravo_idx               |                                            |
   │                           | spans               | /"106718"/1/0-/"106718"/1/1               |                                            |
   └── subquery                |                     |                                           |                                            |
        │                      | id                  | @S1                                       |                                            |
        │                      | original sql        | (SELECT id FROM u WHERE golf = 'N722855') |                                            |
        │                      | exec mode           | one row                                   |                                            |
        └── max1row            |                     |                                           | (id)                                       |
             │                 | estimated row count | 1                                         |                                            |
             └── project       |                     |                                           | (id)                                       |
                  │            | estimated row count | 1                                         |                                            |
                  └── scan     |                     |                                           | (id, golf)                                 |
                               | estimated row count | 1                                         |                                            |
                               | table               | u@u_golf_idx                              |                                            |
                               | spans               | /"N722855"-/"N722855"/PrefixEnd           |                                            |

```

Ok, that's a bit complex, there are 3 nested queries. Let's break it down one by one

### Index Join

Let's pull the plan again, hardcoding the values returned by the two subqueries. We know that the return value is an array of UUIDs.

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = '106718'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN ('e3e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07ce', '13e70682-c209-4cac-a29f-6fbed82c07cd');
```

```text
          tree         |        field        |                                                           description                                                            |                  columns                   | ordering
-----------------------+---------------------+----------------------------------------------------------------------------------------------------------------------------------+--------------------------------------------+-----------
                       | distribution        | local                                                                                                                            |                                            |
                       | vectorized          | false                                                                                                                            |                                            |
  project              |                     |                                                                                                                                  | (id, charlie)                              |
   │                   | estimated row count | 1                                                                                                                                |                                            |
   └── filter          |                     |                                                                                                                                  | (id, bravo, charlie, delta, echo, foxtrot) |
        │              | estimated row count | 1                                                                                                                                |                                            |
        │              | filter              | echo IN ('13e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07cd', 'e3e70682-c209-4cac-a29f-6fbed82c07ce') |                                            |
        └── index join |                     |                                                                                                                                  | (id, bravo, charlie, delta, echo, foxtrot) |
             │         | estimated row count | 1                                                                                                                                |                                            |
             │         | table               | a@primary                                                                                                                        |                                            |
             │         | key columns         | id                                                                                                                               |                                            |
             └── scan  |                     |                                                                                                                                  | (id, bravo, delta, foxtrot)                |
                       | estimated row count | 1                                                                                                                                |                                            |
                       | table               | a@a_foxtrot_delta_bravo_idx                                                                                                      |                                            |
                       | spans               | /"106718"/1/0-/"106718"/1/1                                                                                                      |                                            |
```

We have an index join, which is used to fetch from index/table `a@primary` the fields missing from the index `a@a_foxtrot_delta_bravo_idx`, used to filter for field `echo`.

This is easely fixable: let's recreate index `a@a_foxtrot_delta_bravo_idx` to include the missing field, `charlie`.

```sql
-- recreate the index
DROP INDEX a_foxtrot_delta_bravo_idx;
-- we don't really need to explicitly id, as it is added implicitly
CREATE INDEX a_foxtrot_delta_bravo_echo_idx on a(foxtrot ASC, delta ASC, bravo ASC, echo ASC) storing (charlie);

-- confirm id have been added, just so you know
SHOW INDEXES FROM a;
```

```text
  table_name |           index_name           | non_unique | seq_in_index | column_name | direction | storing | implicit
-------------+--------------------------------+------------+--------------+-------------+-----------+---------+-----------
  a          | primary                        |   false    |            1 | id          | ASC       |  false  |  false
  a          | a_echo_idx                     |    true    |            1 | echo        | ASC       |  false  |  false
  a          | a_echo_idx                     |    true    |            2 | id          | ASC       |  false  |   true
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            1 | foxtrot     | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            2 | delta       | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            3 | bravo       | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            4 | echo        | ASC       |  false  |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            5 | charlie     | N/A       |  true   |  false
  a          | a_foxtrot_delta_bravo_echo_idx |    true    |            6 | id          | ASC       |  false  |   true
```

Pull the query plan again, and you should see that an index-join is no longer required

```text
    tree    |        field        |             description                              |                  columns                   | ordering
------------+---------------------+------------------------------------------------------+--------------------------------------------+-----------
            | distribution        | local                                                |                                            |
            | vectorized          | false                                                |                                            |
  project   |                     |                                                      | (id, charlie)                              |
   │        | estimated row count | 1                                                    |                                            |
   └── scan |                     |                                                      | (id, bravo, charlie, delta, echo, foxtrot) |
            | estimated row count | 1                                                    |                                            |
            | table               | a@a_foxtrot_delta_bravo_echo_idx                     |                                            |
            | spans               | /"106718   <---SHORTENED!! -->  xc2\tLPce"/PrefixEnd |                                            |
```

Good, that was easy! Always look out for index-joins, and for ways to rearrange the order of the fields that compose your key to be as efficient as possible:
in this case, the most uncommon field is `foxtrot`, so we put it at the beginning of our index key so the opt can filter out as many rows, and as quickly, as possible.

### Subquery

Let's pull the plan for the child subquery, the innermost of the two.

```sql
EXPLAIN (VERBOSE) SELECT id FROM u WHERE golf = 'N722855';
```

```text
    tree    |        field        |           description           |  columns   | ordering
------------+---------------------+---------------------------------+------------+-----------
            | distribution        | local                           |            |
            | vectorized          | false                           |            |
  project   |                     |                                 | (id)       |
   │        | estimated row count | 1                               |            |
   └── scan |                     |                                 | (id, golf) |
            | estimated row count | 1                               |            |
            | table               | u@u_golf_idx                    |            |
            | spans               | /"N722855"-/"N722855"/PrefixEnd |            |
```

Perfect, we see that the optimizer is correctly using the index.

Let's pull the plan for its parent

```sql
EXPLAIN (VERBOSE) SELECT echo
FROM m
WHERE id = (
  SELECT id FROM u WHERE golf = 'N722855');
```

```text
            tree           |        field        |                description                |  columns   | ordering
---------------------------+---------------------+-------------------------------------------+------------+-----------
                           | distribution        | full                                      |            |
                           | vectorized          | true                                      |            |
  root                     |                     |                                           | (echo)     |
   ├── project             |                     |                                           | (echo)     |
   │    │                  | estimated row count | 333333                                    |            |
   │    └── filter         |                     |                                           | (echo, id) |
   │         │             | estimated row count | 333333                                    |            |
   │         │             | filter              | id = @S1                                  |            |
   │         └── scan      |                     |                                           | (echo, id) |
   │                       | estimated row count | 1000000                                   |            |
   │                       | table               | m@primary                                 |            |
   │                       | spans               | FULL SCAN                                 |            |
   └── subquery            |                     |                                           |            |
        │                  | id                  | @S1                                       |            |
        │                  | original sql        | (SELECT id FROM u WHERE golf = 'N722855') |            |
        │                  | exec mode           | one row                                   |            |
        └── max1row        |                     |                                           | (id)       |
             │             | estimated row count | 1                                         |            |
             └── project   |                     |                                           | (id)       |
                  │        | estimated row count | 1                                         |            |
                  └── scan |                     |                                           | (id, golf) |
                           | estimated row count | 1                                         |            |
                           | table               | u@u_golf_idx                              |            |
                           | spans               | /"N722855"-/"N722855"/PrefixEnd           |            |
```

Full scan, why? The child subquery returns 1 value, and we have indexes on both fields of table `m`. So why is it doing a full scan?

Confirm the indexes are actually accounted by the optimizer by replacing the subquery with an actual value

```sql
-- using a random UUID instead of subquery
EXPLAIN (VERBOSE) SELECT echo
FROM m
WHERE id = 'e3e70682-c209-4cac-a29f-6fbed82c07cd';
```

```text
    tree    |        field        |                                                       description                                                       |  columns   | ordering
------------+---------------------+-------------------------------------------------------------------------------------------------------------------------+------------+-----------
            | distribution        | local                                                                                                                   |            |
            | vectorized          | false                                                                                                                   |            |
  project   |                     |                                                                                                                         | (echo)     |
   │        | estimated row count | 1                                                                                                                       |            |
   └── scan |                     |                                                                                                                         | (echo, id) |
            | estimated row count | 1                                                                                                                       |            |
            | table               | m@m_id_echo_idx                                                                                                         |            |
            | spans               | /"\xe3\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"-/"\xe3\xe7\x06\x82\xc2\tL\xac\xa2\x9fo\xbe\xd8,\a\xcd"/PrefixEnd |            |
```

Ok, the Opt is using the index as expected, but it doesn't with the subquery.
You raise this issue with CockroachDB Support, and they confirm you run into a known issue, [7042](https://github.com/cockroachdb/cockroach/issues/7042).

The workaround to fix this, is to rewrite your query to avoid subqueries.

You rewrite your queries, and came up with below proposed implementations

### Using IN()

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a
WHERE a.foxtrot = 'y4xbSD8ufOGYW3I'
  AND a.delta = true
  AND a.bravo = false
  AND a.echo
    IN (SELECT m.echo FROM m INNER JOIN u ON m.id = u.id AND u.golf = 'ABCDEF');
```

```text
              tree              |        field        |                  description                  |                  columns                   | ordering
--------------------------------+---------------------+-----------------------------------------------+--------------------------------------------+-----------
                                | distribution        | full                                          |                                            |
                                | vectorized          | false                                         |                                            |
  project                       |                     |                                               | (id, charlie)                              |
   │                            | estimated row count | 1                                             |                                            |
   └── hash join (semi)         |                     |                                               | (id, bravo, charlie, delta, echo, foxtrot) |
        │                       | estimated row count | 1                                             |                                            |
        │                       | equality            | (echo) = (echo)                               |                                            |
        ├── scan                |                     |                                               | (id, bravo, charlie, delta, echo, foxtrot) |
        │                       | estimated row count | 1                                             |                                            |
        │                       | table               | a@a_foxtrot_delta_bravo_echo_idx              |                                            |
        │                       | spans               | /"y4xbSD8ufOGYW3I"/1/0-/"y4xbSD8ufOGYW3I"/1/1 |                                            |
        └── lookup join (inner) |                     |                                               | (id, golf, echo, id)                       |
             │                  | estimated row count | 1                                             |                                            |
             │                  | table               | m@m_id_echo_idx                               |                                            |
             │                  | equality            | (id) = (id)                                   |                                            |
             └── scan           |                     |                                               | (id, golf)                                 |
                                | estimated row count | 1                                             |                                            |
                                | table               | u@u_golf_idx                                  |                                            |
                                | spans               | /"ABCDEF"-/"ABCDEF"/PrefixEnd                 |                                            |

```

### Using 3 joins

```sql
EXPLAIN (VERBOSE) SELECT a.id, a.charlie
FROM a INNER JOIN m ON a.echo = m.echo INNER JOIN u ON m.id = u.id
WHERE a.foxtrot = 'y4xbSD8ufOGYW3I'
  AND a.delta = true
  AND a.bravo = false
  and u.golf = 'ABCDEF';
```

```text
              tree              |        field        |                  description                  |                            columns                             | ordering
--------------------------------+---------------------+-----------------------------------------------+----------------------------------------------------------------+-----------
                                | distribution        | full                                          |                                                                |
                                | vectorized          | false                                         |                                                                |
  project                       |                     |                                               | (id, charlie)                                                  |
   │                            | estimated row count | 1                                             |                                                                |
   └── hash join (inner)        |                     |                                               | (id, bravo, charlie, delta, echo, foxtrot, echo, id, id, golf) |
        │                       | estimated row count | 1                                             |                                                                |
        │                       | equality            | (id) = (id)                                   |                                                                |
        │                       | right cols are key  |                                               |                                                                |
        ├── lookup join (inner) |                     |                                               | (id, bravo, charlie, delta, echo, foxtrot, echo, id)           |
        │    │                  | estimated row count | 1                                             |                                                                |
        │    │                  | table               | m@primary                                     |                                                                |
        │    │                  | equality            | (echo) = (echo)                               |                                                                |
        │    └── scan           |                     |                                               | (id, bravo, charlie, delta, echo, foxtrot)                     |
        │                       | estimated row count | 1                                             |                                                                |
        │                       | table               | a@a_foxtrot_delta_bravo_echo_idx              |                                                                |
        │                       | spans               | /"y4xbSD8ufOGYW3I"/1/0-/"y4xbSD8ufOGYW3I"/1/1 |                                                                |
        └── scan                |                     |                                               | (id, golf)                                                     |
                                | estimated row count | 1                                             |                                                                |
                                | table               | u@u_golf_idx                                  |                                                                |
                                | spans               | /"ABCDEF"-/"ABCDEF"/PrefixEnd                 |                                                                |
```

Congratulations, you reached the end of this exercise! What's left to be done, is testing these above 2 solutions in the real cluster and see how they perform.
Then, you can always iterate over the troubleshooting exercise to further fine tune your query.

## Reference

We use [carota](https://pypi.org/project/carota/) to generate the random datasets.

```bash
# install pip3
sudo apt-get update && sudo apt-get install python3-pip -y
# install carota
pip3 install --user --upgrade pip carota
export PATH=/home/ubuntu/.local/bin:$PATH

# create the dummy data
carota -r 5000 -t "uuid; string::size=15; choices::list=true false; string::size=15; choices::list=true false; uuid; string::size=15" -o a.csv
carota -r 1000000 -t "uuid; uuid" -o m.csv
carota -r 300000 -t "uuid; string::size=7" -o u.csv
```
