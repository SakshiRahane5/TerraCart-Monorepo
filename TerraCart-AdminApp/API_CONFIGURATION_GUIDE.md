# API Configuration Guide

## 🔧 Fixing Network Errors

If you're seeing "Network error. Please check your connection" on all screens, follow these steps:

### Step 1: Check Your Backend Server

Make sure your Node.js backend server is running:
```bash
cd backend
npm start
# or
node server.js
```

The server should be running on port **5001** (or whatever port you configured).

### Step 2: Update API URL Based on Your Setup

Edit `lib/core/config/api_config.dart` and update the `baseUrl`:

#### For Android Emulator (Default - Already Set)
```dart
static const String baseUrl = 'http://10.0.2.2:5001/api';
static const String socketUrl = 'http://10.0.2.2:5001';
```

#### For iOS Simulator
```dart
static const String baseUrl = 'http://localhost:5001/api';
static const String socketUrl = 'http://localhost:5001';
```

#### For Physical Device (Android/iOS)
1. Find your computer's IP address:
   - **Windows**: Open Command Prompt and run `ipconfig` - look for "IPv4 Address"
   - **Mac/Linux**: Open Terminal and run `ifconfig` or `ip addr` - look for "inet"
   
2. Update the URL (example if your IP is 192.168.1.100):
```dart
static const String baseUrl = 'http://192.168.1.100:5001/api';
static const String socketUrl = 'http://192.168.1.100:5001';
```

**Important**: 
- Make sure your phone/device is on the **same Wi-Fi network** as your computer
- Make sure your firewall allows connections on port 5001
- Make sure your backend server is configured to accept connections from your network (not just localhost)

### Step 3: Test the Connection

1. Open a browser on your device/emulator
2. Try to access: `http://YOUR_IP:5001/api/dashboard/stats` (or any API endpoint)
3. If you get a response, the connection works!

### Step 4: Common Issues

#### Issue: "Connection refused"
- **Solution**: Backend server is not running or not listening on the correct port

#### Issue: "Failed host lookup"
- **Solution**: Wrong IP address or device not on same network

#### Issue: "Request timeout"
- **Solution**: Firewall blocking connection or server not responding

#### Issue: Works on emulator but not physical device
- **Solution**: Change from `localhost` or `10.0.2.2` to your computer's actual IP address

### Step 5: Verify Backend CORS Settings

Make sure your backend allows requests from your Flutter app. In your backend `server.js`:

```javascript
app.use(cors({
  origin: '*', // Or specify your app's origin
  credentials: true
}));
```

## 📱 Quick Reference

| Environment | baseUrl |
|------------|---------|
| Android Emulator | `http://10.0.2.2:5001/api` |
| iOS Simulator | `http://localhost:5001/api` |
| Physical Device | `http://YOUR_COMPUTER_IP:5001/api` |

## 🔍 Debugging Tips

1. Check backend logs when making requests
2. Use browser DevTools Network tab to see if requests are being made
3. Check Flutter console for detailed error messages
4. Verify the backend is accessible by testing with Postman or curl

## ✅ After Configuration

1. Restart your Flutter app
2. Try logging in again
3. Check if data loads on dashboard and other screens

If you still see errors, check:
- Backend server logs
- Flutter console output
- Network connectivity between device and server

