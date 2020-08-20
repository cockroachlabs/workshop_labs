# Lab2 Query Tuning Workshop

In this lab we will explore how to use the admin user interface and use time travel queries.


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
The following report query is run to populate a dashboard within your application.  Please run this query and record the results.

```
SELECT h_w_id, count(*) 
FROM history 
WHERE h_w_id < 10 
GROUP BY 1 
ORDER BY 1;
```

When experimenting, someone accidently uploaded some old data with todays date.  Please run the following query:
```
insert into history (h_c_id, h_c_d_id, h_c_w_id, h_d_id, h_w_id, h_date, h_amount, h_data) select h_c_id, h_c_d_id, h_c_w_id, h_d_id, h_w_id, now(), h_amount, h_data from history where h_w_id = 0;
```

Run the report query again to show the additional data.

-- Q1a
--
How can you run the query to exclude the recently added data?


-- Q2
--
Connect to the adminurl for the cluster.  The exact URL should be saved as a bookmark or the instructor will display them.

* http://glenn-querylabs-0002.roachprod.crdb.io:26258/


Once connected answer the following questions.

-- Q2a
--
How big is your database?

-- Q2b
--
How many ranges does the `order_line` table have?

-- Q2c
--
Which query is taking the most time?


-- Q3
--
Run the following the history query again:

```
SELECT h_w_id, count(*) 
FROM history 
WHERE h_w_id < 10 
GROUP BY 1 
ORDER BY 1;
```

-- Q3a
-- 
How do you enable tracing on this query?

-- Q3b
--
Active the tracing on the *history* query and run it again.

```
SELECT h_w_id, count(*) 
FROM history 
WHERE h_w_id < 10 
GROUP BY 1 
ORDER BY 1;
```

Collect the *stmt-bundle* from the AdminUI.

Explore the data gathered for query execution.  This data will be helpful if you are experiencing a performance issues and need advise from Cockroach Labs.

-- Extra Credit
--
Use the Jaeger UI to view the trace-jaeger.json file collected in the statement bundle.

