# Lab2 Query Tuning Workshop

In this lab we will experiment with recovering data from a live running cluster without downtime.


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
The following report query is run by a dashboard.  Please run this query and record the results.

```
SELECT h_w_id, count(*) 
FROM history 
WHERE h_w_id < 10 
GROUP BY 1 
ORDER BY 1;
```

When experimenting, someone accidently deleted some data.  Please run the following query:
```
delete from history where h_w_id = 2;
```

Run the report query again to show the missing data.

-- Q1a
--
How can you run the query to retrieve data that has been deleted?


-- Q1b
--
Can you restore the data without restoring a backup?

