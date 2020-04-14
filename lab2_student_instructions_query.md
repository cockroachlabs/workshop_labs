# Lab2 Query Tuning Workshop

In this lab we will experiment we will explore how to use the admin user interface and show how to time travel.


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
The following report query is run the application dashboard.  Please run this query and record the results.

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


-- Q2
--
Connect to the adminurl for the cluster.  The exact URL should be saved as a bookmark or the instructor will display them.

something link this:
* http://34.74.42.167:26258
* http://35.190.131.2:26258
* http://34.73.131.208:26258
* http://35.231.148.130:26258


Once connected answer the following questions.

-- Q2a
--
How big is your database?


-- Q2b
--
Which query is taking the most time?

-- Q2c
--
How much memory is being used on each node of the cluster?

-- Q2d
--
What is the log commit latency?