# Production Database Bug Report

## Bug 1: Orphaned Orders (Missing Customer)

### Symptom
Some orders appear in the system with no associated customer record. When listing all orders, certain entries show a `null` customer name, even though a `customer_id` is clearly recorded in the table.

### Reproduction Query
```sql
SELECT o.id as order_id, o.customer_id, c.name as customer_name, o.status, o.total
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id
WHERE c.id IS NULL;
```

Result:
```
 order_id | customer_id | customer_name |  status   | total 
----------+-------------+---------------+-----------+-------
        3 |        9999 |               | completed | 50.00
        4 |        9999 |               | pending   | 75.00
```

### Data Flow Trace
The wrong value in the API response comes from `GET /orders`. This route executes a JOIN query between `orders` and `customers`. The `orders` table has rows with `customer_id = 9999`, but there is no customer with `id = 9999` in the `customers` table. The INSERT that created these orders did not validate if the customer exists.

### Root Cause
The `orders` table is missing a `FOREIGN KEY` constraint on the `customer_id` column referencing `customers(id)`. This allows inserting orders with non-existent customer IDs.

### Fix Applied
```sql
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id);
```

### Validation
After deleting the orphaned records and applying the fix:
Reproduction query returns 0 rows.
Attempting to insert a bad record:
```sql
INSERT INTO orders (id, customer_id, status, total) VALUES (999, 9999, 'pending', 10.00);
```
Fails with: `ERROR: insert or update on table "orders" violates foreign key constraint "fk_orders_customer"`

---

## Bug 2: Negative Inventory Counts

### Symptom
Certain products show negative inventory counts after order processing. Several products in the database have an `inventory_count` less than zero, which should not be possible.

### Reproduction Query
```sql
SELECT id, name, sku, inventory_count, price
FROM products
WHERE inventory_count < 0;
```

Result:
```
 id |        name        |   sku   | inventory_count | price 
----+--------------------+---------+-----------------+-------
  2 | Wireless Mouse     | SKU-002 |              -3 | 25.00
  3 | USB-C Cable (1m)   | SKU-003 |              -5 | 12.50
```

### Data Flow Trace
The wrong value is visible in `GET /products`. The `inventory_count` is updated via `PATCH /products/:id/inventory` or when an order is created. The database allows the value to drop below zero because there is no validation at the database level to prevent negative numbers.

### Root Cause
The `products` table is missing a `CHECK` constraint on the `inventory_count` column to ensure the value is `>= 0`.

### Fix Applied
```sql
ALTER TABLE products ADD CONSTRAINT check_inventory_non_negative CHECK (inventory_count >= 0);
```

### Validation
After fixing the negative inventory counts to 0 and applying the fix:
Reproduction query returns 0 rows.
Attempting to insert a bad record:
```sql
UPDATE products SET inventory_count = -1 WHERE id = 1;
```
Fails with: `ERROR: new row for relation "products" violates check constraint "check_inventory_non_negative"`

---

## Bug 3: Duplicate Payments for Single Order

### Symptom
Some completed orders show payment status as pending. Users have reported seeing ambiguous payment statuses or multiple payment records when only one was expected.

### Reproduction Query
```sql
SELECT order_id, COUNT(*) as payment_count, string_agg(status, ', ') as statuses
FROM payments
GROUP BY order_id
HAVING COUNT(*) > 1;
```

Result:
```
 order_id | payment_count |      statuses      
----------+---------------+--------------------
        1 |             2 | pending, completed
```

### Data Flow Trace
The wrong status appears in `GET /payments/:orderId` or `GET /orders`. A client might accidentally submit a payment twice, creating multiple records in the `payments` table for the same `order_id`. The database accepts both inserts because there is no uniqueness constraint enforcing a 1:1 relationship between orders and payments.

### Root Cause
The `payments` table is missing a `UNIQUE` constraint on the `order_id` column.

### Fix Applied
```sql
ALTER TABLE payments ADD CONSTRAINT unique_order_payment UNIQUE (order_id);
```

### Validation
After removing duplicate payments and applying the fix:
Reproduction query returns 0 rows.
Attempting to insert a duplicate payment:
```sql
INSERT INTO payments (order_id, amount, status) VALUES (2, 299.99, 'pending');
INSERT INTO payments (order_id, amount, status) VALUES (2, 299.99, 'completed');
```
Fails with: `ERROR: duplicate key value violates unique constraint "unique_order_payment"`
 
