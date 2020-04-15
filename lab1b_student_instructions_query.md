# Lab1b Query Tuning Workshop

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
* http://35.237.249.82:26258
* http://34.74.60.87:26258
* http://35.243.199.13:26258
* http://35.243.209.78:26258


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
How do you show the query plan?

-- Q1b
--
How do you analyze the query performs?

-- Q1c
--
What can be done to improve the performance of this Query so that it runs in less than 170ms?

-- Q2
--
Connect to the adminurl for the cluster.  The exact URL should be saved as a bookmark or the instructor will display them.

something link this:
* http://35.237.249.82:26258
* http://34.74.60.87:26258
* http://35.243.199.13:26258
* http://35.243.209.78:26258


-- Q2a
--
How big is your database?


-- Q2b
--
Which query is taking the most time?

-- Q2c
--
How much memory is being used on each node of the cluster?