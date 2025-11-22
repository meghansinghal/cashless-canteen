import streamlit as st
from db import fetchall, fetchone, create_order_transaction, execute
from decimal import Decimal
from dotenv import load_dotenv
import os

load_dotenv()

st.set_page_config(page_title="Cashless Canteen", layout="wide")

# ---------------- SHARED PAYMENT GATEWAY ------------------

def payment_gateway(amount, purpose, callback):
    st.subheader("Payment Gateway")
    st.write(f"**Purpose:** {purpose}")
    st.write(f"**Amount:** ₹{float(amount):.2f}")

    method = st.radio("Select payment method:", ["UPI", "Credit Card", "NetBanking"])

    if st.button("Pay Now"):
        st.success(f"Payment of ₹{amount:.2f} via {method} successful!")
        callback()
        st.session_state['payment_mode'] = None


# ---------------- AUTH FUNCTIONS ------------------

def login_user(email, password):
    row = fetchone(
        "SELECT user_id, full_name, email, password, is_admin FROM `User` WHERE email=%s",
        (email,)
    )
    if not row:
        return None
    if password != row['password']:
        return None
    return row


def register_user(full_name, user_id_number, email, password):
    try:
        execute("""
            INSERT INTO `User` (full_name, user_id_number, email, password)
            VALUES (%s, %s, %s, %s)
        """, (full_name, user_id_number, email, password))
        return True
    except Exception as e:
        st.error("Registration failed: " + str(e))
        return False


# --------------- FETCH FUNCTIONS -----------------

def get_menu_items():
    return fetchall("""
        SELECT menu_item_id, name, description, price, available_quantity
        FROM MenuItem ORDER BY name
    """)


def get_user_orders(user_id):
    return fetchall("""
        SELECT o.order_id, o.order_date, o.total_amount, o.order_status
        FROM `Order` o
        WHERE o.user_id=%s
        ORDER BY o.order_date DESC
    """, (user_id,))


def top_up_wallet(user_id, amount):
    w = fetchone("SELECT wallet_id, balance FROM Wallet WHERE user_id=%s", (user_id,))
    if not w:
        execute("INSERT INTO Wallet (user_id, balance) VALUES (%s, %s)",
                (user_id, amount))
    else:
        execute("UPDATE Wallet SET balance = balance + %s WHERE wallet_id=%s",
                (amount, w['wallet_id']))

    execute("""
        INSERT INTO Transaction (user_id, amount, transaction_type, payment_method)
        VALUES (%s, %s, 'wallet_topup', 'card')
    """, (user_id, amount))

    return True


def get_wallet_balance(user_id):
    w = fetchone("SELECT wallet_id, balance FROM Wallet WHERE user_id=%s", (user_id,))
    if not w:
        return Decimal('0.00')
    return Decimal(str(w['balance']))


# ---------------- SESSION STATE -------------------

if 'user' not in st.session_state:
    st.session_state.user = None

if 'cart' not in st.session_state:
    st.session_state.cart = {}

if 'payment_mode' not in st.session_state:
    st.session_state.payment_mode = None


# ---------------- SIDEBAR NAVIGATION --------------

st.sidebar.title("Cashless Canteen")

# Build page list dynamically (admin only)
pages = ["Home", "Menu", "Cart", "Checkout", "Orders", "Wallet"]

if st.session_state.user and st.session_state.user.get("is_admin"):
    pages.append("Admin")

menu_selection = st.sidebar.radio("Navigate", pages)


# ---------------- AUTH UI ------------------

if st.session_state.user:
    st.sidebar.markdown(f"**Logged in as:** {st.session_state.user['full_name']}")

    if st.session_state.user.get("is_admin"):
        st.sidebar.success("Admin Account")

    if st.sidebar.button("Logout"):
        st.session_state.user = None

else:
    st.sidebar.markdown("### Login")
    email = st.sidebar.text_input("Email")
    password = st.sidebar.text_input("Password", type="password")

    if st.sidebar.button("Login"):
        u = login_user(email.strip(), password.strip())
        if u:
            st.session_state.user = u
            st.success("Logged in")
        else:
            st.error("Invalid credentials")

    st.sidebar.markdown("### Register")
    reg_name = st.sidebar.text_input("Full name", key="reg_name")
    reg_uid = st.sidebar.text_input("User ID number", key="reg_uid")
    reg_email = st.sidebar.text_input("Email (register)", key="reg_email")
    reg_pass = st.sidebar.text_input("Password (register)", type="password", key="reg_pass")

    if st.sidebar.button("Register"):
        ok = register_user(
            reg_name.strip(),
            reg_uid.strip(),
            reg_email.strip(),
            reg_pass.strip()
        )
        if ok:
            st.success("User registered. Please login.")


# ---------------- CART OPERATIONS -----------------

def add_to_cart(menu_item_id, qty=1):
    st.session_state.cart[str(menu_item_id)] = \
        st.session_state.cart.get(str(menu_item_id), 0) + qty


def remove_from_cart(menu_item_id):
    st.session_state.cart.pop(str(menu_item_id), None)


def update_cart_qty(menu_item_id, qty):
    if qty <= 0:
        remove_from_cart(menu_item_id)
    else:
        st.session_state.cart[str(menu_item_id)] = qty


def cart_items_list():
    if not st.session_state.cart:
        return []

    ids = list(map(int, st.session_state.cart.keys()))
    if not ids:
        return []

    placeholders = ",".join(["%s"] * len(ids))
    items = fetchall(
        f"SELECT menu_item_id, name, price, available_quantity "
        f"FROM MenuItem WHERE menu_item_id IN ({placeholders})",
        tuple(ids)
    )

    for it in items:
        it['qty'] = st.session_state.cart[str(it['menu_item_id'])]

    return items


# -------------------------------------------------
# ---------------- HOME PAGE ----------------------
# -------------------------------------------------

if menu_selection == "Home":
    st.title("Welcome to Cashless Canteen")
    st.write("Browse menu, place orders, earn coupons, and use wallet payments.")


# -------------------------------------------------
# ---------------- MENU PAGE ----------------------
# -------------------------------------------------

elif menu_selection == "Menu":
    st.header("Menu")

    menu = get_menu_items()
    cols = st.columns(3)

    for i, item in enumerate(menu):
        col = cols[i % 3]

        with col:
            st.subheader(f"{item['name']} — ₹{float(item['price']):.2f}")
            if item['description']:
                st.write(item['description'])
            st.write(f"Available: {item['available_quantity']}")

            qty = st.number_input(
                "Qty",
                min_value=1,
                max_value=int(item['available_quantity']),
                value=1,
                key=f"qty_{item['menu_item_id']}"
            )

            if st.button("Add to cart", key=f"add_{item['menu_item_id']}"):
                add_to_cart(item['menu_item_id'], int(qty))
                st.success("Added to cart")


# -------------------------------------------------
# ---------------- CART PAGE ----------------------
# -------------------------------------------------

elif menu_selection == "Cart":
    st.header("Your Cart")

    items = cart_items_list()

    if not items:
        st.info("Cart empty.")
    else:
        for it in items:
            cols = st.columns([4, 1, 1, 1])

            cols[0].write(it['name'])
            cols[1].write(f"₹{float(it['price']):.2f}")

            new_qty = cols[2].number_input(
                "Qty",
                min_value=1,
                max_value=int(it['available_quantity']),
                value=it['qty'],
                key=f"cart_{it['menu_item_id']}"
            )

            if cols[2].button("Update", key=f"update_{it['menu_item_id']}"):
                update_cart_qty(it['menu_item_id'], int(new_qty))
                st.success("Updated")

            if cols[3].button("Remove", key=f"remove_{it['menu_item_id']}"):
                remove_from_cart(it['menu_item_id'])
                st.success("Removed")

        total = sum(
            Decimal(str(it['price'])) * it['qty']
            for it in items
        )
        st.write(f"**Total: ₹{total:.2f}**")


# -------------------------------------------------
# ---------------- CHECKOUT PAGE ------------------
# -------------------------------------------------

elif menu_selection == "Checkout":
    st.header("Checkout")

    if not st.session_state.user:
        st.warning("Please login first.")

    else:
        items = cart_items_list()

        if not items:
            st.info("Your cart is empty.")
        else:
            st.subheader("Order Summary")

            for it in items:
                st.write(f"{it['name']} × {it['qty']} — ₹{float(it['price']) * it['qty']:.2f}")

            subtotal = sum(
                Decimal(str(it['price'])) * it['qty']
                for it in items
            )
            st.write(f"Subtotal: ₹{subtotal:.2f}")

            # ---- Fetch Unused Coupons ----
            coupons = fetchall("""
                SELECT c.coupon_id, c.code, c.discount_amount, c.minimum_order_amount
                FROM Coupon c
                WHERE c.is_used = FALSE
                AND c.minimum_order_amount <= %s
            """, (subtotal,))

            discount = Decimal('0')
            selected_coupon = None

            if coupons:
                cp_map = {
                    f"{c['code']} - ₹{c['discount_amount']}": c
                    for c in coupons
                }
                choice = st.selectbox("Apply Coupon?", ["No Coupon"] + list(cp_map.keys()))
                if choice != "No Coupon":
                    selected_coupon = cp_map[choice]
                    discount = Decimal(str(selected_coupon["discount_amount"]))

            total = subtotal - discount
            if total < 0:
                total = Decimal('0.00')

            st.write(f"Discount: ₹{discount:.2f}")
            st.write(f"Final Total: ₹{total:.2f}")

            use_wallet = st.checkbox("Pay with Wallet")

            if st.button("Place Order"):

                if use_wallet:
                    try:
                        payload = [
                            {"menu_item_id": it["menu_item_id"], "quantity": it["qty"]}
                            for it in items
                        ]

                        oid = create_order_transaction(
                            st.session_state.user['user_id'],
                            payload,
                            True,
                            applied_coupon_id=(selected_coupon['coupon_id'] if selected_coupon else None),
                            discount_amount=discount
                        )

                        st.success(f"Order placed! Order ID: {oid}")
                        st.session_state.cart = {}

                    except Exception as e:
                        st.error(str(e))

                else:
                    st.session_state['payment_mode'] = {
                        "amount": total,
                        "purpose": "Checkout Payment",
                        "items": items,
                        "coupon": selected_coupon,
                        "discount": discount
                    }


# -------------------------------------------------
# ---------------- PAYMENT HANDLING ----------------
# -------------------------------------------------

if st.session_state.get('payment_mode') and menu_selection != "Wallet":
    mode = st.session_state['payment_mode']

    def finalize_order():
        try:
            payload = [
                {"menu_item_id": it["menu_item_id"], "quantity": it["qty"]}
                for it in mode['items']
            ]

            oid = create_order_transaction(
                st.session_state.user['user_id'],
                payload,
                False,
                applied_coupon_id=(mode['coupon']['coupon_id'] if mode['coupon'] else None),
                discount_amount=mode['discount']
            )

            st.success(f"Order placed! Order ID: {oid}")
            st.session_state.cart = {}

        except Exception as e:
            st.error(str(e))

    payment_gateway(
        amount=mode['amount'],
        purpose=mode['purpose'],
        callback=finalize_order
    )


# -------------------------------------------------
# ---------------- ORDERS PAGE --------------------
# -------------------------------------------------

elif menu_selection == "Orders":
    st.header("Your Orders")

    if not st.session_state.user:
        st.warning("Please login.")
    else:
        orders = get_user_orders(st.session_state.user['user_id'])

        if not orders:
            st.info("No orders yet.")
        else:
            for o in orders:
                st.write(f"### Order #{o['order_id']}")
                st.write(f"Amount: ₹{float(o['total_amount'])}")
                st.write(f"Status: {o['order_status']} — {o['order_date']}")

                coupons = fetchall("""
                    SELECT c.code, c.discount_amount
                    FROM Coupon c
                    JOIN OrderCoupon oc ON oc.coupon_id = c.coupon_id
                    WHERE oc.order_id=%s
                """, (o['order_id'],))

                if coupons:
                    st.write("#### Coupons Earned:")
                    for cp in coupons:
                        st.write(f"- {cp['code']} — ₹{cp['discount_amount']}")

                st.write("---")


# -------------------------------------------------
# ---------------- WALLET PAGE --------------------
# -------------------------------------------------

elif menu_selection == "Wallet":
    st.header("Wallet")

    if not st.session_state.user:
        st.warning("Login to continue.")
    else:
        bal = get_wallet_balance(st.session_state.user['user_id'])
        st.write(f"### Current Balance: ₹{float(bal):.2f}")

        amt = st.number_input("Top-up Amount", min_value=10.0, value=100.0)

        if st.button("Add Money"):
            st.session_state['payment_mode'] = {
                "amount": amt,
                "purpose": "Wallet Top-up"
            }


# Wallet Payment Handler
if st.session_state.get('payment_mode') and st.session_state['payment_mode']['purpose'] == "Wallet Top-up":

    mode = st.session_state['payment_mode']

    def finalize_topup():
        top_up_wallet(
            st.session_state.user['user_id'],
            Decimal(str(mode['amount']))
        )
        st.success("Wallet updated successfully!")

    payment_gateway(
        amount=mode['amount'],
        purpose="Wallet Top-up",
        callback=finalize_topup
    )


# -------------------------------------------------
# ---------------- ADMIN PAGE ---------------------
# -------------------------------------------------

elif menu_selection == "Admin":
    # Security Guard
    if not st.session_state.user or not st.session_state.user.get("is_admin"):
        st.error("Access denied. Admins only.")
        st.stop()

    st.header("Admin Panel — Manage Menu Items")

    items = get_menu_items()

    for it in items:
        cols = st.columns([4, 1, 1])

        cols[0].write(it['name'])

        new_price = cols[1].number_input(
            "Price",
            value=float(it['price']),
            key=f"p_{it['menu_item_id']}"
        )

        new_stock = cols[2].number_input(
            "Stock",
            value=int(it['available_quantity']),
            key=f"s_{it['menu_item_id']}"
        )

        if cols[2].button("Update", key=f"u_{it['menu_item_id']}"):
            execute("""
                UPDATE MenuItem
                SET price=%s, available_quantity=%s
                WHERE menu_item_id=%s
            """, (Decimal(str(new_price)), int(new_stock), it['menu_item_id']))

            st.success("Updated")
