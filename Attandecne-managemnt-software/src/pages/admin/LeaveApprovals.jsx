import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, doc, updateDoc, query, orderBy, where, getDoc } from 'firebase/firestore';
import { LEAVE_STATUS } from '../../constants/hcm';
import { FaCheck, FaTimes, FaUser, FaCalendarAlt, FaSearch, FaHistory, FaFolderOpen } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function LeaveApprovals() {
  const [requests, setRequests] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [adminMessages, setAdminMessages] = useState({});
  const [selectedEmployee, setSelectedEmployee] = useState(null);

  useEffect(() => {
    const initFetch = async () => {
      setLoading(true);
      await Promise.all([fetchLeaves(), fetchEmployees()]);
      setLoading(false);
    };
    initFetch();
  }, []);

  const fetchLeaves = async () => {
    try {
      const q = query(collection(db, 'leaves'), orderBy('createdAt', 'desc'));
      const querySnapshot = await getDocs(q);
      setRequests(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching leave requests:", error);
    }
  };

  const fetchEmployees = async () => {
    try {
      const q = query(collection(db, 'users'), where('role', '==', 'employee'));
      const querySnapshot = await getDocs(q);
      setEmployees(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching employees:", error);
    }
  };

  const handleAction = async (requestId, status, userId, leaveType, startDate, endDate) => {
    try {
      const adminMessage = adminMessages[requestId] || '';
      const reqRef = doc(db, 'leaves', requestId);
      await updateDoc(reqRef, { status, adminMessage, updatedAt: new Date().toISOString() });

      if (status === 'approved') {
        const start = new Date(startDate);
        const end = new Date(endDate);
        const diffTime = Math.abs(end - start);
        const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24)) + 1;

        const userRef = doc(db, 'users', userId);
        const userSnap = await getDoc(userRef);
        if (userSnap.exists()) {
          const userData = userSnap.data();
          const currentBalance = userData[`${leaveType}Balance`] ?? 20; 
          await updateDoc(userRef, {
            [`${leaveType}Balance`]: Math.max(0, currentBalance - diffDays)
          });
        }
      }
      
      setAdminMessages(prev => ({ ...prev, [requestId]: '' }));
      fetchLeaves();
    } catch (error) {
      console.error("Error updating request:", error);
    }
  };

  const filteredEmployees = employees.filter(emp => 
    emp.name?.toLowerCase().includes(search.toLowerCase()) ||
    emp.email?.toLowerCase().includes(search.toLowerCase())
  );

  const pendingRequests = requests.filter(req => 
    req.status === 'pending' && 
    (req.userName?.toLowerCase().includes(search.toLowerCase()) || req.type?.toLowerCase().includes(search.toLowerCase()))
  );

  const selectedEmployeeLeaves = selectedEmployee 
    ? requests.filter(r => r.userId === selectedEmployee.id)
    : [];

  const RequestRow = ({ req, showEmployeeDetails = true }) => (
    <tr className="hover:bg-gray-50 transition-colors">
      {showEmployeeDetails && (
        <td className="px-6 py-4">
          <div className="flex items-center">
            <div className="h-9 w-9 bg-indigo-100 rounded-full flex items-center justify-center text-indigo-600 mr-3 overflow-hidden">
              <img src={`https://ui-avatars.com/api/?name=${req.userName}`} alt="" className="w-full h-full object-cover" />
            </div>
            <div>
              <div className="text-sm font-semibold text-gray-900">{req.userName}</div>
              <div className="text-xs text-gray-500">{req.userEmail}</div>
            </div>
          </div>
        </td>
      )}
      <td className="px-6 py-4">
        <div className="text-sm font-medium text-gray-900 capitalize">{req.type} Leave</div>
        <div className="text-xs text-gray-500 truncate max-w-xs" title={req.reason}>{req.reason}</div>
        {req.adminMessage && <div className="text-[10px] text-indigo-600 mt-1 font-medium">Note: {req.adminMessage}</div>}
      </td>
      <td className="px-6 py-4">
        <div className="flex items-center text-sm text-gray-700">
          <FaCalendarAlt className="mr-2 text-gray-400" />
          {req.startDate} to {req.endDate}
        </div>
      </td>
      <td className="px-6 py-4">
        <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${LEAVE_STATUS.find(s => s.id === req.status)?.color || 'bg-gray-100 text-gray-800'}`}>
          {req.status}
        </span>
      </td>
      <td className="px-6 py-4 text-right">
        {req.status === 'pending' && (
          <div className="flex flex-col items-end gap-2">
            <input
              type="text"
              placeholder="Add a note (optional)..."
              className="text-xs px-2 py-1 border border-gray-200 rounded outline-none focus:border-indigo-500 w-48"
              value={adminMessages[req.id] || ''}
              onChange={(e) => setAdminMessages(prev => ({...prev, [req.id]: e.target.value}))}
            />
            <div className="flex justify-end gap-2">
              <button 
                onClick={() => handleAction(req.id, 'approved', req.userId, req.type, req.startDate, req.endDate)}
                className="p-2 bg-green-50 text-green-600 hover:bg-green-100 rounded-lg transition-colors"
                title="Approve"
              >
                <FaCheck />
              </button>
              <button 
                onClick={() => handleAction(req.id, 'rejected', req.userId, req.type, req.startDate, req.endDate)}
                className="p-2 bg-red-50 text-red-600 hover:bg-red-100 rounded-lg transition-colors"
                title="Reject"
              >
                <FaTimes />
              </button>
            </div>
          </div>
        )}
      </td>
    </tr>
  );

  return (
    <div className="space-y-8 pb-10">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Leave Approvals</h1>
          <p className="text-gray-500 text-sm mt-1">Review pending requests and explore employee leave history.</p>
        </div>
        <div className="relative w-full md:w-72">
          <FaSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input 
            type="text" 
            placeholder="Search employee by name or email..."
            className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500 text-sm shadow-sm"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      {loading ? (
        <div className="text-center py-12 text-gray-500">
          <div className="w-8 h-8 border-4 border-indigo-200 border-t-indigo-600 rounded-full animate-spin mx-auto mb-3"></div>
          Loading leave data...
        </div>
      ) : (
        <>
          {/* Action Required: Pending Leaves */}
          {pendingRequests.length > 0 && (
            <div className="bg-white rounded-xl shadow-sm border border-amber-200 overflow-hidden">
              <div className="px-6 py-4 border-b border-gray-100 bg-gradient-to-r from-amber-50 to-orange-50 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <span className="relative flex h-3 w-3">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-amber-400 opacity-75"></span>
                    <span className="relative inline-flex rounded-full h-3 w-3 bg-amber-500"></span>
                  </span>
                  <h2 className="text-sm font-bold text-gray-900 uppercase tracking-wider">Action Required</h2>
                </div>
                <span className="text-xs font-semibold text-amber-700 bg-amber-100 px-2.5 py-1 rounded-full">{pendingRequests.length} Pending</span>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-left">
                  <thead className="bg-gray-50 border-b border-gray-100">
                    <tr>
                      <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Employee</th>
                      <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Leave Details</th>
                      <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Duration</th>
                      <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Status</th>
                      <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {pendingRequests.map((req) => <RequestRow key={req.id} req={req} />)}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* Employee Leave Directory */}
          <div>
            <div className="flex items-center gap-2 mb-4">
              <FaFolderOpen className="text-indigo-600" />
              <h2 className="text-sm font-bold text-gray-900 uppercase tracking-wider">Employee Leave Directory</h2>
            </div>
            
            {filteredEmployees.length === 0 ? (
              <div className="text-center py-10 bg-white rounded-xl border border-dashed border-gray-300 text-gray-500">
                No employees found matching your search.
              </div>
            ) : (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                {filteredEmployees.map(emp => {
                  const empLeaves = requests.filter(r => r.userId === emp.id);
                  const approved = empLeaves.filter(r => r.status === 'approved').length;
                  const pending = empLeaves.filter(r => r.status === 'pending').length;
                  const rejected = empLeaves.filter(r => r.status === 'rejected').length;

                  return (
                    <div 
                      key={emp.id} 
                      onClick={() => setSelectedEmployee(emp)}
                      className="bg-white border border-gray-200 rounded-xl p-5 cursor-pointer hover:shadow-lg hover:border-indigo-400 transition-all flex flex-col items-center text-center group"
                    >
                      <div className="relative mb-3">
                        <img src={emp.photoURL || `https://ui-avatars.com/api/?name=${emp.name}&background=e0e7ff&color=4f46e5`} className="w-16 h-16 rounded-full object-cover border-2 border-white shadow-sm" alt="" />
                        {pending > 0 && (
                          <div className="absolute -top-1 -right-1 bg-amber-500 text-white text-[10px] font-bold w-5 h-5 rounded-full flex items-center justify-center shadow-sm">
                            {pending}
                          </div>
                        )}
                      </div>
                      <h3 className="font-semibold text-gray-900 group-hover:text-indigo-600 transition-colors">{emp.name}</h3>
                      <p className="text-xs text-gray-500 mb-4 truncate w-full px-2">{emp.email}</p>
                      
                      <div className="flex w-full justify-between border-t border-gray-100 pt-3 mt-auto">
                        <div className="text-center flex-1">
                          <p className="text-[9px] text-gray-400 uppercase font-bold tracking-wider mb-1">Approved</p>
                          <p className="text-sm font-semibold text-emerald-600">{approved}</p>
                        </div>
                        <div className="text-center flex-1 border-l border-gray-100">
                          <p className="text-[9px] text-gray-400 uppercase font-bold tracking-wider mb-1">Pending</p>
                          <p className="text-sm font-semibold text-amber-600">{pending}</p>
                        </div>
                        <div className="text-center flex-1 border-l border-gray-100">
                          <p className="text-[9px] text-gray-400 uppercase font-bold tracking-wider mb-1">Rejected</p>
                          <p className="text-sm font-semibold text-red-500">{rejected}</p>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </>
      )}

      {/* Employee Leaves Modal */}
      <AnimatePresence>
        {selectedEmployee && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/40 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, y: 20, scale: 0.95 }}
              animate={{ opacity: 1, y: 0, scale: 1 }}
              exit={{ opacity: 0, y: 20, scale: 0.95 }}
              className="bg-white rounded-2xl shadow-2xl w-full max-w-5xl overflow-hidden max-h-[90vh] flex flex-col"
            >
              <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between bg-gradient-to-r from-indigo-50 to-white">
                <div className="flex items-center gap-4">
                  <img src={selectedEmployee.photoURL || `https://ui-avatars.com/api/?name=${selectedEmployee.name}`} className="w-12 h-12 rounded-full border-2 border-white shadow-sm" alt="" />
                  <div>
                    <h2 className="text-xl font-bold text-gray-900">{selectedEmployee.name}'s Leave History</h2>
                    <p className="text-xs text-gray-500">{selectedEmployee.email} • {selectedEmployee.department || 'Employee'}</p>
                  </div>
                </div>
                <button onClick={() => setSelectedEmployee(null)} className="text-gray-400 hover:text-gray-600 hover:bg-gray-100 p-2 rounded-full transition-colors">✕</button>
              </div>
              
              <div className="flex-1 overflow-y-auto p-6 bg-gray-50">
                {selectedEmployeeLeaves.length === 0 ? (
                  <div className="text-center py-16 text-gray-400 bg-white rounded-xl border border-gray-200 shadow-sm">
                    <FaHistory className="text-4xl mx-auto mb-3 opacity-20" />
                    <p className="text-sm font-medium">No leave records found for this employee.</p>
                  </div>
                ) : (
                  <div className="bg-white rounded-xl shadow-sm border border-gray-200 overflow-hidden">
                    <table className="w-full text-left">
                      <thead className="bg-gray-50 border-b border-gray-100">
                        <tr>
                          <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Leave Details</th>
                          <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Duration</th>
                          <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase">Status</th>
                          <th className="px-6 py-4 text-xs font-semibold text-gray-500 uppercase text-right">Actions</th>
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-gray-100">
                        {selectedEmployeeLeaves.map(req => <RequestRow key={req.id} req={req} showEmployeeDetails={false} />)}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
              <div className="px-6 py-4 bg-white border-t border-gray-100 flex justify-end">
                <button onClick={() => setSelectedEmployee(null)} className="px-6 py-2 bg-gray-900 text-white rounded-lg font-semibold text-sm hover:bg-gray-800 transition-colors">Close</button>
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
