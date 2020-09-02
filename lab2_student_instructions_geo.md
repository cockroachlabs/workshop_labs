# Lab2 Geo Partitioning

In this lab we will experiment with Geo Partitioning to best understand how to observe and improve performance with Follower Reads and Local Indexes.


## Connecting to CRDB

* DBeaver
* ./cockroach sql --insecure
* psql 

## Connect Info Sheet

*Student, Database, pgurl, adminurl*


## Cluster Configuration
The lab cluster is configured in Google Clould using the following regions:

* us-west1
* us-east4
* europe-west2


## Command Crib Sheet

https://github.com/glennfawcett/roachcrib



## Activity #1 --  Configuring "follower reads"

### Q1
* Are follower reads enabled on your cluster?

### Q2
* If not, how do you enable follower reads?


## Activy #2 -- Observing Multi-Region Performance with "follower reads"

Connect to your database in three separate sessions accross all three regions `us_west`, `us_east`, and `europe_west`.  Refer to the sheet to see which MOVR database is yours.... `movr1`, `movr2`, `movr3`, ....

Run the following queries in all regions and measure the performance.

**without follower reads:**
```
SELECT locality, rides.* 
FROM rides, [show locality]  
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality]  
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality]  
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

**using experimental_follower_read_timestamp():**
```
SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME experimental_follower_read_timestamp() 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

**using `as of system time interval '-4h' `**
```
SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-4h' 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

**using `as of system time '-2s' `**
```
SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-2s' 
WHERE id = '2ce831ad-2135-4a00-8000-00000001569d'  
AND city = 'boston';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-2s' 
WHERE id = '60b65237-0479-4c00-8000-00000002e1db' 
AND city = 'seattle';

SELECT locality, rides.* 
FROM rides, [show locality] AS OF SYSTEM TIME INTERVAL '-2s' 
WHERE id = 'c71d6063-1726-4000-8000-00000005ef20' 
AND city = 'paris';
```

### Q3
* Why does the `as of system time interval '-2s'` query not get good response times across all regions?

### Q4
* How do you ensure **follower reads** queries use local ranges with the least time lag?


## Activty #3 -- Optimizing Performance with regional objects

Run the following query in all regions:

```sql
SELECT vehicle_city, vehicle_id, count(*) 
FROM rides 
WHERE city='paris' 
GROUP BY 1,2;
```

### Q5
* How do you get this query to perform similar in all regions **without** using follower reads?

### Q6
* How do you show which objects are used for the above query? 

### Q7
* How do you identify which regions a lease holder resides for the above query?

