from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import numpy as np
import joblib
import pickle
from datetime import datetime
import os
import tensorflow as tf
# import firebase_admin
# from firebase_admin import credentials, firestore

app = FastAPI(title="Digital Addiction Risk Platform AI Backend")

# Initialize Firebase (Uncomment when credentials are added)
# cred = credentials.Certificate("firebase_credentials.json")
# firebase_admin.initialize_app(cred)
# db = firestore.client()

# ==========================================
# Load Models (Wrap in try-except for dev without models)
# ==========================================
lstm_model = None
scaler_lstm = None
kmeans_model = None
scaler_kmeans = None
iso_model = None
dqn_q_table = None
recommendation_engine = None

try:
    if os.path.exists("models/lstm_prediction_model.h5"):
        lstm_model = tf.keras.models.load_model('models/lstm_prediction_model.h5')
        scaler_lstm = joblib.load('models/scaler_lstm.pkl')
        
    if os.path.exists("models/kmeans_cluster_model.pkl"):
        kmeans_model = joblib.load('models/kmeans_cluster_model.pkl')
        scaler_kmeans = joblib.load('models/scaler_kmeans.pkl')
        
    if os.path.exists("models/isolation_forest_model.pkl"):
        iso_model = joblib.load('models/isolation_forest_model.pkl')
        
    if os.path.exists("models/dqn_q_table.pkl"):
        with open('models/dqn_q_table.pkl', 'rb') as f:
            dqn_q_table = pickle.load(f)
            
    if os.path.exists("models/recommendation_engine.pkl"):
        with open('models/recommendation_engine.pkl', 'rb') as f:
            recommendation_engine = pickle.load(f)
            
    print("Models loaded successfully!")
except Exception as e:
    print(f"Error loading models: {e}")
    print("Provide models generated from Colab script to enable full AI features.")


# ==========================================
# Schema Definitions
# ==========================================
class ScreentimeData(BaseModel):
    user_id: str
    total_minutes: int
    social_pct: float
    gaming_pct: float
    night_use: int
    sessions: int

class Past30DaysRequest(BaseModel):
    user_id: str
    past_30_minutes: list[int]  # List of total minutes for past 30 days

class RiskRequest(BaseModel):
    user_id: str
    daily_total_minutes: int
    most_used_app: str
    session_count: int
    daily_limit_minutes: int

# ==========================================
# API Endpoints
# ==========================================

@app.get("/")
def read_root():
    return {"status": "AI Backend API is running"}

@app.post("/predict_risk")
def predict_risk(data: RiskRequest):
    # Heuristic Expert System Fallback
    base_score = 0
    
    # 1. Total Time Factor relative to custom limit
    # Safe guard against zero division
    limit = max(1, data.daily_limit_minutes)
    usage_percentage = data.daily_total_minutes / limit
    
    if usage_percentage >= 1.0:
        base_score += 60  # Crossed limit completely
    elif usage_percentage >= 0.8:
        base_score += 40  # 80%+ of limit
    elif usage_percentage >= 0.5:
        base_score += 20  # 50%+ of limit
    else:
        base_score += 5   # Under 50% limit
        
    # 2. Addictive App Factor
    addictive_apps = ["instagram", "tiktok", "youtube", "facebook", "snapchat", "reddit", "twitter", "x"]
    most_used = data.most_used_app.lower()
    if any(app in most_used for app in addictive_apps):
        base_score += 20
        
    # 3. Session Factor (Frequent checking)
    if data.session_count > 100:
        base_score += 20
    elif data.session_count > 50:
        base_score += 10
        
    # Clamp to 100
    score = min(100, base_score)
    
    # Classify
    if score >= 70:
        level = "High"
    elif score >= 40:
        level = "Medium"
    else:
        level = "Low"
        
    # Generate Recommendations
    recommendations = []
    
    if level == "High":
        recommendations.append({"title": "High Risk Alert", "desc": "Your screen time is critically high. Consider setting strict app timers and taking breaks every 30 minutes."})
        recommendations.append({"title": "Digital Detox Needed", "desc": "Try a 2-hour phone-free period today. Start with dinner time or before bed."})
    elif level == "Medium":
        recommendations.append({"title": "Moderate Usage", "desc": "Your usage is above average. Try to reduce by 30 minutes each day this week."})
        recommendations.append({"title": "Set Time Limits", "desc": "Use Android's Digital Wellbeing to set daily limits on your top apps."})
    else:
        recommendations.append({"title": "Healthy Usage!", "desc": "Great job! Your screen time is within healthy limits. Keep maintaining these habits."})
        recommendations.append({"title": "Keep It Up", "desc": "You're in the top 20% of healthy digital users. Share your tips with friends!"})
        
    if any(app in most_used for app in addictive_apps):
        recommendations.append({"title": f"Reduce {data.most_used_app}", "desc": f"You spend a significant amount of time on {data.most_used_app}. Consider setting a 1-hour limit."})
        
    if data.session_count > 80:
        recommendations.append({"title": "Compulsive Checking", "desc": f"You unlocked your phone {data.session_count} times. Try turning off non-essential notifications."})

    recommendations.append({"title": "Night Mode", "desc": "Avoid screen usage 1 hour before bed. Blue light disrupts sleep quality and increases addiction risk."})
    
    return {
        "user_id": data.user_id,
        "risk_level": level,
        "risk_score": score,
        "recommendations": recommendations
    }

@app.post("/predict")
def predict_7_days(data: Past30DaysRequest):
    if lstm_model is None:
        raise HTTPException(status_code=500, detail="LSTM model not loaded")
    
    if len(data.past_30_minutes) < 30:
        raise HTTPException(status_code=400, detail="Need 30 days of data for LSTM")
        
    # Scale input
    input_data = np.array(data.past_30_minutes[-30:]).reshape(-1, 1)
    scaled_input = scaler_lstm.transform(input_data)
    
    # Predict next 7 days (Iterative approach)
    predictions = []
    current_seq = scaled_input.reshape(1, 30, 1)
    
    for _ in range(7):
        pred = lstm_model.predict(current_seq)[0, 0]
        predictions.append(pred)
        # Update sequence
        current_seq = np.append(current_seq[:, 1:, :], [[[pred]]], axis=1)
        
    # Inverse transform
    real_predictions = scaler_lstm.inverse_transform(np.array(predictions).reshape(-1, 1)).flatten().tolist()
    
    return {"user_id": data.user_id, "7_day_predictions": real_predictions}

@app.post("/cluster")
def cluster_user(data: ScreentimeData):
    if kmeans_model is None:
        raise HTTPException(status_code=500, detail="K-Means model not loaded")
        
    features = np.array([[data.total_minutes, data.social_pct, data.gaming_pct, data.night_use]])
    scaled_features = scaler_kmeans.transform(features)
    cluster = int(kmeans_model.predict(scaled_features)[0])
    
    cluster_labels = ["Balanced", "Social Media Scroller", "Gamer", "Night Owl", "Binge Watcher"]
    
    return {"user_id": data.user_id, "cluster": cluster, "cluster_name": cluster_labels[cluster]}

@app.post("/detect_anomaly")
def detect_anomaly(data: ScreentimeData):
    if iso_model is None:
        raise HTTPException(status_code=500, detail="Isolation Forest model not loaded")
        
    features = np.array([[data.total_minutes, data.night_use, data.sessions]])
    # 1 for normal, -1 for anomaly
    prediction = iso_model.predict(features)[0]
    is_anomaly = prediction == -1
    
    return {"user_id": data.user_id, "anomaly_detected": is_anomaly}

@app.post("/rl_action")
def rl_action(cluster_id: int):
    # Retrieve best strategy based on Q-Table and User Cluster
    if dqn_q_table is None:
        return {"strategy": "reminders"}
        
    strategies = [
        "reminders", "app limits", "focus mode", "gradual reduction",
        "scheduled breaks", "gamification", "peer challenges", "reward system"
    ]
    best_action_idx = np.argmax(dqn_q_table[cluster_id])
    
    return {"strategy": strategies[best_action_idx]}

@app.post("/recommend")
def recommend_action(cluster_id: int):
    if recommendation_engine is None:
        return {"recommendations": ["Take a break."]}
        
    recs = recommendation_engine.get(cluster_id, ["Take a break."])
    return {"recommendations": recs}
