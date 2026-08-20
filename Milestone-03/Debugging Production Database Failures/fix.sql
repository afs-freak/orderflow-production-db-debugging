-- Fix Bug 1
DELETE FROM orders WHERE customer_id NOT IN (SELECT id FROM customers);
ALTER TABLE orders ADD CONSTRAINT fk_orders_customer FOREIGN KEY (customer_id) REFERENCES customers(id);

-- Fix Bug 2
UPDATE products SET inventory_count = 0 WHERE inventory_count < 0;
ALTER TABLE products ADD CONSTRAINT check_inventory_non_negative CHECK (inventory_count >= 0);

-- Fix Bug 3
DELETE FROM payments WHERE id NOT IN (SELECT MIN(id) FROM payments GROUP BY order_id);
ALTER TABLE payments ADD CONSTRAINT unique_order_payment UNIQUE (order_id);
