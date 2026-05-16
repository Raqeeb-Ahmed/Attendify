import { useEffect, useState, useMemo } from 'react';
import { db } from '../firebase/config';
import { collection, query, getDocs, where, onSnapshot } from 'firebase/firestore';
import { format, parseISO, differenceInMinutes } from 'date-fns';
import {
  FaUsers, FaUserCheck, FaUserTimes, FaMapMarkedAlt, FaBolt,
  FaFileExport, FaChevronDown, FaChevronUp, FaClock, FaMapPin,
  FaWifi, FaCircle, FaSearch, FaChartBar, FaExclamationTriangle,
  FaSignOutAlt
} from 'react-icons/fa';
import { MapContainer, TileLayer, Marker, Popup, useMap, Circle } from 'react-leaflet';
import { getDistanceFromLatLonInM } from '../services/attendance';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

delete L.Icon.Default.prototype._getIconUrl;

const redIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});
const greenIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});
const officeIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});
const yellowIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-gold.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});
const grayIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-grey.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});

function ChangeView({ center, zoom }) {
  const map = useMap();
  map.setView(center, zoom);
  return null;
}

const STALE_THRESHOLD_MINUTES = 5; // consider offline after this many minutes

export default function AdminDashboard() {
  const [employees, setEmployees] = useState([]);
  const [attendance, setAttendance] = useState([]);
  const [locations, setLocations] = useState([]);
  const [heartbeats, setHeartbeats] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filterDate, setFilterDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [selectedUserLoc, setSelectedUserLoc] = useState(null);
  const [expandedEmployee, setExpandedEmployee] = useState(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [filterStatus, setFilterStatus] = useState('all');
  const [isLive, setIsLive] = useState(true);
  const [activeTab, setActiveTab] = useState('team'); // 'team' | 'analytics'

  const OFFICE_LAT = parseFloat(import.meta.env.VITE_OFFICE_LAT) || 33.7178;
  const OFFICE_LNG = parseFloat(import.meta.env.VITE_OFFICE_LNG) || 73.0726;
  const RADIUS_METERS = 100;

  useEffect(() => {
    let unsubAttendance = () => {};
    let unsubLocations = () => {};
    let unsubHeartbeats = () => {};

    async function fetchData() {
      setLoading(true);
      try {
        const usersSnap = await getDocs(collection(db, 'users'));
        const usersData = usersSnap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
        setEmployees(usersData.filter(u => u.role === 'employee'));

        // Real-time Attendance
        const attQuery = query(collection(db, 'attendance'), where('date', '==', filterDate));
        unsubAttendance = onSnapshot(attQuery, (snap) => {
          setAttendance(snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
        });

        // Real-time Locations — latest per user for filterDate
        const locQuery = query(collection(db, 'locations'));
        unsubLocations = onSnapshot(locQuery, (snap) => {
          const locData = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
          const latestLocs = {};
          locData.forEach(loc => {
            const locDate = loc.timestamp?.substring(0, 10) || '';
            if (locDate === filterDate) {
              if (!latestLocs[loc.userId] || new Date(loc.timestamp) > new Date(latestLocs[loc.userId].timestamp)) {
                latestLocs[loc.userId] = loc;
              }
            }
          });
          setLocations(Object.values(latestLocs));
        });

        // Real-time Heartbeats
        unsubHeartbeats = onSnapshot(collection(db, 'heartbeats'), (snap) => {
          setHeartbeats(snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
        });
      } catch (error) {
        console.error("Error fetching admin data:", error);
      }
      setLoading(false);
    }
    fetchData();
    return () => { unsubAttendance(); unsubLocations(); unsubHeartbeats(); };
  }, [filterDate]);

  // ── Derived Data ──────────────────────────────────────────────────
  const getHeartbeat = (userId) => heartbeats.find(h => h.userId === userId);

  const isOnline = (userId) => {
    const hb = getHeartbeat(userId);
    if (!hb || !hb.lastSeen) return false;
    const diff = differenceInMinutes(new Date(), parseISO(hb.lastSeen));
    return diff <= STALE_THRESHOLD_MINUTES;
  };

  const isInsideOffice = (userId) => {
    const loc = locations.find(l => l.userId === userId);
    if (!loc) return false;
    return loc.insideRadius === true;
  };

  const totalEmployees = employees.length;
  const presentCount = attendance.filter(a => a.status === 'present').length;
  const lateCount = attendance.filter(a => a.status === 'late').length;
  const outsideCount = attendance.filter(a => a.status === 'outside').length;
  const pendingCount = totalEmployees - attendance.length;
  const onlineCount = employees.filter(e => isOnline(e.id)).length;
  const offlineCount = totalEmployees - onlineCount;
  const insideCount = employees.filter(e => isInsideOffice(e.id)).length;
  // Out of System: online (heartbeat active) + outside office radius + not on office WiFi
  const outOfSystemCount = employees.filter(e => {
    const online = isOnline(e.id);
    const inside = isInsideOffice(e.id);
    return online && !inside;
  }).length;

  // Filters
  const filteredEmployees = useMemo(() => {
    return employees.filter(emp => {
      const matchesSearch = (emp.name || '').toLowerCase().includes(searchTerm.toLowerCase()) ||
                            (emp.email || '').toLowerCase().includes(searchTerm.toLowerCase());
      if (filterStatus === 'all') return matchesSearch;
      if (filterStatus === 'online') return matchesSearch && isOnline(emp.id);
      if (filterStatus === 'offline') return matchesSearch && !isOnline(emp.id);
      if (filterStatus === 'in-office') return matchesSearch && isInsideOffice(emp.id);
      if (filterStatus === 'out-of-system') return matchesSearch && isOnline(emp.id) && !isInsideOffice(emp.id);
      const record = attendance.find(a => a.userId === emp.id);
      const status = record?.status || 'pending';
      return matchesSearch && status === filterStatus;
    });
  }, [employees, searchTerm, filterStatus, attendance, heartbeats, locations]);

  const handleLocateWorker = (userId) => {
    const loc = locations.find(l => l.userId === userId);
    if (loc) setSelectedUserLoc([loc.lat, loc.lng]);
    else alert("No location data found for this employee.");
  };

  const exportCSV = () => {
    let csvContent = "data:text/csv;charset=utf-8,Name,Email,Status,Online,In Office,Check-In Time,IP Address,Lat,Lng\n";
    employees.forEach(emp => {
      const record = attendance.find(a => a.userId === emp.id);
      const loc = locations.find(l => l.userId === emp.id);
      const name = emp.name?.replace(/,/g, '') || '';
      const email = emp.email || '';
      const status = record?.status || 'Pending';
      const online = isOnline(emp.id) ? 'Yes' : 'No';
      const inOffice = isInsideOffice(emp.id) ? 'Yes' : 'No';
      const checkInTime = record?.checkInTime ? format(parseISO(record.checkInTime), 'yyyy-MM-dd HH:mm:ss') : 'N/A';
      const ipAddress = record?.ipAddress || 'N/A';
      const lat = loc?.lat?.toFixed(5) || 'N/A';
      const lng = loc?.lng?.toFixed(5) || 'N/A';
      csvContent += `"${name}","${email}","${status}","${online}","${inOffice}","${checkInTime}","${ipAddress}","${lat}","${lng}"\n`;
    });
    const link = document.createElement("a");
    link.setAttribute("href", encodeURI(csvContent));
    link.setAttribute("download", `attendance_export_${filterDate}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  if (loading) return (
    <div className="p-8 text-center">
      <div className="inline-flex items-center gap-2 text-indigo-600"><FaBolt className="animate-spin" /> Syncing Live Network...</div>
    </div>
  );

  // ── Workforce health bar ──
  const inOfficePct = totalEmployees > 0 ? Math.round(((presentCount + lateCount) / totalEmployees) * 100) : 0;
  const outsidePct = totalEmployees > 0 ? Math.round((outsideCount / totalEmployees) * 100) : 0;
  const pendingPct = totalEmployees > 0 ? Math.round((pendingCount / totalEmployees) * 100) : 0;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-2">
        <div>
          <h1 className="text-3xl font-bold text-gray-900 flex items-center">
            Admin Dashboard
            {isLive && <span className="ml-3 px-3 py-1 text-xs font-semibold rounded-full bg-green-100 text-green-700 border border-green-300 animate-pulse flex items-center"><FaBolt className="mr-1.5" /> LIVE</span>}
          </h1>
          <p className="text-sm text-gray-600 mt-2">Real-time workforce monitoring & location tracking</p>
        </div>
        <div className="mt-4 sm:mt-0 flex gap-2 flex-wrap">
          <button onClick={exportCSV} className="flex items-center px-4 py-2.5 border border-gray-300 shadow-sm text-sm font-medium rounded-lg text-gray-700 bg-white hover:bg-gray-50 transition-colors">
            <FaFileExport className="mr-2 text-green-600" /> Export CSV
          </button>
          <input
            type="date"
            value={filterDate}
            onChange={(e) => {
              setFilterDate(e.target.value);
              setIsLive(e.target.value === format(new Date(), 'yyyy-MM-dd'));
            }}
            className="border border-gray-300 rounded-lg shadow-sm px-3 py-2 text-sm focus:ring-2 focus:ring-indigo-500 focus:border-transparent bg-white"
          />
        </div>
      </div>

      {/* Stats Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-3">
        {[
          { label: 'Total Staff', val: totalEmployees, color: 'indigo', icon: <FaUsers /> },
          { label: 'Present', val: presentCount, color: 'green', icon: <FaUserCheck /> },
          { label: 'Late', val: lateCount, color: 'yellow', icon: <FaClock /> },
          { label: 'Out of System', val: outOfSystemCount, color: 'orange', icon: <FaSignOutAlt /> },
          { label: 'Offline', val: offlineCount, color: 'gray', icon: <FaUserTimes /> },
          { label: 'Online', val: onlineCount, color: 'emerald', icon: <FaWifi /> },
          { label: 'In Office', val: insideCount, color: 'blue', icon: <FaMapPin /> },
        ].map(s => (
          <div key={s.label} className={`bg-white rounded-xl shadow-sm border border-${s.color}-100 p-4 hover:shadow-md transition-shadow`}>
            <div className="flex items-center">
              <div className={`p-2.5 rounded-lg bg-${s.color}-50 text-${s.color}-600 text-sm`}>{s.icon}</div>
              <div className="ml-3">
                <p className="text-[10px] font-bold text-gray-400 uppercase tracking-wider">{s.label}</p>
                <p className={`text-xl font-bold text-${s.color}-600`}>{s.val}</p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Workforce Health Bar */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-200 p-5">
        <div className="flex items-center justify-between mb-3">
          <div className="flex items-center gap-2">
            <FaChartBar className="text-indigo-600" />
            <h3 className="text-sm font-semibold text-gray-900">Workforce Health</h3>
          </div>
          <div className="flex gap-4 text-xs">
            <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-green-500"></span> In Office {inOfficePct}%</span>
            <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-orange-500"></span> Outside {outsidePct}%</span>
            <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-gray-300"></span> Pending {pendingPct}%</span>
          </div>
        </div>
        <div className="w-full bg-gray-200 rounded-full h-4 overflow-hidden flex">
          <div className="bg-green-500 h-4 transition-all duration-500" style={{ width: `${inOfficePct}%` }}></div>
          <div className="bg-orange-500 h-4 transition-all duration-500" style={{ width: `${outsidePct}%` }}></div>
          <div className="bg-gray-300 h-4 transition-all duration-500" style={{ width: `${pendingPct}%` }}></div>
        </div>
        {outOfSystemCount > 0 && (
          <div className="mt-3 px-3 py-2 bg-orange-50 rounded-lg border border-orange-200 flex items-center gap-2 text-xs text-orange-700">
            <FaExclamationTriangle /> {outOfSystemCount} employee(s) are active online but outside the office system.
          </div>
        )}
      </div>

      {/* Tab Bar */}
      <div className="flex gap-1 bg-gray-100 rounded-lg p-1 w-fit">
        {['team', 'analytics'].map(tab => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className={`px-4 py-2 text-sm font-medium rounded-md transition-all ${activeTab === tab ? 'bg-white shadow-sm text-indigo-700' : 'text-gray-600 hover:text-gray-900'}`}
          >
            {tab === 'team' ? 'Team Directory' : 'Live Analytics'}
          </button>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left Panel */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden flex flex-col lg:col-span-1">
          <div className="px-5 py-4 border-b border-gray-200 bg-gradient-to-r from-indigo-50 to-blue-50">
            <div className="flex items-center gap-2 mb-3">
              <FaSearch className="text-gray-400" />
              <input
                type="text"
                placeholder="Search employees..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
              />
            </div>
            <div className="flex gap-1.5 flex-wrap">
              {['all', 'present', 'late', 'outside', 'pending', 'online', 'offline', 'in-office', 'out-of-system'].map(st => (
                <button
                  key={st}
                  onClick={() => setFilterStatus(st)}
                  className={`px-2 py-1 text-[10px] font-medium rounded-full transition-all ${filterStatus === st
                    ? 'bg-indigo-600 text-white'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                >
                  {st === 'out-of-system' ? 'Out of System' : st.charAt(0).toUpperCase() + st.slice(1).replace('-', ' ')}
                </button>
              ))}
            </div>
          </div>
          <div className="flex-1 overflow-y-auto" style={{ maxHeight: '700px' }}>
            <ul className="divide-y divide-gray-100">
              {filteredEmployees.map(emp => {
                const record = attendance.find(a => a.userId === emp.id);
                const status = record?.status || 'pending';
                const empLoc = locations.find(l => l.userId === emp.id);
                const online = isOnline(emp.id);
                const inOffice = isInsideOffice(emp.id);
                const isExpanded = expandedEmployee === emp.id;
                const hb = getHeartbeat(emp.id);
                const lastSeenText = hb?.lastSeen ? format(parseISO(hb.lastSeen), 'hh:mm a') : 'Never';

                return (
                  <li key={emp.id} className={`border-l-4 transition-all ${online ? 'border-green-400' : 'border-transparent'} hover:bg-indigo-50`}>
                    <div className="p-4">
                      <div className="flex items-center justify-between cursor-pointer" onClick={() => setExpandedEmployee(isExpanded ? null : emp.id)}>
                        <div className="flex items-center flex-1 min-w-0">
                          <div className="relative flex-shrink-0">
                            <img className="h-10 w-10 rounded-full object-cover border-2 border-gray-200" src={emp.photoURL || `https://ui-avatars.com/api/?name=${emp.name}`} alt="" />
                            <span className={`absolute bottom-0 right-0 block h-3 w-3 rounded-full ring-2 ring-white ${online ? 'bg-green-500' : 'bg-gray-400'}`}></span>
                          </div>
                          <div className="ml-3 flex-1 min-w-0">
                            <p className="text-sm font-semibold text-gray-900 truncate">{emp.name}</p>
                            <p className="text-xs text-gray-500 truncate">{emp.email}</p>
                          </div>
                        </div>
                        <div className="flex items-center gap-1.5 ml-2">
                          {inOffice && (
                            <span className="px-1.5 py-0.5 rounded text-[9px] font-bold bg-blue-100 text-blue-700 border border-blue-200">IN</span>
                          )}
                          <span className={`px-2 py-0.5 rounded text-[10px] font-medium ${status === 'present' ? 'bg-green-100 text-green-800' :
                            status === 'late' ? 'bg-yellow-100 text-yellow-800' :
                            status === 'outside' ? 'bg-orange-100 text-orange-800' :
                            'bg-gray-100 text-gray-600'
                            }`}>
                            {status === 'outside' ? 'Out of System' : status.charAt(0).toUpperCase() + status.slice(1)}
                          </span>
                          {isExpanded ? <FaChevronUp className="text-gray-400 text-xs" /> : <FaChevronDown className="text-gray-400 text-xs" />}
                        </div>
                      </div>

                      {isExpanded && (
                        <div className="mt-4 p-5 bg-white rounded-xl shadow-sm border border-gray-100">
                          <h4 className="text-lg font-bold text-gray-900 mb-4">Today's Summary</h4>
                          
                          <div className="grid grid-cols-2 gap-4 mb-4">
                            <div>
                              <p className="text-[10px] font-bold text-gray-500 uppercase tracking-wider mb-1">Check In</p>
                              <p className="text-base font-bold text-gray-900">{record?.checkInTime ? format(parseISO(record.checkInTime), 'hh:mm a') : '--:--'}</p>
                            </div>
                            <div>
                              <p className="text-[10px] font-bold text-gray-500 uppercase tracking-wider mb-1">Check Out</p>
                              <p className="text-base font-bold text-gray-900">{record?.checkOutTime ? format(parseISO(record.checkOutTime), 'hh:mm a') : '--:--'}</p>
                            </div>
                          </div>

                          <div className="border-t border-gray-100 py-3 flex items-center justify-between">
                            <span className="text-sm font-semibold text-gray-600">Status</span>
                            <span className={`px-3 py-1 rounded-full text-[10px] font-bold uppercase tracking-wider ${
                              status === 'present' ? 'bg-green-100 text-green-800' :
                              status === 'late' ? 'bg-yellow-100 text-yellow-800' :
                              status === 'outside' ? 'bg-orange-100 text-orange-800' :
                              'bg-gray-100 text-gray-600'
                            }`}>
                              {status === 'outside' ? 'Out of System' : status}
                            </span>
                          </div>

                          <div className="border-t border-gray-100 pt-4 space-y-3">
                            <p className="text-[10px] font-bold text-gray-400 uppercase tracking-widest mb-2">Time Allocation</p>
                            
                            <div className="flex justify-between items-center text-sm">
                              <span className="text-gray-600 font-medium">Inside Office</span>
                              <span className="font-bold text-green-600">{record?.insideTime ? `${Math.floor(record.insideTime / 60)}h ${record.insideTime % 60}m` : '0h 0m'}</span>
                            </div>
                            <div className="flex justify-between items-center text-sm">
                              <span className="text-gray-600 font-medium">Outside</span>
                              <span className="font-bold text-orange-600">{record?.outsideTime ? `${Math.floor(record.outsideTime / 60)}h ${record.outsideTime % 60}m` : '0h 0m'}</span>
                            </div>
                            <div className="flex justify-between items-center text-sm">
                              <span className="text-gray-600 font-medium">Offline/Idle</span>
                              <span className="font-bold text-gray-400">{record?.offlineTime ? `${Math.floor(record.offlineTime / 60)}h ${record.offlineTime % 60}m` : '0h 0m'}</span>
                            </div>
                            <div className="flex justify-between items-center text-sm">
                              <span className="text-gray-600 font-medium">Extra Hours</span>
                              <span className="font-bold text-indigo-600">{record?.extraHours ? `${Math.floor(record.extraHours / 60)}h ${record.extraHours % 60}m` : '0h 0m'}</span>
                            </div>
                          </div>

                          {empLoc && (
                            <div className="mt-4 pt-4 border-t border-gray-100">
                              <div className="flex justify-between items-center mb-3">
                                <span className="text-xs text-gray-500 font-medium">Live GPS:</span>
                                <span className="text-xs text-gray-900 font-mono">{empLoc.lat?.toFixed(5)}, {empLoc.lng?.toFixed(5)}</span>
                              </div>
                              <button
                                onClick={(e) => { e.stopPropagation(); handleLocateWorker(emp.id); }}
                                className="w-full px-3 py-2 text-indigo-600 bg-indigo-50 hover:bg-indigo-100 rounded-lg font-medium transition-colors flex items-center justify-center gap-2 border border-indigo-100 text-sm"
                              >
                                <FaMapPin /> Locate on Map
                              </button>
                            </div>
                          )}
                        </div>
                      )}
                    </div>
                  </li>
                );
              })}
              {filteredEmployees.length === 0 && <div className="p-8 text-center text-gray-500"><p>No employees found</p></div>}
            </ul>
          </div>
        </div>

        {/* Map View */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden flex flex-col lg:col-span-2">
          <div className="px-6 py-4 border-b border-gray-200 bg-gradient-to-r from-indigo-50 to-blue-50 flex items-center justify-between">
            <div className="flex items-center">
              <FaMapMarkedAlt className="text-indigo-600 mr-2 text-lg" />
              <div>
                <h3 className="text-base font-semibold text-gray-900">Live Location Map</h3>
                <p className="text-xs text-gray-500 mt-0.5">{locations.length} tracked · {onlineCount} online · {insideCount} in office radius</p>
              </div>
            </div>
            <div className="flex items-center gap-3 text-xs">
              <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-green-500"></span> Present</span>
              <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-yellow-500"></span> Late</span>
              <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-red-500"></span> Out of System</span>
              <span className="flex items-center gap-1"><span className="w-2.5 h-2.5 rounded-full bg-gray-400"></span> Offline</span>
            </div>
          </div>
          <div className="h-[700px] w-full bg-gray-100 relative z-0">
            <MapContainer center={[OFFICE_LAT, OFFICE_LNG]} zoom={15} style={{ height: '100%', width: '100%' }}>
              <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" attribution='&copy; OpenStreetMap' />

              {/* Office */}
              <Marker position={[OFFICE_LAT, OFFICE_LNG]} icon={officeIcon}>
                <Popup><div className="text-center font-semibold text-gray-900">🏢 Office HQ<br /><span className="text-xs text-gray-500">Radius: {RADIUS_METERS}m</span></div></Popup>
              </Marker>
              <Circle center={[OFFICE_LAT, OFFICE_LNG]} radius={RADIUS_METERS} pathOptions={{ color: '#4F46E5', fillColor: '#C7D2FE', fillOpacity: 0.15, weight: 2, dashArray: '6' }} />

              {selectedUserLoc && <ChangeView center={selectedUserLoc} zoom={17} />}

              {/* Employee Markers */}
              {locations.map(loc => {
                const emp = employees.find(e => e.id === loc.userId);
                const online = isOnline(loc.userId);
                const attStatus = attendance.find(a => a.userId === loc.userId)?.status || 'pending';
                const inOffice = loc.insideRadius === true;
                let markerIcon;
                if (!online) markerIcon = grayIcon;
                else if (attStatus === 'present') markerIcon = greenIcon;
                else if (attStatus === 'late') markerIcon = yellowIcon;
                else if (attStatus === 'outside' || !inOffice) markerIcon = redIcon;
                else markerIcon = greenIcon;

                // Determine display label
                let displayLabel = '';
                if (!online) displayLabel = 'Offline';
                else if (inOffice && attStatus === 'present') displayLabel = 'Present';
                else if (inOffice && attStatus === 'late') displayLabel = 'Late';
                else if (online && !inOffice) displayLabel = 'Out of System';
                else displayLabel = attStatus.charAt(0).toUpperCase() + attStatus.slice(1);

                const dist = getDistanceFromLatLonInM(OFFICE_LAT, OFFICE_LNG, loc.lat, loc.lng);

                return (
                  <Marker key={loc.id} position={[loc.lat, loc.lng]} icon={markerIcon}>
                    <Popup>
                      <div className="min-w-[220px]">
                        <div className="flex items-center gap-2 mb-2">
                          <img src={emp?.photoURL || `https://ui-avatars.com/api/?name=${emp?.name}`} className="w-10 h-10 rounded-full border-2 border-indigo-500 object-cover" alt="" />
                          <div>
                            <div className="font-bold text-gray-900 text-sm">{emp?.name || 'Unknown'}</div>
                            <div className="text-[11px] text-gray-500">{emp?.email || 'N/A'}</div>
                          </div>
                        </div>
                        <div className="space-y-1 text-xs border-t border-gray-200 pt-2">
                          <div className="flex justify-between">
                            <span className="font-medium text-gray-600">Connection:</span>
                            <span className={`font-semibold ${online ? 'text-green-600' : 'text-gray-500'}`}>{online ? '🟢 Active' : '⚪ Offline'}</span>
                          </div>
                          <div className="flex justify-between">
                            <span className="font-medium text-gray-600">Status:</span>
                            <span className={`font-semibold ${displayLabel === 'Present' ? 'text-green-600' : displayLabel === 'Late' ? 'text-yellow-600' : displayLabel === 'Out of System' ? 'text-orange-600' : 'text-gray-500'}`}>
                              {displayLabel}
                            </span>
                          </div>
                          <div className="flex justify-between">
                            <span className="font-medium text-gray-600">Distance:</span>
                            <span className="text-gray-700">{dist < 1000 ? `${Math.round(dist)}m` : `${(dist / 1000).toFixed(1)}km`} from office</span>
                          </div>
                          <div className="flex justify-between">
                            <span className="font-medium text-gray-600">Last Signal:</span>
                            <span className="text-gray-700">{format(parseISO(loc.timestamp), 'hh:mm:ss a')}</span>
                          </div>
                          <div className="flex justify-between text-[11px]">
                            <span className="font-medium text-gray-600">Coordinates:</span>
                            <span className="text-gray-700 font-mono">{loc.lat.toFixed(5)}, {loc.lng.toFixed(5)}</span>
                          </div>
                        </div>
                      </div>
                    </Popup>
                  </Marker>
                );
              })}
            </MapContainer>
          </div>
        </div>
      </div>
    </div>
  );
}
