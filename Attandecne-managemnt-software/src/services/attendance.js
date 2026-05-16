import { db, rtdb } from '../firebase/config';
import { collection, doc, setDoc, getDoc, updateDoc, query, where, getDocs, onSnapshot, orderBy } from 'firebase/firestore';
import { ref, set, onValue, onDisconnect, serverTimestamp as rtdbTimestamp } from 'firebase/database';
import { format, differenceInMinutes } from 'date-fns';

// ── Office Configuration ──
const OFFICE_LAT = parseFloat(import.meta.env.VITE_OFFICE_LAT) || 33.717810797788445;
const OFFICE_LNG = parseFloat(import.meta.env.VITE_OFFICE_LNG) || 73.07266545222373;
const RADIUS_METERS = 100;
const OFFICE_IP = import.meta.env.VITE_OFFICE_IP || "YOUR_OFFICE_IP_HERE";

const OFFICE_START_MINUTES = 9 * 60 + 45; // 9:45 AM
const OFFICE_END_MINUTES = 17 * 60 + 45;  // 5:45 PM

const HEARTBEAT_INTERVAL = 60000;       // 60 seconds
const LOCATION_INTERVAL = 120000;       // 2 minutes
const STALE_SESSION_GRACE_MS = 2 * 60 * 1000; // 2-minute grace

// ── Haversine Formula ──
export function getDistanceFromLatLonInM(lat1, lon1, lat2, lon2) {
  const R = 6371e3;
  const dLat = (lat2 - lat1) * (Math.PI / 180);
  const dLon = (lon2 - lon1) * (Math.PI / 180);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * (Math.PI / 180)) * Math.cos(lat2 * (Math.PI / 180)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

// ── Attendance ID (one per user per day, backward compatible) ──
export const getTodayAttendanceId = (userId) => {
  const today = format(new Date(), 'yyyy-MM-dd');
  return `${userId}_${today}`;
};

// ── Fetch Today's Attendance ──
export const fetchTodayAttendance = async (userId) => {
  const attendanceId = getTodayAttendanceId(userId);
  const docSnap = await getDoc(doc(db, 'attendance', attendanceId));
  if (docSnap.exists()) return { id: docSnap.id, ...docSnap.data() };
  return null;
};

// ── Check In ──
export const checkIn = async (userId) => {
  const attendanceId = getTodayAttendanceId(userId);
  const today = format(new Date(), 'yyyy-MM-dd');
  const now = new Date();
  const nowIso = now.toISOString();

  // Prevent duplicate check-in
  const existing = await getDoc(doc(db, 'attendance', attendanceId));
  if (existing.exists()) return existing.data();

  // Close any previous unclosed sessions (safety net)
  await closeStaleSession(userId);

  // Fetch user's IP
  let userIp = "";
  try {
    const response = await fetch('https://api.ipify.org?format=json');
    const data = await response.json();
    userIp = data.ip;
  } catch (err) {
    console.error("Failed to fetch IP", err);
  }

  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      resolve(processCheckIn(userId, attendanceId, false, userIp, null, today, nowIso));
    } else {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          const { latitude, longitude } = position.coords;
          const distance = getDistanceFromLatLonInM(OFFICE_LAT, OFFICE_LNG, latitude, longitude);
          const isLocationValid = distance <= RADIUS_METERS;
          const isIpValid = userIp === OFFICE_IP && OFFICE_IP !== "YOUR_OFFICE_IP_HERE";
          const isPresent = isLocationValid || isIpValid;
          resolve(processCheckIn(userId, attendanceId, isPresent, userIp, { lat: latitude, lng: longitude, distanceFromOffice: Math.round(distance) }, today, nowIso));
        },
        () => {
          const isIpValid = userIp === OFFICE_IP && OFFICE_IP !== "YOUR_OFFICE_IP_HERE";
          resolve(processCheckIn(userId, attendanceId, isIpValid, userIp, null, today, nowIso));
        },
        { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 }
      );
    }
  });
};

// ── Process Check-In (builds the attendance document) ──
const processCheckIn = async (userId, attendanceId, isAtOffice, ipAddress, location, dateStr, nowIso) => {
  const now = new Date();
  const userRef = doc(db, 'users', userId);
  const userSnap = await getDoc(userRef);
  const userData = userSnap.data();

  const currentMinutes = now.getHours() * 60 + now.getMinutes();

  let finalStatus = 'outside';
  if (isAtOffice) {
    finalStatus = currentMinutes <= OFFICE_START_MINUTES ? 'present' : 'late';
  }

  const data = {
    userId,
    userName: userData?.name || 'Unknown',
    department: userData?.department || 'N/A',
    date: dateStr,
    checkInTime: nowIso,
    checkOutTime: null,
    status: finalStatus,
    sessionStatus: 'active',           // NEW: session lifecycle
    ipAddress,
    location,
    atOffice: isAtOffice,
    insideTime: 0,                      // minutes
    outsideTime: 0,                     // minutes
    extraHours: 0,                      // minutes
    offlineTime: 0,                     // minutes
    insideOfficeTime: 0,                // milliseconds (for performance scoring)
    totalHours: 0,                      // decimal hours
    lastActive: nowIso
  };

  await setDoc(doc(db, 'attendance', attendanceId), data);

  // Store initial location snapshot
  if (location && location.lat && location.lng) {
    await setDoc(doc(collection(db, 'locations')), {
      userId,
      lat: location.lat,
      lng: location.lng,
      distanceFromOffice: location.distanceFromOffice || 0,
      timestamp: nowIso,
      status: finalStatus,
      insideRadius: isAtOffice,
    });
  }

  return data;
};

// ── Check Out ──
export const checkOut = async (userId) => {
  const attendanceId = getTodayAttendanceId(userId);
  const docRef = doc(db, 'attendance', attendanceId);
  const docSnap = await getDoc(docRef);

  if (!docSnap.exists()) return null;

  const attData = docSnap.data();
  if (attData.checkOutTime) return attData; // Already checked out

  const nowIso = new Date().toISOString();
  const totalHours = computeTotalHours(attData.checkInTime, nowIso);

  // Calculate insideOfficeTime in ms from insideTime (minutes)
  const insideOfficeMs = (attData.insideTime || 0) * 60 * 1000;

  await updateDoc(docRef, {
    checkOutTime: nowIso,
    lastActive: nowIso,
    sessionStatus: 'ended',
    totalHours,
    insideOfficeTime: insideOfficeMs
  });

  // Mark presence offline in RTDB
  try {
    const presenceRef = ref(rtdb, `presence/${userId}`);
    await set(presenceRef, { online: false, lastSeen: nowIso });
  } catch (e) {
    console.warn("RTDB presence update failed on checkout", e);
  }

  return fetchTodayAttendance(userId);
};

// ── Close Stale Sessions (safety net for crashes/disconnects) ──
const closeStaleSession = async (userId) => {
  const yesterday = new Date();
  yesterday.setDate(yesterday.getDate() - 1);
  const yesterdayStr = format(yesterday, 'yyyy-MM-dd');
  const yesterdayId = `${userId}_${yesterdayStr}`;

  const docRef = doc(db, 'attendance', yesterdayId);
  const docSnap = await getDoc(docRef);

  if (docSnap.exists()) {
    const data = docSnap.data();
    if (!data.checkOutTime && data.sessionStatus === 'active') {
      // Auto-close using lastActive + grace period
      const closeTime = data.lastActive
        ? new Date(new Date(data.lastActive).getTime() + STALE_SESSION_GRACE_MS).toISOString()
        : data.checkInTime;
      const totalHours = computeTotalHours(data.checkInTime, closeTime);
      const insideOfficeMs = (data.insideTime || 0) * 60 * 1000;

      await updateDoc(docRef, {
        checkOutTime: closeTime,
        sessionStatus: 'auto-closed',
        totalHours,
        insideOfficeTime: insideOfficeMs
      });
    }
  }
};

// ── Compute Total Hours (decimal) ──
function computeTotalHours(checkInIso, checkOutIso) {
  if (!checkInIso || !checkOutIso) return 0;
  const diffMs = new Date(checkOutIso).getTime() - new Date(checkInIso).getTime();
  return Math.max(0, parseFloat((diffMs / (1000 * 60 * 60)).toFixed(2)));
}

// ── Heartbeat + RTDB Presence ──
export const startHeartbeat = (userId) => {
  let intervalId = null;

  const sendHeartbeat = async () => {
    try {
      const nowIso = new Date().toISOString();

      // 1. Firestore heartbeat
      await setDoc(doc(db, 'heartbeats', userId), {
        userId,
        lastSeen: nowIso,
        online: true,
      });

      // 2. Update attendance lastActive + recalculate totalHours
      const attendanceId = getTodayAttendanceId(userId);
      const attRef = doc(db, 'attendance', attendanceId);
      const attSnap = await getDoc(attRef);
      if (attSnap.exists()) {
        const attData = attSnap.data();
        if (!attData.checkOutTime && attData.sessionStatus === 'active') {
          const totalHours = computeTotalHours(attData.checkInTime, nowIso);
          await updateDoc(attRef, { lastActive: nowIso, totalHours });
        }
      }
    } catch (e) {
      console.warn("Heartbeat failed", e);
    }
  };

  // ── RTDB Presence System ──
  const setupPresence = () => {
    try {
      const presenceRef = ref(rtdb, `presence/${userId}`);
      const connectedRef = ref(rtdb, '.info/connected');

      onValue(connectedRef, (snapshot) => {
        if (snapshot.val() === true) {
          // We're connected — set up onDisconnect first
          const disconnectRef = onDisconnect(presenceRef);
          disconnectRef.set({
            online: false,
            lastSeen: new Date().toISOString()
          }).then(() => {
            // Now mark ourselves online
            set(presenceRef, {
              online: true,
              lastSeen: new Date().toISOString()
            });
          });
        }
      });
    } catch (e) {
      console.warn("RTDB presence setup failed (may not have databaseURL configured)", e);
    }
  };

  // ── beforeunload: Mark offline as best-effort ──
  const markOffline = async () => {
    try {
      const nowIso = new Date().toISOString();
      await setDoc(doc(db, 'heartbeats', userId), {
        userId,
        lastSeen: nowIso,
        online: false,
      });
    } catch (_) { }
  };

  // Initialize
  setupPresence();
  sendHeartbeat();
  intervalId = setInterval(sendHeartbeat, HEARTBEAT_INTERVAL);
  window.addEventListener('beforeunload', markOffline);

  // Return cleanup function
  return () => {
    if (intervalId) clearInterval(intervalId);
    window.removeEventListener('beforeunload', markOffline);
    markOffline();
  };
};

// ── Location Tracking ──
export const trackLocation = (userId) => {
  let lastLat = null;
  let lastLng = null;

  if (!navigator.geolocation) return () => {};

  const sendLocation = () => {
    navigator.geolocation.getCurrentPosition(async (position) => {
      const { latitude, longitude } = position.coords;

      // Skip if position hasn't changed significantly (< 5m)
      if (lastLat && lastLng) {
        const distance = getDistanceFromLatLonInM(lastLat, lastLng, latitude, longitude);
        if (distance < 5) return;
      }

      lastLat = latitude;
      lastLng = longitude;

      const distFromOffice = getDistanceFromLatLonInM(OFFICE_LAT, OFFICE_LNG, latitude, longitude);
      const isInside = distFromOffice <= RADIUS_METERS;
      const now = new Date();
      const nowIso = now.toISOString();

      // Store location point
      await setDoc(doc(collection(db, 'locations')), {
        userId,
        timestamp: nowIso,
        lat: latitude,
        lng: longitude,
        distanceFromOffice: Math.round(distFromOffice),
        insideRadius: isInside,
      });

      // Update time tracking on attendance
      const attendanceId = getTodayAttendanceId(userId);
      const attRef = doc(db, 'attendance', attendanceId);
      const attSnap = await getDoc(attRef);

      if (attSnap.exists()) {
        const attData = attSnap.data();
        if (!attData.checkOutTime && attData.sessionStatus === 'active') {
          const currentMinutes = now.getHours() * 60 + now.getMinutes();
          let updates = {};

          if (attData.lastActive) {
            const lastDate = new Date(attData.lastActive);
            const diffMins = differenceInMinutes(now, lastDate);

            // Only add if reasonable (< 15 mins gap means user was active)
            if (diffMins > 0 && diffMins < 15) {
              if (currentMinutes > OFFICE_END_MINUTES) {
                updates.extraHours = (attData.extraHours || 0) + diffMins;
              } else if (currentMinutes >= OFFICE_START_MINUTES && currentMinutes <= OFFICE_END_MINUTES) {
                if (isInside) {
                  updates.insideTime = (attData.insideTime || 0) + diffMins;
                } else {
                  updates.outsideTime = (attData.outsideTime || 0) + diffMins;
                }
              } else if (currentMinutes < OFFICE_START_MINUTES) {
                updates.outsideTime = (attData.outsideTime || 0) + diffMins;
              }
            } else if (diffMins >= 15) {
              updates.offlineTime = (attData.offlineTime || 0) + diffMins;
            }
          }

          // Recalculate totalHours and insideOfficeTime
          const newInsideTime = updates.insideTime ?? attData.insideTime ?? 0;
          updates.insideOfficeTime = newInsideTime * 60 * 1000; // ms for perf scoring
          updates.totalHours = computeTotalHours(attData.checkInTime, nowIso);
          updates.lastActive = nowIso;

          await updateDoc(attRef, updates);
        }
      }
    }, (error) => {
      console.warn("Tracking error:", error);
    }, { enableHighAccuracy: true, timeout: 10000, maximumAge: 0 });
  };

  sendLocation();
  const interval = setInterval(sendLocation, LOCATION_INTERVAL);

  return () => clearInterval(interval);
};
