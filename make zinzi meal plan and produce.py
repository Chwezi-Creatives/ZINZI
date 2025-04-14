import pyodbc
import pandas as pd
import numpy as np

def get_db_connection():
    connection_string = (
        "Driver={ODBC Driver 17 for SQL Server};"
        "Server=localhost\\SQLExpress;"
        "Database=ZANZA;"
        "Trusted_Connection=Yes;"
        "TrustServerCertificate=Yes;"
    )
    try:
        return pyodbc.connect(connection_string)
    except pyodbc.Error as e:
        print(f"Error: {e}")
        return None

conn = get_db_connection()
if not conn:
    exit()
cursor = conn.cursor()

file_path = r"C:\Users\Josh CJ\Desktop\ZINZI Meal plan.xlsx"
xls = pd.ExcelFile(file_path)

produce_df = pd.read_excel(xls, 'Produce').rename(columns=lambda x: x.strip())
meal_df = pd.read_excel(xls, 'Meal').rename(columns=lambda x: x.strip())

produce_df = produce_df.loc[:, ~produce_df.columns.str.contains('^Unnamed')]
meal_df = meal_df.loc[:, ~meal_df.columns.str.contains('^Unnamed')]

def create_table(table_name, df):
    column_types = {}
    for col in df.columns:
        if table_name == "Produce":
            if col.lower() == 'produce id':
                column_types[col] = 'NVARCHAR(50) PRIMARY KEY'
            elif col.lower() in ['unit grams', 'calories', 'cholesterol', 'carbohyd', 'proteins', 'fats', 'fiber', 'sugar']:
                column_types[col] = 'FLOAT NULL'  # Allow NULL values
            elif col.lower() in ['produce', 'meal type', 'source', 'nutritional info']:
                column_types[col] = 'NVARCHAR(MAX)'
            else:
                column_types[col] = 'NVARCHAR(MAX)'
        elif table_name == "Meals":
            if col.lower() == 'cuisine preferences':
                column_types[col] = 'NVARCHAR(MAX)'
            else:
                column_types[col] = 'NVARCHAR(MAX)'
        else:
            column_types[col] = 'NVARCHAR(MAX)'

    columns = [f"[{col}] {dtype}" for col, dtype in column_types.items()]
    cursor.execute(f"IF OBJECT_ID('{table_name}', 'U') IS NOT NULL DROP TABLE {table_name}")
    cursor.execute(f"CREATE TABLE {table_name} ({', '.join(columns)})")
    conn.commit()

create_table("Produce", produce_df)
create_table("Meals", meal_df)

def clean_data(df):
    for col in df.columns:
        if df[col].dtype == 'float64':  # Check if column is numeric
            df[col] = df[col].fillna(0)  # Replace NaN with 0 in numeric columns
        else:
            df[col] = df[col].replace({np.nan: None})  # Replace NaN with None for non-numeric columns
        df[col] = df[col].apply(lambda x: 'None' if x == '' else x)
        if col in ['Eaing Goal', 'Allergies', 'Recipe Link', 'Meal image Link']:
            df[col] = df[col].apply(lambda x: 'None' if x is None else x)
    return df

produce_df = clean_data(produce_df)
meal_df = clean_data(meal_df)

def insert_data(table, df):
    cols = [f'[{c}]' for c in df.columns]
    query = f"INSERT INTO {table} ({', '.join(cols)}) VALUES ({', '.join('?' * len(cols))})"
    for _, row in df.iterrows():
        try:
            cursor.execute(query, tuple(row))
        except pyodbc.Error as e:
            print(f"Error inserting row: {e}\nRow: {tuple(row)}")

insert_data("Produce", produce_df)
insert_data("Meals", meal_df)

conn.commit()
cursor.close()
conn.close()
print("✅ Data successfully inserted!")