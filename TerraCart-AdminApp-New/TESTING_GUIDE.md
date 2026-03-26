# Testing Guide - Signup and Login

## ✅ Configuration Complete

### IP Address Updated
- **Your Computer IP**: `192.168.1.12`
- **API Base URL**: `http://192.168.1.12:5001/api`
- **Socket URL**: `http://192.168.1.12:5001`

### What Was Fixed
1. ✅ Updated API config with your IP address (192.168.1.12)
2. ✅ Added signup API endpoint
3. ✅ Implemented real signup functionality
4. ✅ Added required fields: Cafe Name, Location, Franchise ID
5. ✅ Improved error handling for network issues

## 🧪 Testing Steps

### Step 1: Start Backend Server
```bash
cd backend
npm start
# Server should be running on http://192.168.1.12:5001
```

### Step 2: Test Signup

1. **Open the app** and navigate to Signup screen
2. **Fill in the form**:
   - Full Name: `Test User`
   - Email: `test@example.com` (use a unique email)
   - Phone: `9876543210` (optional)
   - Cafe Name: `Test Cafe` ⭐ **Required**
   - Location: `Noida, Sector 18` ⭐ **Required**
   - Franchise ID: Leave empty or enter if you have one
   - Password: `password123` (min 6 characters)
   - Confirm Password: `password123`
   - Select Role: Staff/Cook/Manager
   - Agree to Terms ✓

3. **Click "Create Account"**
4. **Expected Result**:
   - If successful: Auto-login and navigate to dashboard
   - If franchise ID required: Shows error message
   - If email exists: Shows "Email already registered"

### Step 3: Test Login

1. **Navigate to Login screen** (or use existing account)
2. **Enter credentials**:
   - Email: The email you used for signup (or existing account)
   - Password: The password you set
   - Role: Select appropriate role

3. **Click "Sign In"**
4. **Expected Result**:
   - Success: Navigate to dashboard with attendance modal
   - Error: Shows error message (check backend logs)

## 🔍 Troubleshooting

### Issue: "Request timeout"
**Solution**: 
- Check if backend server is running
- Verify firewall allows port 5001
- Check if IP address is correct (192.168.1.12)

### Issue: "Franchise ID is required"
**Solution**: 
- The backend requires franchiseId for public signup
- You can either:
  1. Get a franchise ID from your admin
  2. Create a franchise admin first in the backend
  3. Temporarily modify backend to make it optional (not recommended)

### Issue: "Cannot connect to server"
**Solution**:
- Ensure device/emulator is on same Wi-Fi network
- Check backend CORS settings allow your app
- Verify backend is listening on 0.0.0.0 (not just localhost)

### Issue: "Email already registered"
**Solution**: 
- Use a different email address
- Or login with existing credentials

## 📝 Backend Requirements

Make sure your backend:
1. ✅ Is running on port 5001
2. ✅ Allows CORS from your Flutter app
3. ✅ Has the `/api/users/register-cafe-admin-public` endpoint
4. ✅ Has the `/api/admin/login` endpoint
5. ✅ Database is connected and working

## 🎯 Quick Test Checklist

- [ ] Backend server is running
- [ ] Can access `http://192.168.1.12:5001/api` from browser
- [ ] Signup form shows all required fields
- [ ] Signup creates account successfully
- [ ] Login works with created account
- [ ] Dashboard loads after login
- [ ] No network errors on any screen

## 💡 Tips

1. **For Emulator**: If using Android emulator, change IP back to `10.0.2.2:5001`
2. **For Physical Device**: Keep `192.168.1.12:5001` (current setting)
3. **Check Backend Logs**: Watch console for API requests
4. **Test API Directly**: Use Postman/curl to test endpoints first

## 🔄 If IP Changes

If your computer's IP address changes, update:
- `lib/core/config/api_config.dart`
- Change `baseUrl` and `socketUrl` to new IP

