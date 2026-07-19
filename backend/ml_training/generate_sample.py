import csv
import random
import numpy as np

num_users = 100
days_per_user = 5 # 100 users * 5 days = 500 rows
data = []

user_id_counter = 0
for u in range(num_users):
    is_addict = random.random() < 0.2
    base_minutes = random.randint(300, 600) if is_addict else random.randint(60, 240)
    for d in range(1, days_per_user + 1):
        minutes = int(np.clip(np.random.normal(base_minutes, 60), 10, 800))
        social_pct = round(random.uniform(0.1, 0.8), 2)
        gaming_pct = round(random.uniform(0, 0.6), 2)
        night_use = random.randint(0, 120) if is_addict else random.randint(0, 30)
        sessions = random.randint(10, 50) if is_addict else random.randint(5, 20)
        data.append([user_id_counter, d, minutes, social_pct, gaming_pct, night_use, sessions])
    user_id_counter += 1

with open("sample_dataset.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["user_id", "day", "total_minutes", "social_pct", "gaming_pct", "night_use", "sessions"])
    writer.writerows(data)

print("Successfully generated 500 rows!")
