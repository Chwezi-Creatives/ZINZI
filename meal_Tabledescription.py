#cspell:disable
from database import get_db_connection
import pandas as pd
#import ace_tools as tools

# Load data from the database
conn = get_db_connection()
produce_df = pd.read_sql("SELECT * FROM Produce", conn)
meal_df = pd.read_sql("SELECT * FROM Meals", conn)
conn.close()

# Normalize column names to lowercase and remove extra spaces
produce_df.columns = produce_df.columns.str.lower().str.strip()
meal_df.columns = meal_df.columns.str.lower().str.strip()

def generate_produce_description(row):
    """Generates a structured sentence describing a produce item based on its row data."""
    produce_id = row.get("produce_id", "Unknown")
    produce_name = row.get("produce", "Unknown")
    calories = row.get("calories", "Unknown")
    cholesterol = row.get("cholesterol", "Unknown")
    carbohydrates = row.get("carbohydrates", "Unknown")
    proteins = row.get("proteins", "Unknown")
    fats = row.get("fats", "Unknown")
    fiber = row.get("fiber", "Unknown")
    vitamins = row.get("vitamins (of recommended daily intake)", "Unknown")
    magnesium = row.get("magnesium(of recommended daily intake)", "Unknown")
    potassium = row.get("potassium", "Unknown")
    source = row.get("source", "Unknown")

    if cholesterol == "Unknown" or cholesterol == 0:
        cholesterol_text = "and is **cholesterol-free**."
    else:
        cholesterol_text = f"and contains **{cholesterol}mg of cholesterol**."

    sentence = (
        f"**{produce_name}** (Produce ID: {produce_id}) provides **{calories} calories per 100g** "
        f"{cholesterol_text} It contains **{carbohydrates}g of carbohydrates, {proteins}g of protein, "
        f"and {fats}g of fat**. Dietary fiber content is **{fiber}g**, and it provides essential vitamins **{vitamins}**. "
        f"Magnesium and potassium levels are **{magnesium}%** and **{potassium}mg**, respectively. "
        f"More details are available [here]({source})."
    )
    
    return sentence

def generate_meal_description(row):
    """Generates a structured sentence describing a meal based on its row data."""
    meal_id = row.get("meal_id", "Unknown")
    meal_name = row.get("meal_name", "Unknown")
    meal_category = row.get("meal category", "Unknown")
    meal_description = row.get("meal_description", "Unknown")
    ingredients = row.get("ingredients", "Unknown")
    complementary_dishes = row.get("complementary dishes", "Unknown")
    recipe_link = row.get("link", "Unknown")
    goal = row.get("goal", "Unknown")
    dietary_preference = row.get("dietary preference", "Unknown")
    allergies = row.get("allergies", "Unknown")
    disease_management = row.get("disease management", "Unknown")
    cuisine_preferences = row.get("cuisine preferences", "Unknown")
    skill_level = row.get("cooking skill level", "Unknown")
    prep_time = row.get("prep time", "Unknown")

    sentence = (
        f"**{meal_name}** (Meal ID: {meal_id}) is a **{meal_category}** meal, described as **{meal_description}**. "
        f"It contains **{ingredients}** as ingredients and pairs well with **{complementary_dishes}**. "
        f"This meal supports **{goal}** and is suitable for **{dietary_preference}** diets. "
        f"It avoids common allergens like **{allergies}** and helps in managing **{disease_management}**. "
        f"Popular in **{cuisine_preferences}** cuisine, it requires a **{skill_level}** skill level and takes **{prep_time}** to prepare. "
        f"The recipe can be found [here]({recipe_link})."
    )
    
    return sentence

# Apply the function to generate descriptions for both sheets
if "produce_id" in produce_df.columns:
    produce_df["produce_description"] = produce_df.apply(generate_produce_description, axis=1)

if "meal_id" in meal_df.columns:
    meal_df["meal_description"] = meal_df.apply(generate_meal_description, axis=1)

# Display the generated descriptions for both sheets
#print("Produce Descriptions:\n", produce_df[["produce_id", "produce_description"]])
#print("\nMeal Descriptions:\n", meal_df[["meal_id", "meal_description"]])

print("Produce Descriptions:\n", produce_df[["produce_id", "produce_description"]].to_string(index=False))
print("\nMeal Descriptions:\n", meal_df[["meal_id", "meal_description"]].to_string(index=False))


