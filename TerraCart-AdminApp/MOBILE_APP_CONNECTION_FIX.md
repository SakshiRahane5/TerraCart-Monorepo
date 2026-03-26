# Mobile App Connection Fix (Login Timeout)

If you see `TimeoutException` or "Cannot reach server" when logging in from the mobile app, the device cannot reach your backend. Follow these steps:

## 1. Verify Backend is Running

```bash
cd backend
npm run dev
# or: node server.js
```

You should see: `🚀 Server running on port 5001`

## 2. Test from Your Computer

Open browser: http://localhost:5001/health

You should see: `{"status":"healthy"}`

## 3. Add Windows Firewall Rule (Most Common Fix)

Windows Firewall blocks incoming connections by default. Run **PowerShell as Administrator**:

```powershell
New-NetFirewallRule -DisplayName "TerraCart Backend 5001" -Direction Inbound -LocalPort 5001 -Protocol TCP -Action Allow
```

Or via Command Prompt (Admin):

```cmd
netsh advfirewall firewall add rule name="TerraCart Backend 5001" dir=in action=allow protocol=TCP localport=5001
```

## 4. Verify Your IP Address

Run `ipconfig` and note your **IPv4 Address** (e.g., 192.168.1.16).

Update `lib/core/config/api_config.dart` if your IP changed:

```dart
static const String baseUrl = 'http://YOUR_IP:5001/api';
static const String socketUrl = 'http://YOUR_IP:5001';
```

## 5. Same Network Required

- Phone and computer must be on the **same WiFi network**
- If phone is on mobile data, it cannot reach your computer's local IP

## 6. Test from Phone Browser

On your phone's browser, open: `http://YOUR_IP:5001/health`

If this fails, the firewall rule or network is the issue.
