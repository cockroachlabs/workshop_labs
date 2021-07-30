use tpcc;
create index idx1 on order_line (ol_supply_w_id);
explain analyze select ol_amount, ol_quantity from order_line where ol_supply_w_id=100;
explain analyze select sum(ol_amount), sum(ol_quantity) from order_line where ol_supply_w_id=100 and ol_quantity>2;

create index idx2 on order_line ( ol_supply_w_id ) storing (ol_quantity, ol_amount);
explain analyze select ol_amount, ol_quantity from order_line where ol_supply_w_id=100;
explain analyze select sum(ol_amount), sum(ol_quantity) from order_line where ol_supply_w_id=100 and ol_quantity>2;

