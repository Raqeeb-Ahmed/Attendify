import { useState, useEffect } from 'react';
import { db } from '../firebase/config';
import { collection, addDoc, query, where, getDocs, orderBy } from 'firebase/firestore';
import { useAuth } from '../hooks/useAuth';
import { LEAVE_TYPES, LEAVE_STATUS } from '../constants/hcm';
import { FaCalendarPlus, FaInfoCircle, FaCheckCircle, FaTimesCircle, FaClock } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';
import { createNotification } from '../services/notifications';

export default function LeaveManagement() {
  const { user } = useAuth();
  const [leaves, setLeaves] = useState([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isApplying, setIsApplying] = useState(false);
  const [formData, setFormData] = useState({
    type: 'annual',
    startDate: '',
    endDate: '',
    reason: ''
  });

  useEffect(() => {
    if (user) fetchMyLeaves();
  }, [user]);

  const fetchMyLeaves = async () => {
    setLoading(true);
    try {
      const q = query(
        collection(db, 'leaves'),
        where('userId', '==', user.uid),
        orderBy('createdAt', 'desc')
      );
      const querySnapshot = await getDocs(q);
      setLeaves(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching leaves:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleApplyLeave = async (e) => {
    e.preventDefault();
    if (isApplying) return;
    setIsApplying(true);
    try {
      await addDoc(collection(db, 'leaves'), {
        ...formData,
        userId: user.uid,
        userName: user.name,
        userEmail: user.email,
        status: 'pending',
        createdAt: new Date().toISOString()
      });
      
      await createNotification({
        targetRole: 'admin',
        title: 'New Leave Request',
        message: `${user.name} applied for ${formData.type} leave from ${formData.startDate} to ${formData.endDate}.`,
        type: 'info'
      });

      setIsModalOpen(false);
      fetchMyLeaves();
      setFormData({ type: 'annual', startDate: '', endDate: '', reason: '' });
    } catch (error) {
      console.error("Error applying leave:", error);
    } finally {
      setIsApplying(false);
    }
  };

  const getStatusBadge = (status) => {
    const s = LEAVE_STATUS.find(st => st.id === status);
    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${s?.color}`}>
        {status === 'pending' && <FaClock className="mr-1" />}
        {status === 'approved' && <FaCheckCircle className="mr-1" />}
        {status === 'rejected' && <FaTimesCircle className="mr-1" />}
        {s?.label}
      </span>
    );
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Leave Management</h1>
          <p className="text-gray-500 text-sm">Apply for leaves and track your requests.</p>
        </div>
        <button 
          onClick={() => setIsModalOpen(true)}
          className="flex items-center justify-center px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 transition-colors shadow-sm text-sm font-medium"
        >
          <FaCalendarPlus className="mr-2" /> Apply for Leave
        </button>
      </div>

      {/* Leave Balances */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {LEAVE_TYPES.map((type) => (
          <div key={type.id} className="bg-white p-4 rounded-xl shadow-sm border border-gray-100">
            <p className="text-xs font-bold text-gray-400 uppercase tracking-widest">{type.label}</p>
            <div className="flex items-baseline mt-1">
              <span className="text-2xl font-bold text-gray-900">{user?.[`${type.id}Balance`] ?? type.defaultBalance}</span>
              <span className="text-xs text-gray-400 ml-1">Days remaining</span>
            </div>
          </div>
        ))}
      </div>

      {/* Requests Table */}
      <div className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden">
        <div className="px-6 py-4 border-b border-gray-100">
          <h2 className="text-sm font-bold text-gray-900 uppercase tracking-wider">Your Requests</h2>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left">
            <thead className="bg-gray-50 border-b border-gray-100">
              <tr>
                <th className="px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Leave Type</th>
                <th className="px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Duration</th>
                <th className="px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Status</th>
                <th className="px-6 py-3 text-xs font-semibold text-gray-500 uppercase">Applied On</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {loading ? (
                <tr><td colSpan="4" className="px-6 py-10 text-center text-gray-500">Loading requests...</td></tr>
              ) : leaves.length === 0 ? (
                <tr><td colSpan="4" className="px-6 py-10 text-center text-gray-500">No leave requests found.</td></tr>
              ) : leaves.map((leave) => (
                <tr key={leave.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4">
                    <div className="text-sm font-medium text-gray-900 capitalize">{leave.type} Leave</div>
                    <div className="text-xs text-gray-500 truncate max-w-xs" title={leave.reason}>{leave.reason}</div>
                    {leave.adminMessage && <div className="text-[10px] text-indigo-600 mt-1">Note: {leave.adminMessage}</div>}
                  </td>
                  <td className="px-6 py-4">
                    <div className="text-sm text-gray-900">{leave.startDate} to {leave.endDate}</div>
                  </td>
                  <td className="px-6 py-4">
                    {getStatusBadge(leave.status)}
                  </td>
                  <td className="px-6 py-4 text-xs text-gray-500">
                    {new Date(leave.createdAt).toLocaleDateString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Apply Leave Modal */}
      <AnimatePresence>
        {isModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden"
            >
              <form onSubmit={handleApplyLeave}>
                <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
                  <h2 className="text-xl font-bold text-gray-900">Apply for Leave</h2>
                  <button type="button" onClick={() => setIsModalOpen(false)} className="text-gray-400">✕</button>
                </div>
                <div className="p-6 space-y-4">
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Leave Type</label>
                    <select 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={formData.type}
                      onChange={(e) => setFormData({...formData, type: e.target.value})}
                      required
                    >
                      {LEAVE_TYPES.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
                    </select>
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <label className="text-sm font-semibold text-gray-700">Start Date</label>
                      <input 
                        type="date" 
                        className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                        value={formData.startDate}
                        onChange={(e) => setFormData({...formData, startDate: e.target.value})}
                        required
                      />
                    </div>
                    <div className="space-y-1">
                      <label className="text-sm font-semibold text-gray-700">End Date</label>
                      <input 
                        type="date" 
                        className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                        value={formData.endDate}
                        onChange={(e) => setFormData({...formData, endDate: e.target.value})}
                        required
                      />
                    </div>
                  </div>
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Reason</label>
                    <textarea 
                      rows="3"
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      placeholder="Briefly explain the reason for leave..."
                      value={formData.reason}
                      onChange={(e) => setFormData({...formData, reason: e.target.value})}
                      required
                    ></textarea>
                  </div>
                  <div className="bg-blue-50 p-4 rounded-lg flex items-start">
                    <FaInfoCircle className="text-blue-500 mt-0.5 mr-3 flex-shrink-0" />
                    <p className="text-xs text-blue-700 leading-relaxed">
                      Your request will be sent to HR for approval. Please ensure you have sufficient leave balance.
                    </p>
                  </div>
                </div>
                <div className="px-6 py-4 bg-gray-50 border-t border-gray-100 flex justify-end gap-3">
                  <button type="button" onClick={() => setIsModalOpen(false)} className="px-4 py-2 text-sm font-semibold text-gray-600">Cancel</button>
                  <button type="submit" disabled={isApplying} className="px-6 py-2 bg-indigo-600 text-white rounded-lg font-semibold text-sm shadow-md disabled:opacity-70 disabled:cursor-not-allowed">
                    {isApplying ? 'Applying/Saving...' : 'Submit Request'}
                  </button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
