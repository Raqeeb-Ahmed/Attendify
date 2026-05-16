import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, query, where, orderBy, doc, updateDoc, getDoc } from 'firebase/firestore';
import { FaInbox, FaCheckCircle, FaTimesCircle, FaCalendarCheck, FaWallet, FaFileAlt, FaClock } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';
import { createNotification } from '../../services/notifications';

export default function WorkflowApprovals() {
  const [requests, setRequests] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState('all');

  useEffect(() => {
    fetchRequests();
  }, []);

  const fetchRequests = async () => {
    setLoading(true);
    try {
      // Fetch Leaves
      const leaveQ = query(collection(db, 'leaves'), where('status', '==', 'pending'));
      const leaveSnap = await getDocs(leaveQ);
      const leaveReqs = leaveSnap.docs.map(doc => ({ id: doc.id, type: 'leave', ...doc.data() }));

      // Fetch Expenses
      const expenseQ = query(collection(db, 'expenses'), where('status', '==', 'pending'));
      const expenseSnap = await getDocs(expenseQ);
      const expenseReqs = expenseSnap.docs.map(doc => ({ id: doc.id, type: 'expense', ...doc.data() }));

      setRequests([...leaveReqs, ...expenseReqs].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)));
    } catch (error) {
      console.error("Error fetching workflows:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleAction = async (id, type, status) => {
    try {
      const collectionName = type === 'leave' ? 'leaves' : 'expenses';
      await updateDoc(doc(db, collectionName, id), { status, updatedAt: new Date().toISOString() });
      
      const docSnap = await getDoc(doc(db, collectionName, id));
      if (docSnap.exists()) {
        const data = docSnap.data();
        await createNotification({
          userId: data.userId,
          title: `${type === 'leave' ? 'Leave' : 'Expense'} Request ${status.charAt(0).toUpperCase() + status.slice(1)}`,
          message: `Your ${type} request has been ${status} by HR.`,
          type: status === 'approved' ? 'success' : 'warning'
        });
      }

      fetchRequests();
    } catch (error) {
      console.error(`Error updating ${type}:`, error);
    }
  };

  const filteredRequests = filter === 'all' ? requests : requests.filter(r => r.type === filter);

  return (
    <div className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Workflow & Approvals</h1>
          <p className="text-gray-500 text-sm">Unified inbox for all pending requests across the HCM.</p>
        </div>
        <div className="flex bg-white p-1 rounded-xl border border-gray-100 shadow-sm">
          {['all', 'leave', 'expense'].map(t => (
            <button
              key={t}
              onClick={() => setFilter(t)}
              className={`px-4 py-1.5 rounded-lg text-xs font-bold capitalize transition-all ${filter === t ? 'bg-indigo-600 text-white shadow-md' : 'text-gray-500 hover:bg-gray-50'}`}
            >
              {t}s
            </button>
          ))}
        </div>
      </div>

      <div className="grid grid-cols-1 gap-4">
        {loading ? (
          <div className="text-center py-20 text-gray-500">Scanning for pending requests...</div>
        ) : filteredRequests.length === 0 ? (
          <div className="bg-white p-20 rounded-3xl border border-dashed border-gray-200 text-center">
            <div className="h-16 w-16 bg-green-50 text-green-600 rounded-full flex items-center justify-center mx-auto mb-4">
              <FaCheckCircle className="text-3xl" />
            </div>
            <h3 className="text-lg font-bold text-gray-900">All caught up!</h3>
            <p className="text-gray-400">No pending requests require your attention.</p>
          </div>
        ) : (
          filteredRequests.map((req) => (
            <motion.div 
              key={req.id}
              layout
              initial={{ opacity: 0, y: 10 }}
              animate={{ opacity: 1, y: 0 }}
              className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex flex-col md:flex-row items-center justify-between gap-6"
            >
              <div className="flex items-center gap-4 flex-1">
                <div className={`h-12 w-12 rounded-2xl flex items-center justify-center text-xl ${req.type === 'leave' ? 'bg-orange-50 text-orange-600' : 'bg-green-50 text-green-600'}`}>
                  {req.type === 'leave' ? <FaCalendarCheck /> : <FaWallet />}
                </div>
                <div>
                  <div className="flex items-center gap-2">
                    <h4 className="font-bold text-gray-900">{req.userName}</h4>
                    <span className="px-2 py-0.5 bg-gray-100 text-gray-500 rounded text-[10px] font-bold uppercase tracking-widest">{req.type}</span>
                  </div>
                  <p className="text-sm text-gray-500 line-clamp-1">
                    {req.type === 'leave' ? `${req.leaveType}: ${req.startDate} to ${req.endDate}` : `${req.category}: ${req.amount} - ${req.description}`}
                  </p>
                </div>
              </div>

              <div className="flex items-center gap-6">
                <div className="text-right hidden sm:block">
                  <p className="text-xs font-bold text-gray-400 flex items-center justify-end">
                    <FaClock className="mr-1" /> Requested
                  </p>
                  <p className="text-xs text-gray-500">{new Date(req.createdAt).toLocaleDateString()}</p>
                </div>
                <div className="flex gap-2">
                  <button 
                    onClick={() => handleAction(req.id, req.type, 'approved')}
                    className="px-4 py-2 bg-green-600 text-white rounded-xl text-xs font-bold hover:bg-green-700 shadow-md shadow-green-100 transition-all"
                  >
                    Approve
                  </button>
                  <button 
                    onClick={() => handleAction(req.id, req.type, 'rejected')}
                    className="px-4 py-2 bg-white text-red-600 border border-red-100 rounded-xl text-xs font-bold hover:bg-red-50 transition-all"
                  >
                    Reject
                  </button>
                </div>
              </div>
            </motion.div>
          ))
        )}
      </div>
    </div>
  );
}
