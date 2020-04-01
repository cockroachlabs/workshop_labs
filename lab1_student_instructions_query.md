# Lab1 Query Tuning Workshop

In this lab we will experiment query tuning techniques to best 
understand how to observe and improve performance.


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
* http://34.74.77.192:26258/
* http://34.74.212.182:26258/
* http://35.231.13.30:26258/
* http://34.73.172.194:26258/
* http://35.243.192.30:26258/


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

This query must run in 12ms or less to be able to keep up with the SLAs for the company dashboard.

-- Q1a
--
How do you show the query plan for this query?

-- Q1b
--
How do you analyze how the query performs when running?

-- Q1c
--
What can be done to improve the performance of this Query so that it runs in less than 12ms?



-- Q2
--
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
