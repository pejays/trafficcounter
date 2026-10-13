import psycopg2

# Connection parameters – replace with your actual PostgreSQL password
conn_params = {
    "dbname": "vehisights_db",
    "user": "postgres",
    "password": "abiera27",  # Change this to your actual password
    "host": "192.168.110.131",
    "port": "5432"
}

try:
    conn = psycopg2.connect(**conn_params)
    print("✅ Connected to PostgreSQL successfully!")
    
    cur = conn.cursor()
    cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema = 'public' ORDER BY table_name;")
    tables = cur.fetchall()
    
    print("Tables in the database:")
    for table in tables:
        print(f"  - {table[0]}")
    
    cur.close()
    conn.close()
    
except Exception as e:
    print(f"❌ Error: {e}")