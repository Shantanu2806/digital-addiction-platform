
import numpy as np
import pandas as pd
import joblib
from sklearn.cluster import KMeans
from sklearn.ensemble import IsolationForest
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import MinMaxScaler
import tensorflow as tf
from tensorflow.keras.models import Sequential
from tensorflow.keras.layers import LSTM, Dense, Dropout
import random

# ==========================================
# 1. Generate Synthetic Behavioral Dataset
# ==========================================
print("Generating Synthetic Data...")
num_users = 1000
days = 90
data = []

for u in range(num_users):
    # Determine base profile
    is_addict = random.random() < 0.2
    base_minutes = random.randint(300, 600) if is_addict else random.randint(60, 240)
    for d in range(days):
        minutes = int(np.clip(np.random.normal(base_minutes, 60), 10, 800))
        social_pct = random.uniform(0.1, 0.8)
        gaming_pct = random.uniform(0, 0.6)
        night_use = random.randint(0, 120) if is_addict else random.randint(0, 30)
        sessions = random.randint(10, 50) if is_addict else random.randint(5, 20)
        data.append([u, d, minutes, social_pct, gaming_pct, night_use, sessions])

df = pd.DataFrame(data, columns=['user_id', 'day', 'total_minutes', 'social_pct', 'gaming_pct', 'night_use', 'sessions'])
print("Dataset shape:", df.shape)

# ==========================================
# 2. LSTM Prediction Model (7-day Forecast)
# ==========================================
print("\nTraining LSTM Prediction Model...")
scaler = MinMaxScaler()
# We will predict next day's total minutes based on past 30 days
# Creating sequences of 30 days
seq_length = 30
X, y = [], []

user_groups = df.groupby('user_id')
for _, group in user_groups:
    group_minutes = group['total_minutes'].values
    if len(group_minutes) >= seq_length + 1:
        scaled_minutes = scaler.fit_transform(group_minutes.reshape(-1, 1))
        for i in range(len(scaled_minutes) - seq_length):
            X.append(scaled_minutes[i:i+seq_length])
            y.append(scaled_minutes[i+seq_length])

X, y = np.array(X), np.array(y)
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

lstm_model = Sequential([
    LSTM(128, return_sequences=True, input_shape=(seq_length, 1)),
    Dropout(0.2),
    LSTM(64),
    Dense(32, activation='relu'),
    Dense(1)
])
lstm_model.compile(optimizer='adam', loss='mse')
lstm_model.fit(X_train, y_train, epochs=5, batch_size=64, validation_split=0.1, verbose=1)
lstm_model.save('lstm_prediction_model.h5')
joblib.dump(scaler, 'scaler_lstm.pkl')
print("Saved lstm_prediction_model.h5")

# ==========================================
# 3. K-Means Clustering Model (5 Types)
# ==========================================
print("\nTraining K-Means Clustering Model...")
# Features: avg total_minutes, avg social, avg gaming, avg night
user_stats = df.groupby('user_id').mean().drop(columns=['day'])
scaler_kmeans = MinMaxScaler()
X_cluster = scaler_kmeans.fit_transform(user_stats)

kmeans = KMeans(n_clusters=5, random_state=42)
kmeans.fit(X_cluster)
joblib.dump(kmeans, 'kmeans_cluster_model.pkl')
joblib.dump(scaler_kmeans, 'scaler_kmeans.pkl')
print("Saved kmeans_cluster_model.pkl")

# ==========================================
# 4. Isolation Forest (Anomaly Detection)
# ==========================================
print("\nTraining Isolation Forest...")
# Anomaly if: 3x spikes, 5+ hour sessions, late night binges
# Real-time features: total_minutes, night_use, sessions
iso_features = df[['total_minutes', 'night_use', 'sessions']].values
iso_model = IsolationForest(contamination=0.03, random_state=42)
iso_model.fit(iso_features)
joblib.dump(iso_model, 'isolation_forest_model.pkl')
print("Saved isolation_forest_model.pkl")

# ==========================================
# 5. DQN Reinforcement Learning (Simulated logic) 
# ==========================================
print("\nTraining DQN Recommendation Agent...")
# For simplicity in this script, we'll save a pre-trained dummy structure 
# or a simple dictionary matrix q-table that acts like a DQN strategy selector
# Real DQN requires an environment and tensorflow agents
import pickle
q_table = np.random.uniform(size=(5, 8)) # 5 clusters, 8 strategies
with open('dqn_q_table.pkl', 'wb') as f:
    pickle.dump(q_table, f)
print("Saved dqn_q_table.pkl (Simulated RL Weights)")

# ==========================================
# 6. Recommendation Engine (Content-Based)
# ==========================================
print("\nTraining Recommendation Engine...")
recommendation_map = {
    0: ["Try 25-min Pomodoro focuses.", "Lock social media for 2 hours."],
    1: ["Schedule offline reading for 30 mins.", "Use wind-down mode at 10 PM."],
    2: ["Turn off device an hour before bed.", "Keep phone out of bedroom."],
    3: ["Set app limits on Gaming.", "Replace gaming with physical exercise."],
    4: ["Set app limits on Streaming apps.", "Try a 24-hr digital detox."]
}
with open('recommendation_engine.pkl', 'wb') as f:
    pickle.dump(recommendation_map, f)
print("Saved recommendation_engine.pkl")

print("\nAll models trained and saved successfully!")
print("Please run: from google.colab import files")
print("files.download('lstm_prediction_model.h5')")
print("files.download('scaler_lstm.pkl')")
print("files.download('kmeans_cluster_model.pkl')")
print("files.download('scaler_kmeans.pkl')")
print("files.download('isolation_forest_model.pkl')")
print("files.download('dqn_q_table.pkl')")
print("files.download('recommendation_engine.pkl')")
