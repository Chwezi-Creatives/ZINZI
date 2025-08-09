-- Rename the id column to meal_plan_id in the meal_plans table
ALTER TABLE meal_plans RENAME COLUMN id TO meal_plan_id;

-- Rename the sequence if it exists
ALTER SEQUENCE IF EXISTS meal_plans_id_seq RENAME TO meal_plans_meal_plan_id_seq;

-- Update the default value for the meal_plan_id column
ALTER TABLE meal_plans ALTER COLUMN meal_plan_id SET DEFAULT nextval('meal_plans_meal_plan_id_seq'::regclass);

-- Update the foreign key in meal_plan_meals table
ALTER TABLE meal_plan_meals 
  DROP CONSTRAINT IF EXISTS meal_plan_meals_meal_plan_id_fkey,
  ADD CONSTRAINT meal_plan_meals_meal_plan_id_fkey 
  FOREIGN KEY (meal_plan_id) REFERENCES meal_plans(meal_plan_id);
