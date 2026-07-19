<div align="center">
  <h1>🧠 Digital Addiction Platform (ScreenCoach)</h1>
  <p><strong>An AI-Powered Screen Time Tracker & Behavioral Habit Coach</strong></p>

  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/TensorFlow-FF6F00?style=for-the-badge&logo=tensorflow&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white" />
</div>

<br />

## 📖 Overview
The **Digital Addiction Platform** is an advanced, cross-platform mobile application designed to combat smartphone addiction and promote healthy digital habits. 

Unlike basic screen time trackers, this platform goes a step further by integrating **Machine Learning (AI)** to analyze behavioral patterns, predict future usage, classify addiction risk levels, and deliver hyper-personalized coaching recommendations. The app aggressively monitors real-time foreground usage at the native Android hardware level and syncs chronologically to the cloud.

---

## ✨ Key Features

* **⏱️ Native Hardware-Level Tracking:** Uses Android's native `UsageStatsManager` to track exact foreground usage. Automatically filters out background audio apps and system UI processes for 100% accurate screen time reading.
* **☁️ Cloud Data Synchronization:** Automatically syncs daily usage statistics to a NoSQL Firebase Cloud Firestore database, ensuring a persistent historical record of habits over time.
* **📊 Dynamic Data Visualization:** Implements `fl_chart` to render a responsive, dynamically scaling 7-day Bar Graph of the user's weekly usage.
* **🤖 AI Predictive Backend (FastAPI + Scikit-Learn + TensorFlow):**
  * **LSTM Neural Networks:** Forecasts screen time usage for the next 7 days based on 30-day historical sequence data.
  * **K-Means Clustering:** Categorizes users into 5 distinct behavioral archetypes (e.g., "Night Owl", "Binge Watcher", "Social Scroller").
  * **Isolation Forest:** Detects severe usage anomalies in real-time.
  * **Heuristic Expert System:** Calculates a robust Risk Score (0-100) dynamically considering total time, addictive app usage, and session unlocks.
* **⚠️ Background Isolates & Native Alerts:** A headless Dart isolate continuously monitors device usage in the background every 15 minutes and triggers native Android Push Notifications if the user exceeds their daily limit.
* **📄 Automated PDF Reporting:** A fully programmatic canvas-painting engine compiles NoSQL data into a formatted, professional PDF report (complete with tables and bar graphs) that can be instantly shared or exported using native Android Intents.

---

## 🛠️ Technology Stack

### Mobile Frontend (App)
* **Framework:** Flutter (Dart)
* **State Management / UI:** Material 3 Design
* **Native Integrations:** `app_usage`, `flutter_background_service`, `flutter_local_notifications`
* **Data Visualization:** `fl_chart`
* **Document Generation:** `pdf`, `printing`

### Backend & Cloud
* **Database:** Firebase Cloud Firestore (NoSQL Document Database)
* **Authentication:** Google Sign-In & Firebase Auth

### AI & Machine Learning Pipeline
* **Backend Framework:** FastAPI (Python)
* **Data Processing:** Numpy, Pandas
* **Machine Learning:** Scikit-Learn (K-Means, Isolation Forest)
* **Deep Learning:** TensorFlow / Keras (LSTM Recurrent Neural Networks)

---

## 🧠 Machine Learning Methodology
Because collecting real-world, minute-by-minute behavioral data is an invasion of privacy, this project's AI models are trained on a **Synthetic Behavioral Dataset**. 

A specialized Python algorithm generates 90,000 data points simulating 1,000 distinct users across 90 days, applying normal (Gaussian) distributions to simulate variables like `social_pct`, `night_use`, and `sessions`. The data is deliberately seeded with 20% high-risk addictive profiles to provide supervised labels for outlier detection.

---

## 🚀 Getting Started

### Prerequisites
* Flutter SDK (3.x)
* Android Studio (with Android SDK 33+)
* Python 3.9+

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/Shantanu2806/digital-addiction-platform.git
   cd digital-addiction-platform
   ```

2. **Run the AI Backend**
   ```bash
   cd backend
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   pip install -r requirements.txt
   uvicorn main:app --reload --port 8000
   ```

3. **Run the Flutter Application**
   ```bash
   cd ../flutter_app/addiction_tracker/addiction_tracker
   flutter pub get
   flutter run
   ```

*(Note: The mobile app requires physical device installation for native `UsageStatsManager` API access. Emulators will not return correct screen time data.)*

---
*Built with ❤️ to foster healthier digital lives.*
