# Lab1 Query Tuning Workshop

The following labs will take you through various query tuning scenarios and allow you to discover various ways to observe, diagnose, and optimize query performance with CockroachDB.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql 

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould in a singe zone:

* us-east4-b

## AdminURL
* http://glenn-querylabs-0002.roachprod.crdb.io:26258/


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Activities & Questions

--  Q1 
--
Run the following query and observe the performance.

```
SELECT ol_number, SUM(ol_quantity) 
FROM order_line 
WHERE ol_w_id > 30
   AND ol_amount > 9990
GROUP BY ol_number 
ORDER BY ol_number;
```

This query must run in less than 1 second!   Note the the location of the client program will effect performance. 
For instance, the following times should be achieved
* DBeaver::  < 200ms
* cockroach (laptop-to-cloud):: < 200ms
* roachprod sql glenn-querylabs:3 --insecure::  < 12ms

-- Q1a
--
How do you show the query plan for this query?  


-- Q1b
--
How to you gather an explain plan /w statistics used by the optimizer?


-- Q1c
--
How do you analyze details of the query runtime performance?


-- Q1d
--
What can be done to improve the performance of this Query so that it runs in less than 170ms?



-- Q2
--
Run the following query:

```
SELECT w_name, w_city, sum(ol_amount) 
FROM order_line
INNER JOIN warehouse ON (w_id = ol_supply_w_id) 
WHERE ol_supply_w_id > 40
GROUP BY 1,2;
```

-- Q2a
--
How does this query join?

-- Q2b
--
Show how to force this query to use all join methods (LOOKUP, HASH, MERGE) ?

-- Q2c
--
How do you make the optimizer choose MERGE join without using a HINT?

-- Q2d
--
How do you force the query to use the primary key and not the indexes?
