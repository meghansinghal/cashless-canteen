import mysql.connector
from mysql.connector import pooling
from dotenv import load_dotenv
import os
from decimal import Decimal

load_dotenv()

DB_HOST = os.getenv("DB_HOST", "127.0.0.1")
DB_PORT = int(os.getenv("DB_PORT", 3306))
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "cashless_canteen")

# Connection Pool
pool = pooling.MySQLConnectionPool(
    pool_name="cashless_pool",
    pool_size=5,
    host=DB_HOST,
    port=DB_PORT,
    user=DB_USER,
    password=DB_PASSWORD,
    database=DB_NAME,
    autocommit=False
)

def get_conn():
    return pool.get_connection()


# ---------------- BASIC DB HELPERS ----------------

def fetchall(query, params=None):
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(query, params or ())
        return cur.fetchall()
    finally:
        cur.close()
        conn.close()


def fetchone(query, params=None):
    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        cur.execute(query, params or ())
        return cur.fetchone()
    finally:
        cur.close()
        conn.close()


def execute(query, params=None, commit=True):
    conn = get_conn()
    try:
        cur = conn.cursor()
        cur.execute(query, params or ())
        if commit:
            conn.commit()
        return cur.lastrowid
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()




def create_order_transaction(
    user_id,
    items,
    use_wallet=False,
    applied_coupon_id=None,
    discount_amount=Decimal('0.00'),
    payment_method="card"
):
    """
    THIS NEW VERSION USES SQL PROCEDURES + TRIGGERS.
    """

    conn = get_conn()
    try:
        cur = conn.cursor(dictionary=True)
        conn.start_transaction()

        # 1) Create the order in PENDING state first
        cur.execute("""
            INSERT INTO `Order` (user_id, total_amount, order_status)
            VALUES (%s, 0.00, 'pending')
        """, (user_id,))
        order_id = cur.lastrowid

        # 2) Insert order items (unit_price auto-filled by trigger if missing)
        for it in items:
            cur.execute("""
                INSERT INTO OrderItem (order_id, menu_item_id, quantity, unit_price)
                SELECT %s, %s, %s, price
                FROM MenuItem WHERE menu_item_id=%s
            """, (order_id, it["menu_item_id"], it["quantity"], it["menu_item_id"]))

        # 3) Update order to APPROVED to fire trigger + call procedures
        cur.execute("""
            UPDATE `Order`
            SET order_status='approved'
            WHERE order_id=%s
        """, (order_id,))

        # 4) If user applied coupon
        if applied_coupon_id:
            cur.execute("""
                INSERT INTO OrderCoupon (order_id, coupon_id)
                VALUES (%s, %s)
            """, (order_id, applied_coupon_id))

        # 5) Let SQL procedure finish wallet/transaction logic
        cur.callproc("sp_create_order", [
            user_id,
            use_wallet,
            discount_amount,
            payment_method
        ])

        conn.commit()
        return order_id

    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()
