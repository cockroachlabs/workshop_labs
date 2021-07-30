use tpcc;
-- partial index
show create table order_line;
alter table order_line add column is_active boolean default False;
update order_line set is_active = True where ol_o_id / 10 = 1;

CREATE INDEX idx_dist_info_partial
   ON order_line(ol_dist_info)
   STORING (ol_amount)
   WHERE is_active = True;

CREATE INDEX idx_dist_info
   ON order_line(ol_dist_info)
   STORING (ol_amount);

analyze order_line;

EXPLAIN analyze select sum(ol_amount), count(*)
FROM order_line
WHERE is_active = True;

SELECT 'PARTIAL_INDEX' as indexType, sum(range_size_mb) as indexSizeMB, count(*) as rangeCount
FROM [show ranges from index idx_dist_info_partial]
UNION ALL
SELECT 'FULL_INDEX', sum(range_size_mb), count(*)
FROM [show ranges from index idx_dist_info];
