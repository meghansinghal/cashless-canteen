-- ============================================
-- Cashless Canteen Database Schema
-- Team Members: Meghan Singhal, Mungara Shreya
-- Date: 2025-10-24
-- ============================================

DROP DATABASE IF EXISTS cashless_canteen;
CREATE DATABASE cashless_canteen;
USE cashless_canteen;

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";

-- TABLE: User
CREATE TABLE `User` (
    user_id BIGINT AUTO_INCREMENT,
    full_name VARCHAR(100) NOT NULL,
    user_id_number VARCHAR(20) UNIQUE NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    phone_number VARCHAR(20),
    password VARCHAR(255) NOT NULL,
    daily_spending_limit DECIMAL(10,2) DEFAULT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    is_admin BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: MenuItem
CREATE TABLE MenuItem (
    menu_item_id BIGINT AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    available_quantity INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (menu_item_id),
    CONSTRAINT chk_MenuItem_price CHECK (price > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: Order
CREATE TABLE `Order` (
    order_id BIGINT AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    order_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    total_amount DECIMAL(10,2) NOT NULL,
    order_status ENUM('pending','approved','preparing','ready_for_pickup','completed','cancelled') DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id),
    FOREIGN KEY (user_id) REFERENCES `User`(user_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: OrderItem
CREATE TABLE OrderItem (
    order_id BIGINT,
    menu_item_id BIGINT,
    quantity INT NOT NULL,
    unit_price DECIMAL(10,2) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, menu_item_id),
    FOREIGN KEY (order_id) REFERENCES `Order`(order_id) ON DELETE CASCADE ON UPDATE CASCADE,
    FOREIGN KEY (menu_item_id) REFERENCES MenuItem(menu_item_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: Transaction
CREATE TABLE `Transaction` (
    transaction_id BIGINT AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    order_id BIGINT NULL,
    transaction_date DATETIME DEFAULT CURRENT_TIMESTAMP,
    amount DECIMAL(10,2) NOT NULL,
    transaction_type ENUM('order','wallet_topup') NOT NULL,
    payment_method VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (transaction_id),
    FOREIGN KEY (user_id) REFERENCES `User`(user_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (order_id) REFERENCES `Order`(order_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: Wallet
CREATE TABLE Wallet (
    wallet_id BIGINT AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    balance DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (wallet_id),
    FOREIGN KEY (user_id) REFERENCES `User`(user_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: Coupon
CREATE TABLE Coupon (
    coupon_id BIGINT AUTO_INCREMENT,
    code VARCHAR(50) UNIQUE NOT NULL,
    discount_amount DECIMAL(10,2) NOT NULL,
    minimum_order_amount DECIMAL(10,2) DEFAULT 0,
    is_used BOOLEAN DEFAULT FALSE,
    start_date DATETIME,
    end_date DATETIME,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (coupon_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- TABLE: OrderCoupon
CREATE TABLE OrderCoupon (
    order_id BIGINT,
    coupon_id BIGINT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (order_id, coupon_id),
    FOREIGN KEY (order_id) REFERENCES `Order`(order_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    FOREIGN KEY (coupon_id) REFERENCES Coupon(coupon_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================

CREATE INDEX idx_Order_user_id ON `Order`(user_id);
CREATE INDEX idx_MenuItem_name_price ON MenuItem(name, price);
CREATE INDEX idx_Coupon_code ON Coupon(code);

-- =====================================================
-- VIEWS (3)

-- 1. View: Order summary with totals and user
CREATE VIEW vw_order_summary AS
SELECT o.order_id, o.user_id, u.full_name, o.order_date, o.order_status, o.total_amount
FROM `Order` o
JOIN `User` u ON o.user_id = u.user_id;

-- 2. View: Wallet balances (useful for admin)
CREATE VIEW vw_wallet_balances AS
SELECT w.wallet_id, w.user_id, u.full_name, w.balance, w.updated_at
FROM Wallet w
JOIN `User` u ON w.user_id = u.user_id;

-- 3. View: Low-stock items (threshold 10)
CREATE VIEW vw_low_stock AS
SELECT menu_item_id, name, available_quantity
FROM MenuItem
WHERE available_quantity <= 10;

-- =====================================================
-- FUNCTIONS (1)

DELIMITER $$
CREATE FUNCTION fn_get_order_total(p_order_id BIGINT)
RETURNS DECIMAL(12,2)
DETERMINISTIC
BEGIN
    DECLARE v_total DECIMAL(12,2) DEFAULT 0.00;
    SELECT IFNULL(SUM(quantity * unit_price), 0.00)
    INTO v_total
    FROM OrderItem
    WHERE order_id = p_order_id;
    RETURN v_total;
END$$
DELIMITER ;

-- =====================================================
-- STORED PROCEDURES (4)

-- 1) Procedure: reduce_stock_for_order
--    Reduces stock based on OrderItem rows for a given order_id
DELIMITER $$
CREATE PROCEDURE sp_reduce_stock_for_order(p_order_id BIGINT)
BEGIN
    UPDATE MenuItem m
    JOIN OrderItem oi ON m.menu_item_id = oi.menu_item_id
    SET m.available_quantity = m.available_quantity - oi.quantity
    WHERE oi.order_id = p_order_id;
END$$
DELIMITER ;

-- 2) Procedure: sp_wallet_topup
--    Adds amount to wallet (creates wallet row if missing) and logs Transaction
DELIMITER $$
CREATE PROCEDURE sp_wallet_topup(p_user_id BIGINT, p_amount DECIMAL(12,2), p_method VARCHAR(50))
BEGIN
    DECLARE v_wallet_id BIGINT;
    SELECT wallet_id INTO v_wallet_id FROM Wallet WHERE user_id = p_user_id;
    IF v_wallet_id IS NULL THEN
        INSERT INTO Wallet (user_id, balance) VALUES (p_user_id, p_amount);
    ELSE
        UPDATE Wallet SET balance = balance + p_amount WHERE wallet_id = v_wallet_id;
    END IF;

    INSERT INTO `Transaction` (user_id, amount, transaction_type, payment_method)
    VALUES (p_user_id, p_amount, 'wallet_topup', p_method);
END$$
DELIMITER ;

-- 3) Procedure: sp_create_order
--    Creates order + items + transaction, optionally uses wallet, returns last_inserted order_id
DELIMITER $$
CREATE PROCEDURE sp_create_order(
    IN p_user_id BIGINT,
    IN p_use_wallet BOOLEAN,
    IN p_discount_amount DECIMAL(12,2),
    IN p_payment_method VARCHAR(50)
)
BEGIN
    DECLARE v_order_id BIGINT;
    DECLARE v_total DECIMAL(12,2);

    -- Insert order header (total_amount is temporary; will update after items insert)
    INSERT INTO `Order` (user_id, total_amount, order_status) VALUES (p_user_id, 0.00, 'approved');
    SET v_order_id = LAST_INSERT_ID();

    -- Expect calling app to insert order items via separate INSERTs using v_order_id.
    -- But provide a convenience: calculate total from inserted items (if any)
    SELECT IFNULL(SUM(quantity * unit_price), 0.00) INTO v_total FROM OrderItem WHERE order_id = v_order_id;

    -- Apply discount if provided
    SET v_total = v_total - IFNULL(p_discount_amount, 0.00);
    IF v_total < 0 THEN SET v_total = 0.00; END IF;

    -- Update order total
    UPDATE `Order` SET total_amount = v_total WHERE order_id = v_order_id;

    -- Create transaction record
    INSERT INTO `Transaction` (user_id, order_id, amount, transaction_type, payment_method)
    VALUES (p_user_id, v_order_id, v_total, 'order', p_payment_method);

    -- If using wallet, deduct wallet
    IF p_use_wallet THEN
        UPDATE Wallet
        SET balance = balance - v_total
        WHERE user_id = p_user_id;
    END IF;

    -- Reduce stock (call procedure)
    CALL sp_reduce_stock_for_order(v_order_id);

    -- Auto-generate coupon for large orders (call procedure)
    CALL sp_autogen_coupon_for_order(v_order_id);

    SELECT v_order_id AS created_order_id;
END$$
DELIMITER ;

-- 4) Procedure: sp_autogen_coupon_for_order
--    Generates a coupon for the order if it meets thresholds
DELIMITER $$
CREATE PROCEDURE sp_autogen_coupon_for_order(p_order_id BIGINT)
BEGIN
    DECLARE v_total DECIMAL(12,2);
    DECLARE v_user BIGINT;

    SELECT total_amount, user_id INTO v_total, v_user FROM `Order` WHERE order_id = p_order_id;

    -- If total >= 200 produce a coupon worth 20 with min order 150 valid for 30 days
    IF v_total >= 200 THEN
        INSERT INTO Coupon (code, discount_amount, minimum_order_amount, start_date, end_date)
        VALUES (CONCAT('AUTO', p_order_id, DATE_FORMAT(NOW(),'%y%m%d%H%i')), 20.00, 150.00, NOW(), DATE_ADD(NOW(), INTERVAL 30 DAY));

        INSERT INTO OrderCoupon (order_id, coupon_id)
        VALUES (p_order_id, LAST_INSERT_ID());
    END IF;

    -- Bonus: if total >= 500 produce bigger coupon
    IF v_total >= 500 THEN
        INSERT INTO Coupon (code, discount_amount, minimum_order_amount, start_date, end_date)
        VALUES (CONCAT('BIG', p_order_id, DATE_FORMAT(NOW(),'%y%m%d%H%i')), 50.00, 400.00, NOW(), DATE_ADD(NOW(), INTERVAL 60 DAY));

        INSERT INTO OrderCoupon (order_id, coupon_id)
        VALUES (p_order_id, LAST_INSERT_ID());
    END IF;
END$$
DELIMITER ;



-- =====================================================
-- TRIGGERS (5)

-- 1) Trigger: After user insert → create wallet automatically
DELIMITER $$
CREATE TRIGGER trg_user_after_insert
AFTER INSERT ON `User`
FOR EACH ROW
BEGIN
    INSERT INTO Wallet (user_id, balance) VALUES (NEW.user_id, 0.00);
END$$
DELIMITER ;

-- 2) Trigger: After order insert → copy unit prices into OrderItem if missing (convenience)
--    (Only fires if application inserted OrderItem rows with NULL unit_price — safe default)
DELIMITER $$
CREATE TRIGGER trg_orderitem_unitprice_fill
AFTER INSERT ON OrderItem
FOR EACH ROW
BEGIN
    IF NEW.unit_price IS NULL OR NEW.unit_price = 0 THEN
        UPDATE OrderItem oi
        JOIN MenuItem m ON oi.menu_item_id = m.menu_item_id
        SET oi.unit_price = m.price
        WHERE oi.order_id = NEW.order_id AND oi.menu_item_id = NEW.menu_item_id;
    END IF;
END$$
DELIMITER ;

-- 3) Trigger: On order status update to 'approved' → reduce stock
DELIMITER $$
CREATE TRIGGER trg_Order_approved
AFTER UPDATE ON `Order`
FOR EACH ROW
BEGIN
    IF NEW.order_status = 'approved' AND OLD.order_status != 'approved' THEN
        CALL sp_reduce_stock_for_order(NEW.order_id);
        CALL sp_autogen_coupon_for_order(NEW.order_id);
    END IF;
END$$
DELIMITER ;

-- 4) Trigger: On coupon expiry (scheduler / periodic job recommended) — here we mark coupons expired when used or past end_date
--    We'll provide a trigger to mark is_used TRUE when an OrderCoupon is inserted, and a procedure to sweep expired coupons
DELIMITER $$
CREATE TRIGGER trg_ordercoupon_after_insert
AFTER INSERT ON OrderCoupon
FOR EACH ROW
BEGIN
    -- mark coupon used
    UPDATE Coupon SET is_used = TRUE WHERE coupon_id = NEW.coupon_id;
END$$
DELIMITER ;

-- 5) Trigger: Prevent negative wallet balances (before update)
DELIMITER $$
CREATE TRIGGER trg_wallet_before_update
BEFORE UPDATE ON Wallet
FOR EACH ROW
BEGIN
    IF NEW.balance < 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Wallet balance cannot be negative';
    END IF;
END$$
DELIMITER ;


-- =====================================================
-- HELPER PROCEDURE (to be scheduled by admin) - marks expired coupons as used/invalid

DELIMITER $$
CREATE PROCEDURE sp_sweep_expired_coupons()
BEGIN
    UPDATE Coupon
    SET is_used = TRUE
    WHERE end_date IS NOT NULL AND end_date < NOW();
END$$
DELIMITER ;

-- =====================================================
-- SAMPLE DATA

INSERT INTO `User` (full_name, user_id_number, email, password, is_admin)
VALUES
('John Doe', '12345', 'john@example.com', 'password', FALSE),
('Jane Smith', '67890', 'jane@example.com', 'password', FALSE),
('Bob Wilson', '13579', 'bob@example.com', 'password', FALSE);

-- Admin account (created last so wallet trigger fires)
INSERT INTO `User` (full_name, user_id_number, email, password, is_admin)
VALUES ('Admin User', '00000', 'admin@canteen.com', 'admin123', TRUE);

-- Menu Items
INSERT INTO MenuItem (name, description, price, available_quantity) VALUES
('Burger', 'Classic Veg Burger', 60.00, 50),
('Fries', 'Crispy Potato Fries', 40.00, 100),
('Soda', 'Chilled Soft Drink', 30.00, 75),
('Pizza Slice', 'Cheese Pizza Slice', 80.00, 40),
('Pasta', 'Creamy Alfredo Pasta', 120.00, 40),
('Sandwich', 'Grilled Veg Sandwich', 50.00, 70),
('Coffee', 'Hot Brew Coffee', 35.00, 100),
('Tea', 'Masala Chai', 20.00, 150),
('Momos', 'Steamed Veg Momos', 60.00, 80),
('Brownie', 'Chocolate Fudge Brownie', 70.00, 60);

-- Coupons
INSERT INTO Coupon (code, discount_amount, minimum_order_amount, start_date, end_date)
VALUES
('WELCOME10', 10.00, 100.00, '2024-01-01', '2025-12-31'),
('SAVE5', 5.00, 50.00, '2024-01-01', '2025-12-31');

-- Example order + items
INSERT INTO `Order` (user_id, total_amount, order_status) VALUES (1, 100.00, 'approved');
INSERT INTO OrderItem (order_id, menu_item_id, quantity, unit_price) VALUES (LAST_INSERT_ID(), 1, 1, 60.00);
-- After above insertion, triggers/procedures will ensure wallet/wallet creation + stock are consistent

-- =====================================================
-- FINAL: safety tuning

-- Reduce lock-wait time for quick feedback in student environment
SET GLOBAL innodb_lock_wait_timeout = 10;