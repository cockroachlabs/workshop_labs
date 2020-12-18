-- Q1
SELECT DISTINCT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c WHERE c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND c.pid = '000000' UNION SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';
-- Q2
SELECT c.id, c.code, c.channel, c.status, c.exp_date, c.start_date FROM coupons AS c, offers AS o WHERE c.id = o.id AND c.code = o.code AND c.status = 'A' AND c.exp_date >= '2020-11-20' AND c.start_date <= '2020-11-20' AND o.token = 'c744250a-1377-4cdf-a1f4-5b85a4d29aaa';