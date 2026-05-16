import { useEffect, useState } from 'react';
import { useAuth } from '../hooks/useAuth';
import { fetchTodayAttendance, checkIn, checkOut, trackLocation, startHeartbeat } from '../services/attendance';
import { format, parseISO, isWithinInterval } from 'date-fns';
import { FaCheckCircle, FaTimesCircle, FaMapMarkerAlt, FaClock, FaHistory, FaMapMarkedAlt, FaSignOutAlt, FaSignInAlt } from 'react-icons/fa';
import { db } from '../firebase/config';
import { collection, query, where, getDocs, onSnapshot } from 'firebase/firestore';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

delete L.Icon.Default.prototype._getIconUrl;

const greenIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});

const blueIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});

function ChangeView({ center, zoom }) {
  const map = useMap();
  map.setView(center, zoom);
  return null;
}

const formatMinutes = (mins) => {
  if (!mins) return '0h 0m';
  const h = Math.floor(mins / 60);
  const m = mins % 60;
  return `${h}h ${m}m`;
};

export default function EmployeeDashboard() {
  const { user } = useAuth();
  const [todayAttendance, setTodayAttendance] = useState(null);
  const [history, setHistory] = useState([]);
  const [filterMonth, setFilterMonth] = useState(format(new Date(), 'yyyy-MM'));
  const [loading, setLoading] = useState(true);
  const [currentLoc, setCurrentLoc] = useState(null);
  const [actionLoading, setActionLoading] = useState(false);
  const [cleanupFns, setCleanupFns] = useState([]);

  useEffect(() => {
    async function init() {
      if (!user) return;
      try {
        const att = await fetchTodayAttendance(user.uid);
        setTodayAttendance(att);
        
        const histQuery = query(collection(db, 'attendance'), where('userId', '==', user.uid));
        const histSnap = await getDocs(histQuery);
        let histData = histSnap.docs.map(d => ({ id: d.id, ...d.data() }));
        histData.sort((a,b) => new Date(b.date) - new Date(a.date));
        setHistory(histData);

        // Only track if checked in and session is active
        let stopTracking, stopHeartbeat;
        if (att && att.checkInTime && !att.checkOutTime && att.sessionStatus !== 'ended') {
           stopTracking = trackLocation(user.uid);
           stopHeartbeat = startHeartbeat(user.uid);
        }

        const qLoc = query(collection(db, 'locations'), where('userId', '==', user.uid));
        const unsubscribe = onSnapshot(qLoc, (snapshot) => {
            const locs = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
            if (locs.length > 0) {
               locs.sort((a,b) => new Date(b.timestamp) - new Date(a.timestamp));
               setCurrentLoc(locs[0]);
            }
        });

        // Listen to today's attendance document live
        const todayDate = format(new Date(), 'yyyy-MM-dd');
        const qToday = query(collection(db, 'attendance'), where('userId', '==', user.uid), where('date', '==', todayDate));
        const unsubToday = onSnapshot(qToday, (snap) => {
           if (!snap.empty) {
              setTodayAttendance({ id: snap.docs[0].id, ...snap.docs[0].data() });
           }
        });

        return () => {
           stopTracking && stopTracking();
           stopHeartbeat && stopHeartbeat();
           unsubscribe();
           unsubToday();
        };

      } catch (err) {
        console.error("Dashboard init failed", err);
      } finally {
        setLoading(false);
      }
    }
    const cleanup = init();
    return () => {
       cleanup.then(fn => fn && fn());
    };
  }, [user]);

  const handleCheckIn = async () => {
    setActionLoading(true);
    try {
      const result = await checkIn(user.uid);
      setTodayAttendance(result);
      // Start tracking dynamically instead of reloading
      const stopTracking = trackLocation(user.uid);
      const stopHeartbeat = startHeartbeat(user.uid);
      setCleanupFns(prev => [...prev, stopTracking, stopHeartbeat]);
    } catch (err) {
      console.error("Check-in failed", err);
    }
    setActionLoading(false);
  };

  const handleCheckOut = async () => {
    setActionLoading(true);
    try {
      const result = await checkOut(user.uid);
      setTodayAttendance(result);
      // Stop tracking
      cleanupFns.forEach(fn => fn && fn());
      setCleanupFns([]);
    } catch (err) {
      console.error("Check-out failed", err);
    }
    setActionLoading(false);
  };

  if (loading) return (
    <div className="flex justify-center py-20 text-indigo-600 font-medium">
      Loading Dashboard...
    </div>
  );

  const status = todayAttendance?.status || 'Pending';
  const hasCheckedIn = !!todayAttendance?.checkInTime;
  const hasCheckedOut = !!todayAttendance?.checkOutTime;

  const [year, month] = filterMonth.split('-');
  const filterStart = new Date(year, month - 1, 1);
  const filterEnd = new Date(year, month, 0, 23, 59, 59);

  const filteredHistory = history.filter(record => {
     if (!record.checkInTime) return false;
     return isWithinInterval(new Date(record.checkInTime), { start: filterStart, end: filterEnd });
  });

  return (
    <div className="max-w-7xl mx-auto space-y-8">
      <div className="flex flex-col md:flex-row justify-between items-start md:items-center">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Attendance Dashboard</h1>
          <p className="text-sm text-gray-500 mt-1">{format(new Date(), 'EEEE, MMMM do, yyyy')}</p>
        </div>
        <div className="mt-4 md:mt-0 flex gap-4">
          {!hasCheckedIn ? (
            <button 
              onClick={handleCheckIn} disabled={actionLoading}
              className="flex items-center px-6 py-3 bg-green-600 hover:bg-green-700 text-white font-bold rounded-xl shadow-lg transition-all disabled:opacity-50"
            >
              <FaSignInAlt className="mr-2" /> Check In
            </button>
          ) : !hasCheckedOut ? (
            <button 
              onClick={handleCheckOut} disabled={actionLoading}
              className="flex items-center px-6 py-3 bg-red-600 hover:bg-red-700 text-white font-bold rounded-xl shadow-lg transition-all disabled:opacity-50"
            >
              <FaSignOutAlt className="mr-2" /> Check Out
            </button>
          ) : (
            <div className="px-6 py-3 bg-gray-100 text-gray-600 font-bold rounded-xl flex items-center border border-gray-200">
              <FaCheckCircle className="mr-2 text-green-500" /> Shift Completed
            </div>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Today Stats */}
        <div className="lg:col-span-1 space-y-6">
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
            <div className="px-6 py-6 border-b border-gray-100 bg-gray-50">
               <h3 className="text-lg font-semibold text-gray-900 mb-4">Today's Summary</h3>
               <div className="grid grid-cols-2 gap-4">
                  <div>
                    <p className="text-xs text-gray-500 font-bold uppercase">Check In</p>
                    <p className="font-bold text-gray-900">{todayAttendance?.checkInTime ? format(new Date(todayAttendance.checkInTime), 'hh:mm a') : '--:--'}</p>
                  </div>
                  <div>
                    <p className="text-xs text-gray-500 font-bold uppercase">Check Out</p>
                    <p className="font-bold text-gray-900">{todayAttendance?.checkOutTime ? format(new Date(todayAttendance.checkOutTime), 'hh:mm a') : '--:--'}</p>
                  </div>
               </div>
               <div className="mt-4 pt-4 border-t border-gray-200 flex items-center justify-between">
                  <span className="text-sm font-bold text-gray-500">Status</span>
                  <span className={`px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider ${
                    status === 'present' ? 'bg-green-100 text-green-700' :
                    status === 'late' ? 'bg-yellow-100 text-yellow-700' :
                    status === 'outside' ? 'bg-orange-100 text-orange-700' : 'bg-gray-100 text-gray-600'
                  }`}>
                    {status}
                  </span>
               </div>
               {todayAttendance?.totalHours > 0 && (
                 <div className="mt-3 flex items-center justify-between">
                    <span className="text-sm font-bold text-gray-500">Total Hours</span>
                    <span className="text-lg font-black text-indigo-600">{todayAttendance.totalHours}h</span>
                 </div>
               )}
            </div>
            
            <div className="p-6 space-y-4">
               <h4 className="text-xs font-bold text-gray-400 uppercase tracking-widest mb-2">Time Allocation</h4>
               <div className="flex justify-between items-center text-sm">
                 <span className="text-gray-600 font-medium">Inside Office</span>
                 <span className="font-bold text-green-600">{formatMinutes(todayAttendance?.insideTime)}</span>
               </div>
               <div className="flex justify-between items-center text-sm">
                 <span className="text-gray-600 font-medium">Outside</span>
                 <span className="font-bold text-orange-600">{formatMinutes(todayAttendance?.outsideTime)}</span>
               </div>
               <div className="flex justify-between items-center text-sm">
                 <span className="text-gray-600 font-medium">Offline/Idle</span>
                 <span className="font-bold text-gray-400">{formatMinutes(todayAttendance?.offlineTime)}</span>
               </div>
               <div className="flex justify-between items-center text-sm">
                 <span className="text-gray-600 font-medium">Extra Hours</span>
                 <span className="font-bold text-indigo-600">{formatMinutes(todayAttendance?.extraHours)}</span>
               </div>
            </div>
          </div>

          <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
             <div className="px-6 py-4 border-b border-gray-100 flex items-center">
               <FaMapMarkedAlt className="text-indigo-600 mr-2" />
               <h3 className="font-semibold text-gray-900">Live Tracker</h3>
             </div>
             <div className="h-64 w-full bg-gray-100 relative">
               {currentLoc ? (
                  <MapContainer center={[currentLoc.lat, currentLoc.lng]} zoom={15} style={{ height: '100%', width: '100%' }}>
                     <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
                     <ChangeView center={[currentLoc.lat, currentLoc.lng]} zoom={16} />
                     <Marker position={[import.meta.env.VITE_OFFICE_LAT || 33.7178, import.meta.env.VITE_OFFICE_LNG || 73.0726]} icon={blueIcon}>
                        <Popup><b>Office Base</b></Popup>
                     </Marker>
                     <Marker position={[currentLoc.lat, currentLoc.lng]} icon={greenIcon}>
                        <Popup><b>You are here</b><br/>{format(new Date(currentLoc.timestamp), 'hh:mm:ss a')}</Popup>
                     </Marker>
                  </MapContainer>
               ) : (
                 <div className="flex h-full items-center justify-center text-gray-400 text-sm p-4 text-center">
                    Awaiting GPS signal... Ensure you are checked in.
                 </div>
               )}
             </div>
          </div>
        </div>

        {/* History Table */}
        <div className="lg:col-span-2 bg-white rounded-xl shadow-sm border border-gray-200 flex flex-col h-full">
          <div className="px-6 py-5 border-b border-gray-100 flex items-center justify-between bg-gray-50">
            <div className="flex items-center">
              <FaHistory className="text-indigo-600 mr-2" />
              <h3 className="font-semibold text-gray-900">Attendance Log</h3>
            </div>
            <input 
              type="month" 
              value={filterMonth}
              onChange={(e) => setFilterMonth(e.target.value)}
              className="border border-gray-300 rounded-md shadow-sm p-1.5 text-sm focus:ring-indigo-500 focus:border-indigo-500" 
            />
          </div>

          <div className="overflow-x-auto">
             <table className="w-full text-left border-collapse">
               <thead>
                 <tr className="bg-gray-50 border-b border-gray-100 text-xs text-gray-500 uppercase tracking-wider">
                    <th className="px-4 py-3 font-bold">Date</th>
                    <th className="px-4 py-3 font-bold">In</th>
                    <th className="px-4 py-3 font-bold">Out</th>
                    <th className="px-4 py-3 font-bold">Inside</th>
                    <th className="px-4 py-3 font-bold">Outside</th>
                    <th className="px-4 py-3 font-bold">Offline</th>
                    <th className="px-4 py-3 font-bold">Extra</th>
                    <th className="px-4 py-3 font-bold">Status</th>
                 </tr>
               </thead>
               <tbody className="divide-y divide-gray-100 text-sm text-gray-700">
                 {filteredHistory.length > 0 ? filteredHistory.map(record => (
                   <tr key={record.id} className="hover:bg-gray-50 transition-colors">
                     <td className="px-4 py-3 font-medium">{format(new Date(record.date), 'MMM do')}</td>
                     <td className="px-4 py-3">{record.checkInTime ? format(new Date(record.checkInTime), 'hh:mm a') : '-'}</td>
                     <td className="px-4 py-3">{record.checkOutTime ? format(new Date(record.checkOutTime), 'hh:mm a') : '-'}</td>
                     <td className="px-4 py-3 text-green-600 font-medium">{formatMinutes(record.insideTime)}</td>
                     <td className="px-4 py-3 text-orange-600">{formatMinutes(record.outsideTime)}</td>
                     <td className="px-4 py-3 text-gray-400">{formatMinutes(record.offlineTime)}</td>
                     <td className="px-4 py-3 text-indigo-600 font-medium">{formatMinutes(record.extraHours)}</td>
                     <td className="px-4 py-3">
                       <span className={`px-2 py-1 rounded text-[10px] font-bold uppercase ${
                         record.status === 'present' ? 'bg-green-100 text-green-700' :
                         record.status === 'late' ? 'bg-yellow-100 text-yellow-700' :
                         'bg-orange-100 text-orange-700'
                       }`}>
                         {record.status}
                       </span>
                     </td>
                   </tr>
                 )) : (
                   <tr>
                     <td colSpan="8" className="px-4 py-8 text-center text-gray-500">No records found.</td>
                   </tr>
                 )}
               </tbody>
             </table>
          </div>
        </div>

      </div>
    </div>
  );
}
