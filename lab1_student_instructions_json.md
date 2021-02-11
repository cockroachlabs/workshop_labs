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



## Activity #1 -- Import TABLE with big JSON object

Create a table by importing a CSV file from a cloud storage bucket.

```sql

IMPORT TABLE jblob (
    id INT PRIMARY KEY,
    myblob JSONB
) CSV DATA ('https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/JSON-optimization/data/raw_test_blob.tsv')
WITH
    delimiter = e'\t';

```

### Q1
* How many json objects were imported?  
* How useful is this within a database?


## Activity #2 -- Import Table with Flattened JSON objects

Create a table with FLATTENED JSONB objects by importing a CSV file from a cloud storage bucket.  This CSV file was created by a python3 script to read the JSON
file and extract all values into rows.

```sql

IMPORT TABLE jflat (
    id INT PRIMARY KEY,
    myflat JSONB
) CSV DATA ('https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/JSON-optimization/data/raw_test_flat.tsv')
WITH
    delimiter = e'\t';

```

### Q2
* How many json objects were imported?

### Q3
* Create a query that counts the number with the same `c_base_ap_id`.

### Q4
* Create a query that sums the `r_price` values by `c_base_ap_id` showing the TOP 10 sums of `r_price`.


## Activity #3 -- Import more data into jflat table

Import more data into the `jflat` table:

```sql

IMPORT INTO jflat (id, myflat)
CSV DATA (
    'https://raw.githubusercontent.com/cockroachlabs/workshop_labs/master/JSON-optimization/data/raw_test_flat2.tsv'
)
WITH
    delimiter = e'\t';

```

### Q5
* How many json objects are in the table now?

## Activity #4 -- Optimize Query Performance

Run the following query:
```sql
SELECT id FROM jflat WHERE myflat::JSONB @> '{"c_sattr19": "momjzdfu"}';
```

### Q6
* How much can you improve the performance of the above query?  Show the query, DDL and amount of improvement.

## Activity #5 -- Observe and Optimize Aggregrate Performance

Run the following query:
```sql
select myflat::JSONB->>'c_sattr19' as attr19, 
       myflat::JSONB->>'r_seat' as seat, 
       count(*), 
       sum(CAST(myflat::JSONB->>'r_price' as INT)) 
from jflat 
where myflat::JSONB->>'c_sattr19' like '%mom%'
group by 1,2;
```

### Q6
* What is the response time of the above query?

### Q7
* Does the above query use any indexes?

### Q8
Tune the above query.  You can add Indexes and/or columns to the table.  Feel free to create a new table as well and poplulate from the original table.

* How much can you improve the performance of the above query?  Show the query, DDL and amount of improvement.

## Activity #6 -- 

Consider the following query:
```sql
SELECT id from jflat where myflat::JSONB @> '{"c_sattr19": "momjzdfu"}';
```

### Q9
Is it faster to use an `INVERTED INDEX` or create a *computed* column with an index?


## Extra Credit 

Using the [companies.json](https://raw.githubusercontent.com/ozlerhakan/mongodb-json-files/master/datasets/companies.json) file, create a table in CockroachDB to include the JSON object.  Modify the table to create the most performant queries possible to calculate the following:

* Top 10 highest aquisition prices by Year and Aquiring Company in USD.  Include the aquiring company name, aquisition year, and SUM of the total amount spent that year.

* Explore multiple methods to improve performance
* * Raw JSON
* * JSON with Computed Columns
* * JSON with Inverted Indexes
