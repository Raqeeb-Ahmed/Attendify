import { useState, useEffect } from 'react';
import { useAuth } from '../hooks/useAuth';
import { db } from '../firebase/config';
import { collection, query, where, getDocs, orderBy } from 'firebase/firestore';
import {
  format,
  startOfMonth,
  endOfMonth,
  eachDayOfInterval,
  isSameDay,
  addMonths,
  subMonths,
  startOfWeek,
  endOfWeek,
  parseISO,
  isFuture,
  isToday
} from 'date-fns';
import { FaChevronLeft, FaChevronRight, FaCalendarAlt, FaMapMarkerAlt, FaClock, FaCheckCircle, FaTimesCircle, FaExclamationCircle } from 'react-icons/fa';
import { MapContainer, TileLayer, Marker, Popup, Polyline } from 'react-leaflet';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

delete L.Icon.Default.prototype._getIconUrl;

const greenIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-green.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});
const redIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-red.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});
const blueIcon = new L.Icon({
  iconUrl: 'https://raw.githubusercontent.com/pointhi/leaflet-color-markers/master/img/marker-icon-2x-blue.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/0.7.7/images/marker-shadow.png',
  iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34]
});

const OFFICE_LAT = parseFloat(import.meta.env.VITE_OFFICE_LAT) || 33.7178;
const OFFICE_LNG = parseFloat(import.meta.env.VITE_OFFICE_LNG) || 73.0726;

export default function PastAttendance() {
  const { user } = useAuth();
  const [currentMonth, setCurrentMonth] = useState(new Date());
  const [attendanceRecords, setAttendanceRecords] = useState([]);
  const [selectedDay, setSelectedDay] = useState(new Date());
  const [dayLocations, setDayLocations] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function fetchMonthData() {
      if (!user) return;
      setLoading(true);
      try {
        const start = format(startOfMonth(currentMonth), 'yyyy-MM-dd');
        const end = format(endOfMonth(currentMonth), 'yyyy-MM-dd');
        const q = query(
          collection(db, 'attendance'),
          where('userId', '==', user.uid),
          where('date', '>=', start),
          where('date', '<=', end)
        );
        const snap = await getDocs(q);
        setAttendanceRecords(snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
      } catch (err) {
        console.error("Error fetching month attendance:", err);
      } finally {
        setLoading(false);
      }
    }
    fetchMonthData();
  }, [currentMonth, user]);

  useEffect(() => {
    async function fetchDayLocations() {
      if (!user || !selectedDay) return;
      try {
        const dayStr = format(selectedDay, 'yyyy-MM-dd');
        const start = `${dayStr}T00:00:00.000Z`;
        const end = `${dayStr}T23:59:59.999Z`;
        const q = query(
          collection(db, 'locations'),
          where('userId', '==', user.uid),
          where('timestamp', '>=', start),
          where('timestamp', '<=', end),
          orderBy('timestamp', 'asc')
        );
        const snap = await getDocs(q);
        setDayLocations(snap.docs.map(doc => ({ id: doc.id, ...doc.data() })));
      } catch (err) {
        console.error("Error fetching day locations:", err);
      }
    }
    fetchDayLocations();
  }, [selectedDay, user]);

  const days = eachDayOfInterval({
    start: startOfWeek(startOfMonth(currentMonth)),
    end: endOfWeek(endOfMonth(currentMonth)),
  });

  const getDayRecord = (day) => attendanceRecords.find(r => r.date === format(day, 'yyyy-MM-dd'));

  const selectedRecord = getDayRecord(selectedDay);

  // Monthly summary
  const totalPresent = attendanceRecords.filter(r => r.status === 'present').length;
  const totalLate = attendanceRecords.filter(r => r.status === 'late').length;
  const totalOutside = attendanceRecords.filter(r => r.status === 'outside').length;
  const totalRecords = attendanceRecords.length;

  // Build trail polyline from locations
  const trailPositions = dayLocations.map(l => [l.lat, l.lng]);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between flex-wrap gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Past Attendance</h1>
          <p className="text-sm text-gray-500">View your attendance history, location trail & monthly statistics.</p>
        </div>
        <div className="flex bg-white rounded-lg shadow-sm border border-gray-200">
          <button onClick={() => setCurrentMonth(subMonths(currentMonth, 1))} className="p-2.5 hover:bg-gray-50 text-gray-600 transition-colors rounded-l-lg">
            <FaChevronLeft />
          </button>
          <div className="px-5 py-2.5 text-sm font-semibold text-gray-700 min-w-[160px] text-center border-x border-gray-100">
            {format(currentMonth, 'MMMM yyyy')}
          </div>
          <button onClick={() => setCurrentMonth(addMonths(currentMonth, 1))} className="p-2.5 hover:bg-gray-50 text-gray-600 transition-colors rounded-r-lg">
            <FaChevronRight />
          </button>
        </div>
      </div>

      {/* Monthly Summary Strip */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <div className="bg-white rounded-xl border border-gray-200 p-4 shadow-sm">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-green-50 text-green-600"><FaCheckCircle /></div>
            <div>
              <p className="text-[10px] font-bold text-gray-400 uppercase">Present</p>
              <p className="text-xl font-bold text-green-600">{totalPresent}</p>
            </div>
          </div>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4 shadow-sm">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-yellow-50 text-yellow-600"><FaExclamationCircle /></div>
            <div>
              <p className="text-[10px] font-bold text-gray-400 uppercase">Late</p>
              <p className="text-xl font-bold text-yellow-600">{totalLate}</p>
            </div>
          </div>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4 shadow-sm">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-orange-50 text-orange-600"><FaTimesCircle /></div>
            <div>
              <p className="text-[10px] font-bold text-gray-400 uppercase">Outside</p>
              <p className="text-xl font-bold text-orange-600">{totalOutside}</p>
            </div>
          </div>
        </div>
        <div className="bg-white rounded-xl border border-gray-200 p-4 shadow-sm">
          <div className="flex items-center gap-2">
            <div className="p-2 rounded-lg bg-indigo-50 text-indigo-600"><FaCalendarAlt /></div>
            <div>
              <p className="text-[10px] font-bold text-gray-400 uppercase">Rate</p>
              <p className="text-xl font-bold text-indigo-600">{totalRecords > 0 ? Math.round(((totalPresent + totalLate) / totalRecords) * 100) : 0}%</p>
            </div>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Calendar */}
        <div className="lg:col-span-1 bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
          <div className="p-4 bg-gradient-to-r from-indigo-50 to-blue-50 border-b border-gray-200 flex items-center">
            <FaCalendarAlt className="text-indigo-600 mr-2" />
            <span className="font-semibold text-gray-900">Attendance Calendar</span>
          </div>
          <div className="p-4">
            {/* Day headers */}
            <div className="grid grid-cols-7 gap-1 mb-2">
              {['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(d => (
                <div key={d} className="text-center text-[10px] font-bold text-gray-400 uppercase py-1">{d}</div>
              ))}
            </div>
            {/* Calendar grid */}
            <div className="grid grid-cols-7 gap-1.5">
              {days.map((day, idx) => {
                const record = getDayRecord(day);
                const status = record?.status || null;
                const isSelected = isSameDay(day, selectedDay);
                const isCurrentMonth = day.getMonth() === currentMonth.getMonth();
                const isTodayDate = isToday(day);
                const isFutureDate = isFuture(day);

                let cellBg = '';
                let cellText = isCurrentMonth ? 'text-gray-700' : 'text-gray-300';
                let statusLabel = '';

                if (isCurrentMonth && !isFutureDate && status) {
                  if (status === 'present') {
                    cellBg = 'bg-green-100 border-green-300';
                    cellText = 'text-green-800';
                    statusLabel = 'P';
                  } else if (status === 'late') {
                    cellBg = 'bg-yellow-100 border-yellow-300';
                    cellText = 'text-yellow-800';
                    statusLabel = 'L';
                  } else if (status === 'outside') {
                    cellBg = 'bg-orange-100 border-orange-300';
                    cellText = 'text-orange-800';
                    statusLabel = 'O';
                  }
                }

                return (
                  <button
                    key={idx}
                    onClick={() => setSelectedDay(day)}
                    disabled={isFutureDate}
                    className={`
                      relative h-14 flex flex-col items-center justify-center rounded-lg transition-all border
                      ${isSelected ? 'ring-2 ring-indigo-500 ring-offset-1 shadow-md' : ''}
                      ${cellBg || 'bg-white border-transparent'}
                      ${isTodayDate && !isSelected ? 'border-indigo-400 border-2' : ''}
                      ${isFutureDate ? 'opacity-30 cursor-not-allowed' : 'hover:shadow-sm cursor-pointer'}
                    `}
                  >
                    <span className={`text-sm font-semibold ${cellText}`}>
                      {format(day, 'd')}
                    </span>
                    {statusLabel && (
                      <span className={`text-[9px] font-bold mt-0.5 ${cellText}`}>{statusLabel}</span>
                    )}
                  </button>
                );
              })}
            </div>
          </div>
          {/* Legend */}
          <div className="p-3 border-t border-gray-100 bg-gray-50 grid grid-cols-3 gap-2">
            <div className="flex items-center text-[10px] text-gray-600 gap-1.5">
              <span className="w-4 h-4 rounded bg-green-100 border border-green-300 flex items-center justify-center text-green-800 font-bold text-[8px]">P</span>
              <span>Before 9:45</span>
            </div>
            <div className="flex items-center text-[10px] text-gray-600 gap-1.5">
              <span className="w-4 h-4 rounded bg-yellow-100 border border-yellow-300 flex items-center justify-center text-yellow-800 font-bold text-[8px]">L</span>
              <span>After 9:45</span>
            </div>
            <div className="flex items-center text-[10px] text-gray-600 gap-1.5">
              <span className="w-4 h-4 rounded bg-orange-100 border border-orange-300 flex items-center justify-center text-orange-800 font-bold text-[8px]">O</span>
              <span>Outside</span>
            </div>
          </div>
        </div>

        {/* Right Panel — Details & Map */}
        <div className="lg:col-span-2 space-y-6">
          {/* Day Detail Card */}
          <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
            <div className="px-6 py-4 border-b border-gray-200 bg-gradient-to-r from-indigo-50 to-blue-50 flex items-center justify-between">
              <div className="flex items-center">
                <FaClock className="text-indigo-600 mr-2" />
                <h3 className="font-semibold text-gray-900">{format(selectedDay, 'EEEE, MMMM do, yyyy')}</h3>
              </div>
              {selectedRecord && (
                <span className={`px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider ${
                  selectedRecord.status === 'present' ? 'bg-green-100 text-green-700 border border-green-200' :
                  selectedRecord.status === 'late' ? 'bg-yellow-100 text-yellow-700 border border-yellow-200' :
                  'bg-orange-100 text-orange-700 border border-orange-200'
                }`}>
                  {selectedRecord.status === 'outside' ? 'OUT OF SYSTEM' : selectedRecord.status.toUpperCase()}
                </span>
              )}
            </div>

            <div className="p-6">
              {selectedRecord ? (
                <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
                  <div className="bg-indigo-50 p-4 rounded-lg border border-indigo-100">
                    <p className="text-[10px] text-indigo-500 font-bold uppercase mb-1">Check-in Time</p>
                    <p className="text-lg font-bold text-gray-900">{format(parseISO(selectedRecord.checkInTime), 'hh:mm:ss a')}</p>
                  </div>
                  <div className="bg-blue-50 p-4 rounded-lg border border-blue-100">
                    <p className="text-[10px] text-blue-500 font-bold uppercase mb-1">IP Address</p>
                    <p className="text-lg font-bold text-gray-900 font-mono">{selectedRecord.ipAddress || 'N/A'}</p>
                  </div>
                  <div className="bg-purple-50 p-4 rounded-lg border border-purple-100">
                    <p className="text-[10px] text-purple-500 font-bold uppercase mb-1">GPS Coordinates</p>
                    <p className="text-lg font-bold text-gray-900 font-mono text-sm">
                      {selectedRecord.location ? `${selectedRecord.location.lat?.toFixed(4)}, ${selectedRecord.location.lng?.toFixed(4)}` : 'N/A'}
                    </p>
                  </div>
                </div>
              ) : (
                <div className="text-center py-8 text-gray-500 italic bg-gray-50 rounded-lg mb-6 border border-dashed border-gray-300">
                  <FaCalendarAlt className="mx-auto text-3xl mb-2 text-gray-300" />
                  <p>No attendance record found for this date.</p>
                </div>
              )}

              {/* Map with trail */}
              <div className="space-y-3">
                <div className="flex items-center justify-between">
                  <div className="flex items-center">
                    <FaMapMarkerAlt className="text-indigo-600 mr-2" />
                    <h4 className="font-semibold text-gray-900 text-sm">Location Trail</h4>
                  </div>
                  <span className="text-xs text-gray-500 bg-gray-100 px-2 py-1 rounded-full">{dayLocations.length} GPS points</span>
                </div>

                <div className="h-80 w-full rounded-xl overflow-hidden border border-gray-200 bg-gray-100 relative z-0">
                  {dayLocations.length > 0 ? (
                    <MapContainer center={[dayLocations[0].lat, dayLocations[0].lng]} zoom={15} style={{ height: '100%', width: '100%' }}>
                      <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />

                      {/* Office marker */}
                      <Marker position={[OFFICE_LAT, OFFICE_LNG]} icon={blueIcon}>
                        <Popup><b>Office</b></Popup>
                      </Marker>

                      {/* Movement trail */}
                      {trailPositions.length > 1 && (
                        <Polyline positions={trailPositions} pathOptions={{ color: '#6366F1', weight: 3, opacity: 0.6, dashArray: '8' }} />
                      )}

                      {/* Start point */}
                      <Marker position={[dayLocations[0].lat, dayLocations[0].lng]} icon={greenIcon}>
                        <Popup>
                          <div className="text-xs">
                            <p className="font-bold text-green-700">📍 Start</p>
                            <p>Time: {format(parseISO(dayLocations[0].timestamp), 'hh:mm a')}</p>
                            <p className="font-mono text-[10px]">{dayLocations[0].lat.toFixed(5)}, {dayLocations[0].lng.toFixed(5)}</p>
                          </div>
                        </Popup>
                      </Marker>

                      {/* End point */}
                      {dayLocations.length > 1 && (
                        <Marker position={[dayLocations[dayLocations.length - 1].lat, dayLocations[dayLocations.length - 1].lng]} icon={redIcon}>
                          <Popup>
                            <div className="text-xs">
                              <p className="font-bold text-red-700">🏁 Last Known</p>
                              <p>Time: {format(parseISO(dayLocations[dayLocations.length - 1].timestamp), 'hh:mm a')}</p>
                              <p className="font-mono text-[10px]">{dayLocations[dayLocations.length - 1].lat.toFixed(5)}, {dayLocations[dayLocations.length - 1].lng.toFixed(5)}</p>
                            </div>
                          </Popup>
                        </Marker>
                      )}
                    </MapContainer>
                  ) : (
                    <div className="h-full flex flex-col items-center justify-center text-gray-400 p-8 text-center">
                      <FaMapMarkerAlt className="text-4xl mb-2 opacity-20" />
                      <p className="text-sm">No location data captured for this day.</p>
                      <p className="text-xs mt-1">Locations are tracked automatically when the device is active.</p>
                    </div>
                  )}
                </div>

                {/* Location timeline */}
                {dayLocations.length > 0 && (
                  <div className="bg-gray-50 rounded-lg p-4 border border-gray-200 max-h-48 overflow-y-auto">
                    <p className="text-xs font-bold text-gray-500 uppercase mb-2">GPS Timeline</p>
                    <div className="space-y-1.5">
                      {dayLocations.map((loc, idx) => (
                        <div key={loc.id || idx} className="flex items-center gap-3 text-xs">
                          <span className="text-gray-400 font-mono w-16">{format(parseISO(loc.timestamp), 'hh:mm a')}</span>
                          <span className={`w-2 h-2 rounded-full ${loc.insideRadius ? 'bg-green-500' : 'bg-orange-500'}`}></span>
                          <span className="text-gray-600 font-mono">{loc.lat.toFixed(5)}, {loc.lng.toFixed(5)}</span>
                          <span className={`text-[10px] font-medium ${loc.insideRadius ? 'text-green-600' : 'text-orange-600'}`}>
                            {loc.insideRadius ? 'In Office' : 'Outside'}
                          </span>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
