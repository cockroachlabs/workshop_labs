# Lab1 JSON Workshop

In this lab we will experiment we will explore how to use the JSONB objects within CockroachDB.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql 

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould in a singe zone:

* us-east4-b


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Activities & Questions

--  Q1
--
Create a table by importing a CSV file from a cloud storage bucket.

```
IMPORT TABLE jblob (
    id INT PRIMARY KEY,
    myblob JSONB
) CSV DATA ('gs://crdb_json/raw/test_blob.tsv')
WITH
    delimiter = e'\t';
```

-- Q1a
-- 
How many rows were imported?  How useful is this within a database?


-- Q2
--
Create a table with FLATTENED JSONB objects by importing a CSV file from a cloud storage bucket.  This CSV file was created by a python3 script to read the JSON
file and extract all values into rows.

```
IMPORT TABLE jflat (
    id INT PRIMARY KEY,
    myflat JSONB
) CSV DATA ('gs://crdb_json/raw/test_flat.tsv')
WITH
    delimiter = e'\t';
```

-- Q2a
--
How many json object were imported?

-- Q2b
--
Create a query that counts the number of values of the same `c_base_ap_id` and show the SQL.

-- Q2c
--
Create a query that sums the `r_price` value by `c_base_ap_id`


-- Q3
--
Import more data into the `jflat` table:
```
IMPORT INTO jflat (id, myflat)
CSV DATA (
    'gs://crdb_json/raw/test_flat2.tsv'
)
WITH
    delimiter = e'\t';
```

-- Q3a
--
How many rows are in the table now?

-- Q4
--
Run the following query:
```
SELECT id FROM jflat WHERE myflat::JSONB @> '{"c_sattr19": "momjzdfu"}';
```

-- Q4a
--
How can you improve the performance of the above query?

-- Q4b
--
What is the performance difference after tuning?

-- Q5
--
Run the following query:
```
select myflat::JSONB->>'c_sattr19' as attr19, 
       myflat::JSONB->>'r_seat' as seat, 
       count(*), 
       sum(CAST(myflat::JSONB->>'r_price' as INT)) 
from jflat 
where myflat::JSONB->>'c_sattr19' like '%mom%'
group by 1,2;
```

-- Q5a
--
What is the response time of the above query?

-- Q5b
--
Does the above query use any indexes?

-- Q5c
--
Tune the above query.  You can add Indexes and/or columns to the table.  Feel free to create a new table as well and poplulate from the original table.

What is the DDL?

What improvements were made?

-- Q6
--
Consider the following query:
```
SELECT id from jflat where myflat::JSONB @> '{"c_sattr19": "momjzdfu"}';
```

-- Q6a
--
Is it faster to use an `INVERTED INDEX` or create a *computed* column on this value with an index?
