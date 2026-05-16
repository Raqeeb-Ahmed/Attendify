import { useState, useEffect, useMemo } from 'react';
import { db } from '../../firebase/config';
import { collection, query, where, getDocs, orderBy } from 'firebase/firestore';
import { format, parseISO, startOfMonth, endOfMonth, eachDayOfInterval, isWeekend, differenceInMinutes } from 'date-fns';
import { FaCalendarAlt, FaSearch, FaFileExport, FaClock, FaUserCheck, FaExclamationTriangle, FaTimesCircle, FaCalendarCheck, FaChevronLeft, FaChevronRight, FaFilter } from 'react-icons/fa';

export default function AdminAttendance() {
  const [employees, setEmployees] = useState([]);
  const [allAttendance, setAllAttendance] = useState([]);
  const [allLeaves, setAllLeaves] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filterDate, setFilterDate] = useState(format(new Date(), 'yyyy-MM-dd'));
  const [filterMonth, setFilterMonth] = useState(format(new Date(), 'yyyy-MM'));
  const [searchTerm, setSearchTerm] = useState('');
  const [viewMode, setViewMode] = useState('daily'); // 'daily' | 'monthly'

  // Fetch all employees
  useEffect(() => {
    async function fetchEmployees() {
      const snap = await getDocs(collection(db, 'users'));
      setEmployees(snap.docs.map(d => ({ id: d.id, ...d.data() })).filter(u => u.role === 'employee'));
    }
    fetchEmployees();
  }, []);

  // Fetch attendance for the selected month
  useEffect(() => {
    async function fetchData() {
      setLoading(true);
      try {
        const monthDate = new Date(filterMonth + '-01');
        const start = format(startOfMonth(monthDate), 'yyyy-MM-dd');
        const end = format(endOfMonth(monthDate), 'yyyy-MM-dd');

        const attQ = query(
          collection(db, 'attendance'),
          where('date', '>=', start),
          where('date', '<=', end)
        );
        const attSnap = await getDocs(attQ);
        setAllAttendance(attSnap.docs.map(d => ({ id: d.id, ...d.data() })));

        const leaveQ = query(collection(db, 'leaves'));
        const leaveSnap = await getDocs(leaveQ);
        setAllLeaves(leaveSnap.docs.map(d => ({ id: d.id, ...d.data() })));
      } catch (err) {
        console.error('Error fetching admin attendance:', err);
      } finally {
        setLoading(false);
      }
    }
    fetchData();
  }, [filterMonth]);

  // Helper: format minutes to Xh Ym
  const fmtMins = (mins) => {
    if (!mins || mins <= 0) return '0h 0m';
    return `${Math.floor(mins / 60)}h ${mins % 60}m`;
  };

  // Helper: calculate total hours between checkIn and checkOut
  const calcTotalHours = (rec) => {
    if (!rec?.checkInTime) return 0;
    const end = rec.checkOutTime ? new Date(rec.checkOutTime) : new Date();
    return differenceInMinutes(end, new Date(rec.checkInTime));
  };

  // Count approved leaves for an employee in the selected month
  const getMonthlyLeaves = (userId) => {
    const monthDate = new Date(filterMonth + '-01');
    const mStart = startOfMonth(monthDate);
    const mEnd = endOfMonth(monthDate);
    return allLeaves.filter(l => {
      if (l.userId !== userId || l.status !== 'approved') return false;
      const lStart = new Date(l.startDate);
      const lEnd = new Date(l.endDate);
      return lStart <= mEnd && lEnd >= mStart;
    }).length;
  };

  // Get working days in the month (exclude weekends)
  const getWorkingDays = () => {
    const monthDate = new Date(filterMonth + '-01');
    const days = eachDayOfInterval({ start: startOfMonth(monthDate), end: endOfMonth(monthDate) });
    const today = new Date();
    return days.filter(d => !isWeekend(d) && d <= today).length;
  };

  // Build per-employee monthly stats
  const getMonthlyStats = (userId) => {
    const empRecords = allAttendance.filter(a => a.userId === userId);
    const presents = empRecords.filter(a => a.status === 'present').length;
    const lates = empRecords.filter(a => a.status === 'late').length;
    const outsides = empRecords.filter(a => a.status === 'outside').length;
    const totalInsideMins = empRecords.reduce((s, r) => s + (r.insideTime || 0), 0);
    const totalOutsideMins = empRecords.reduce((s, r) => s + (r.outsideTime || 0), 0);
    const totalHoursMins = totalInsideMins; // Use inside time for total hours
    const workingDays = getWorkingDays();
    const attended = empRecords.length;
    const leaves = getMonthlyLeaves(userId);
    const absents = Math.max(0, workingDays - attended - leaves);
    return { presents, lates, outsides, totalInsideMins, totalOutsideMins, totalHoursMins, absents, leaves, attended };
  };

  // Daily view data
  const dailyData = useMemo(() => {
    return employees.map(emp => {
      const rec = allAttendance.find(a => a.userId === emp.id && a.date === filterDate);
      const leaveRec = allLeaves.find(l => 
        l.userId === emp.id && 
        l.status === 'approved' && 
        filterDate >= l.startDate && 
        filterDate <= l.endDate
      );
      const stats = getMonthlyStats(emp.id);
      return { emp, rec, leaveRec, stats };
    }).filter(row =>
      row.emp.name?.toLowerCase().includes(searchTerm.toLowerCase()) ||
      row.emp.email?.toLowerCase().includes(searchTerm.toLowerCase())
    );
  }, [employees, allAttendance, allLeaves, filterDate, searchTerm, filterMonth]);

  // Summary counters for the selected date
  const daySummary = useMemo(() => {
    const dayRecs = allAttendance.filter(a => a.date === filterDate);
    const dayLeaves = employees.filter(emp => 
      allLeaves.some(l => 
        l.userId === emp.id && 
        l.status === 'approved' && 
        filterDate >= l.startDate && 
        filterDate <= l.endDate
      )
    ).length;

    return {
      total: employees.length,
      present: dayRecs.filter(r => r.status === 'present').length,
      late: dayRecs.filter(r => r.status === 'late').length,
      outside: dayRecs.filter(r => r.status === 'outside').length,
      leave: dayLeaves,
      absent: Math.max(0, employees.length - dayRecs.length - dayLeaves),
    };
  }, [employees, allAttendance, allLeaves, filterDate]);

  const statusBadge = (status, leaveRec) => {
    if (leaveRec) {
      const type = leaveRec.type?.toLowerCase() || 'leave';
      let color = 'bg-blue-50 text-blue-700 border-blue-200';
      if (type.includes('sick')) color = 'bg-rose-50 text-rose-700 border-rose-200';
      if (type.includes('home')) color = 'bg-indigo-50 text-indigo-700 border-indigo-200';
      
      return <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold uppercase tracking-wider border ${color}`}>
        {type === 'work_from_home' ? 'WFH' : type.replace('_', ' ')}
      </span>;
    }
    if (!status) return <span className="px-2.5 py-1 rounded-full text-[10px] font-bold uppercase tracking-wider bg-gray-100 text-gray-500 border border-gray-200">Absent</span>;
    const map = {
      present: 'bg-emerald-50 text-emerald-700 border-emerald-200',
      late: 'bg-amber-50 text-amber-700 border-amber-200',
      outside: 'bg-orange-50 text-orange-700 border-orange-200',
    };
    return <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold uppercase tracking-wider border ${map[status] || 'bg-gray-100 text-gray-500 border-gray-200'}`}>{status === 'outside' ? 'Out of System' : status}</span>;
  };

  const exportCSV = () => {
    let csv = "data:text/csv;charset=utf-8,Employee,Email,Date,Check In,Check Out,Status,Total Hours,Inside,Outside,Month Absents,Month Lates,Month Leaves,Month Total Hours\n";
    dailyData.forEach(({ emp, rec, leaveRec, stats }) => {
      const checkIn = rec?.checkInTime ? format(parseISO(rec.checkInTime), 'hh:mm a') : '-';
      const checkOut = rec?.checkOutTime ? format(parseISO(rec.checkOutTime), 'hh:mm a') : '-';
      let status = rec?.status || 'Absent';
      if (leaveRec) status = leaveRec.type?.replace('_', ' ') || 'On Leave';
      const totalH = rec ? fmtMins(rec?.insideTime || 0) : '-';
      csv += `"${emp.name}","${emp.email}","${filterDate}","${checkIn}","${checkOut}","${status}","${totalH}","${fmtMins(rec?.insideTime || 0)}","${fmtMins(rec?.outsideTime || 0)}","${stats.absents}","${stats.lates}","${stats.leaves}","${fmtMins(stats.totalHoursMins)}"\n`;
    });
    const link = document.createElement('a');
    link.setAttribute('href', encodeURI(csv));
    link.setAttribute('download', `attendance_${filterDate}.csv`);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  // Navigate date
  const prevDay = () => {
    const d = new Date(filterDate);
    d.setDate(d.getDate() - 1);
    const newDate = format(d, 'yyyy-MM-dd');
    setFilterDate(newDate);
    setFilterMonth(newDate.substring(0, 7));
  };
  const nextDay = () => {
    const d = new Date(filterDate);
    d.setDate(d.getDate() + 1);
    if (d > new Date()) return;
    const newDate = format(d, 'yyyy-MM-dd');
    setFilterDate(newDate);
    setFilterMonth(newDate.substring(0, 7));
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Attendance Management</h1>
          <p className="text-sm text-gray-500 mt-1">Complete employee attendance overview with daily & monthly analytics.</p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <button onClick={exportCSV} className="flex items-center gap-2 px-4 py-2.5 bg-white border border-gray-200 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 shadow-sm transition-colors">
            <FaFileExport className="text-emerald-600" /> Export
          </button>
        </div>
      </div>

      {/* Summary Cards */}
      <div className="grid grid-cols-2 sm:grid-cols-6 gap-3">
        {[
          { label: 'Total Staff', val: daySummary.total, color: 'indigo', icon: <FaUserCheck /> },
          { label: 'Present', val: daySummary.present, color: 'emerald', icon: <FaCalendarCheck /> },
          { label: 'Late', val: daySummary.late, color: 'amber', icon: <FaClock /> },
          { label: 'Outside', val: daySummary.outside, color: 'orange', icon: <FaExclamationTriangle /> },
          { label: 'On Leave', val: daySummary.leave, color: 'blue', icon: <FaCalendarAlt /> },
          { label: 'Absent', val: daySummary.absent, color: 'red', icon: <FaTimesCircle /> },
        ].map(s => (
          <div key={s.label} className="bg-white rounded-xl border border-gray-200 p-4 shadow-sm hover:shadow-md transition-shadow">
            <div className="flex items-center gap-3">
              <div className={`p-2.5 rounded-lg bg-${s.color}-50 text-${s.color}-600`}>{s.icon}</div>
              <div>
                <p className="text-[10px] font-bold text-gray-400 uppercase tracking-wider">{s.label}</p>
                <p className={`text-xl font-bold text-${s.color}-600`}>{s.val}</p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Filters Bar */}
      <div className="bg-white rounded-xl border border-gray-200 shadow-sm p-4">
        <div className="flex flex-col md:flex-row items-start md:items-center gap-3">
          {/* Date Navigator */}
          <div className="flex items-center bg-gray-50 rounded-lg border border-gray-200 overflow-hidden">
            <button onClick={prevDay} className="p-2.5 hover:bg-gray-100 text-gray-500 transition-colors"><FaChevronLeft className="text-xs" /></button>
            <input
              type="date"
              value={filterDate}
              onChange={(e) => {
                setFilterDate(e.target.value);
                setFilterMonth(e.target.value.substring(0, 7));
              }}
              className="px-3 py-2 text-sm font-medium text-gray-700 bg-transparent border-x border-gray-200 focus:outline-none min-w-[160px] text-center"
            />
            <button onClick={nextDay} className="p-2.5 hover:bg-gray-100 text-gray-500 transition-colors"><FaChevronRight className="text-xs" /></button>
          </div>

          {/* Month Filter */}
          <div className="flex items-center gap-2">
            <FaFilter className="text-gray-400 text-xs" />
            <input
              type="month"
              value={filterMonth}
              onChange={(e) => setFilterMonth(e.target.value)}
              className="px-3 py-2 text-sm border border-gray-200 rounded-lg bg-gray-50 focus:ring-2 focus:ring-indigo-500 focus:outline-none"
            />
          </div>

          {/* Search */}
          <div className="relative flex-1 w-full md:w-auto">
            <FaSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400 text-xs" />
            <input
              type="text"
              placeholder="Search employee..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full pl-9 pr-4 py-2 text-sm border border-gray-200 rounded-lg bg-gray-50 focus:ring-2 focus:ring-indigo-500 focus:outline-none"
            />
          </div>

          {/* Selected date label */}
          <div className="hidden md:flex items-center gap-2 text-sm text-gray-600 ml-auto">
            <FaCalendarAlt className="text-indigo-500" />
            <span className="font-semibold">{format(new Date(filterDate), 'EEEE, MMM dd, yyyy')}</span>
          </div>
        </div>
      </div>

      {/* Main Table */}
      <div className="bg-white rounded-xl border border-gray-200 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left min-w-[1200px]">
            <thead>
              <tr className="bg-gradient-to-r from-slate-50 to-gray-50 border-b border-gray-200">
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider sticky left-0 bg-slate-50 z-10">Employee</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Date</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Status</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Check In</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Check Out</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Total Hrs</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Inside</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider">Outside</th>
                <th className="px-4 py-3.5 text-[10px] font-bold text-gray-500 uppercase tracking-wider text-center border-l border-gray-200" colSpan="4">
                  Monthly Summary ({format(new Date(filterMonth + '-01'), 'MMM yyyy')})
                </th>
              </tr>
              <tr className="bg-gray-50/50 border-b border-gray-100">
                <th colSpan="8"></th>
                <th className="px-3 py-2 text-[9px] font-bold text-red-500 uppercase tracking-wider text-center border-l border-gray-200">Absents</th>
                <th className="px-3 py-2 text-[9px] font-bold text-amber-500 uppercase tracking-wider text-center">Lates</th>
                <th className="px-3 py-2 text-[9px] font-bold text-blue-500 uppercase tracking-wider text-center">Leaves</th>
                <th className="px-3 py-2 text-[9px] font-bold text-indigo-500 uppercase tracking-wider text-center">Total Hrs</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {loading ? (
                <tr><td colSpan="12" className="px-6 py-16 text-center">
                  <div className="flex flex-col items-center gap-2 text-gray-400">
                    <div className="w-8 h-8 border-3 border-indigo-200 border-t-indigo-600 rounded-full animate-spin"></div>
                    <span className="text-sm">Loading attendance data...</span>
                  </div>
                </td></tr>
              ) : dailyData.length === 0 ? (
                <tr><td colSpan="12" className="px-6 py-16 text-center text-gray-400 text-sm">No employees found.</td></tr>
              ) : dailyData.map(({ emp, rec, leaveRec, stats }, idx) => (
                <tr key={emp.id} className={`hover:bg-indigo-50/30 transition-colors ${idx % 2 === 0 ? 'bg-white' : 'bg-gray-50/30'}`}>
                  {/* Employee */}
                  <td className="px-4 py-3.5 sticky left-0 bg-inherit z-10">
                    <div className="flex items-center gap-3">
                      <img
                        className="h-9 w-9 rounded-full object-cover border-2 border-gray-200 flex-shrink-0"
                        src={emp.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(emp.name || 'U')}&background=6366f1&color=fff&size=36`}
                        alt=""
                      />
                      <div className="min-w-0">
                        <p className="text-sm font-semibold text-gray-900 truncate">{emp.name}</p>
                        <p className="text-[11px] text-gray-400 truncate">{emp.department || emp.email}</p>
                      </div>
                    </div>
                  </td>
                  {/* Date */}
                  <td className="px-4 py-3.5">
                    <span className="text-sm text-gray-700 font-medium">{format(new Date(filterDate), 'dd MMM')}</span>
                    <p className="text-[10px] text-gray-400">{format(new Date(filterDate), 'EEEE')}</p>
                  </td>
                  {/* Status */}
                  <td className="px-4 py-3.5">{statusBadge(rec?.status, leaveRec)}</td>
                  {/* Check In */}
                  <td className="px-4 py-3.5">
                    <span className={`text-sm font-mono ${rec?.checkInTime ? 'text-gray-800' : 'text-gray-300'}`}>
                      {rec?.checkInTime ? format(parseISO(rec.checkInTime), 'hh:mm a') : '--:--'}
                    </span>
                  </td>
                  {/* Check Out */}
                  <td className="px-4 py-3.5">
                    <span className={`text-sm font-mono ${rec?.checkOutTime ? 'text-gray-800' : 'text-gray-300'}`}>
                      {rec?.checkOutTime ? format(parseISO(rec.checkOutTime), 'hh:mm a') : '--:--'}
                    </span>
                  </td>
                  {/* Total Hours */}
                  <td className="px-4 py-3.5">
                    <span className="text-sm font-semibold text-gray-800">
                      {rec ? fmtMins(rec?.insideTime || 0) : '-'}
                    </span>
                  </td>
                  {/* Inside */}
                  <td className="px-4 py-3.5">
                    <span className="text-sm text-emerald-600 font-medium">{fmtMins(rec?.insideTime || 0)}</span>
                  </td>
                  {/* Outside */}
                  <td className="px-4 py-3.5">
                    <span className="text-sm text-orange-600 font-medium">{fmtMins(rec?.outsideTime || 0)}</span>
                  </td>
                  {/* Monthly: Absents */}
                  <td className="px-3 py-3.5 text-center border-l border-gray-100">
                    <span className={`inline-flex items-center justify-center w-8 h-8 rounded-lg text-sm font-bold ${stats.absents > 0 ? 'bg-red-50 text-red-600' : 'bg-gray-50 text-gray-400'}`}>
                      {stats.absents}
                    </span>
                  </td>
                  {/* Monthly: Lates */}
                  <td className="px-3 py-3.5 text-center">
                    <span className={`inline-flex items-center justify-center w-8 h-8 rounded-lg text-sm font-bold ${stats.lates > 0 ? 'bg-amber-50 text-amber-600' : 'bg-gray-50 text-gray-400'}`}>
                      {stats.lates}
                    </span>
                  </td>
                  {/* Monthly: Leaves */}
                  <td className="px-3 py-3.5 text-center">
                    <span className={`inline-flex items-center justify-center w-8 h-8 rounded-lg text-sm font-bold ${stats.leaves > 0 ? 'bg-blue-50 text-blue-600' : 'bg-gray-50 text-gray-400'}`}>
                      {stats.leaves}
                    </span>
                  </td>
                  {/* Monthly: Total Hours */}
                  <td className="px-3 py-3.5 text-center">
                    <span className="text-sm font-semibold text-indigo-600">{fmtMins(stats.totalHoursMins)}</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Table Footer */}
        {!loading && dailyData.length > 0 && (
          <div className="px-6 py-3 bg-gray-50 border-t border-gray-200 flex items-center justify-between text-xs text-gray-500">
            <span>Showing {dailyData.length} of {employees.length} employees</span>
            <span>Working days this month: {getWorkingDays()}</span>
          </div>
        )}
      </div>
    </div>
  );
}
