-- Data cleaning
/* Remove records customerID is NULL */
DELETE FROM customer360.customer_registered
WHERE ID = 0;
/* Remove records created_date is NULL */
DELETE FROM customer360.customer_registered 
WHERE created_date IS NULL;
/* Remove records GMV = 0 */
DELETE FROM customer360.customer_registered
WHERE GMV = 0;
/* Format data type */
--- Bước 1: Thêm cột mới kiểu DATE
ALTER TABLE customer360.customer_registered
ADD COLUMN created_date_clean DATE;
--- Bước 2: Chuyển dữ liệu từ chuỗi sang ngày
ALTER TABLE customer360.customer_transaction 
MODIFY COLUMN Purchase_Date DATE;
/* Remove duplicates */
DELETE t1
FROM customer360.customer_registered t1
JOIN customer360.customer_registered t2
  ON t1.Contract = t2.Contract
  AND t1.ID > t2.ID;


-- Data summary
/* Check table registered */
SELECT count(ID) as row_1, count(Contract) as row_2, count(LocationID) as row_3, 
count(BranchCode) as row_4, count(Status) as row_5, count(created_date) as row_6, count(stopdate) as row_7
from customer360.customer_registered
/* Check table transaction */
SELECT count(Transaction_ID) as row_1, count(CustomerID) as row_2, 
count(Purchase_Date) as row_3, count(GMV) as row_4
from customer360.customer_transaction


-- Data analysis
/* Classify IQR range */
-- Step 1: Calculate customer statistics
	WITH customer_statistics AS (
	  SELECT 
	    CustomerID,
	    DATEDIFF('2022-09-01', MAX(Purchase_Date)) AS Recency,
	    1.00 * COUNT(*)/TIMESTAMPDIFF(YEAR, MIN(created_date), '2022-09-01') AS Frequency,
	    1.00 * SUM(GMV)/TIMESTAMPDIFF(YEAR, MIN(created_date), '2022-09-01') AS Monetary,
	    ROW_NUMBER() OVER (ORDER BY DATEDIFF('2022-09-01', MAX(Purchase_Date)) DESC) AS rn_r,
	    ROW_NUMBER() OVER (ORDER BY 1.00 * COUNT(*)/TIMESTAMPDIFF(YEAR, MIN(created_date), '2022-09-01') ASC) AS rn_f,
	    ROW_NUMBER() OVER (ORDER BY 1.00 * SUM(GMV)/TIMESTAMPDIFF(YEAR, MIN(created_date), '2022-09-01') ASC) AS rn_m
	  FROM customer360.customer_transaction CT
	  JOIN customer360.customer_registered CR ON CT.CustomerID = CR.ID
	  WHERE CustomerID != 0
	  GROUP BY CustomerID),
	
	-- Step 2: Get total count to calculate percentile thresholds
	customer_count AS (
	 SELECT COUNT(*) AS cnt FROM customer_statistics
	),
	-- Step 3: Classify R, F, M based on rank percentiles
	RFM as (
	SELECT
	 cs.*,
	 CASE
	   WHEN cs.rn_r <= cc.cnt * 0.25 THEN '1'
	   WHEN cs.rn_r <= cc.cnt * 0.50 THEN '2'
	   WHEN cs.rn_r <= cc.cnt * 0.75 THEN '3'
	   ELSE '4'
	 END AS R,
	 CASE
	   WHEN cs.rn_f <= cc.cnt * 0.25 THEN '1'
	   WHEN cs.rn_f <= cc.cnt * 0.50 THEN '2'
	   WHEN cs.rn_f <= cc.cnt * 0.75 THEN '3'
	   ELSE '4'
	 END AS F,
	 CASE
	   WHEN cs.rn_m <= cc.cnt * 0.25 THEN '1'
	   WHEN cs.rn_m <= cc.cnt * 0.50 THEN '2'
	   WHEN cs.rn_m <= cc.cnt * 0.75 THEN '3'
	   ELSE '4'
	 END AS M
	FROM customer_statistics cs
	CROSS JOIN customer_count cc), 

/* Cluster customer groups */
customer_segmentation as (
select CustomerID, Monetary, Frequency, Recency, rn_r, rn_f, rn_m, RFM.R, RFM.F, RFM.M,
concat(RFM.R, RFM.F, RFM.M) as RFM,
case 
	when concat(RFM.R, RFM.F, RFM.M) in ('344', '343', '334', '444', '443', '434', '433') then 'VIP customer'
	when concat(RFM.R, RFM.F, RFM.M) in ('424', '243', '324', '244', '342', '242', '333', '332', '234', '341', '241', '441', '331', '231', '442', '431', '432', '423') then 'Loyal customer'
	when concat(RFM.R, RFM.F, RFM.M) in ('222', '322', '223', '323', '224', '132', '233', '312', '232', '313', '214', '314', '421', '414', '422', '413') then 'Potential customer'
	when concat(RFM.R, RFM.F, RFM.M) in ('143', '142', '124', '131', '141','133', '144', '134') then 'Churned customer'
	else 'Walk-in customer'
end as customer_segment 
from RFM)

/* Visualization */ 
-- Summary by segment
select cg.customer_segment,
1.00 * count(CT.Transaction_ID)/count(distinct cg.CustomerID) as purchase_per_each_customer, 
1.00 * sum(CT.GMV)/count(CT.Transaction_ID) as money_per_purchase_segment
from customer360.customer_transaction CT
join customer_segmentation cg 
on CT.CustomerID = cg.CustomerID
group by cg.customer_segment 
-- Overall summary
select sum(ct.GMV)/count(ct.Transaction_ID) as money_per_purchase
from customer360.customer_transaction ct
join customer360.customer_registered cr on ct.CustomerID = cr.ID