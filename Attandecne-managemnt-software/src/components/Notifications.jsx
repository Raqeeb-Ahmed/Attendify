import { useState, useEffect, useRef } from 'react';
import { db } from '../firebase/config';
import { collection, query, where, orderBy, onSnapshot, doc, updateDoc, getDocs, limit } from 'firebase/firestore';
import { useAuth } from '../hooks/useAuth';
import { FaBell, FaCalendarCheck, FaMoneyCheckAlt, FaFileAlt, FaWallet, FaUserCheck, FaTimes, FaInbox, FaCheck } from 'react-icons/fa';
import { formatDistanceToNow, parseISO } from 'date-fns';
import { motion, AnimatePresence } from 'framer-motion';

export default function Notifications() {
  const { user } = useAuth();
  const [notifications, setNotifications] = useState([]);
  const [activities, setActivities] = useState([]);
  const [isOpen, setIsOpen] = useState(false);
  const [activeTab, setActiveTab] = useState('activity');
  const [loading, setLoading] = useState(false);
  const buttonRef = useRef(null);

  // Close on outside click
  useEffect(() => {
    const handleClickOutside = (e) => {
      // If the click is on an element that is no longer in the document 
      // (like a notification item that just got removed), ignore it.
      if (!document.body.contains(e.target)) return;
      
      if (buttonRef.current && !buttonRef.current.contains(e.target)) {
        setIsOpen(false);
      }
    };
    if (isOpen) document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isOpen]);

  // Fetch official notifications (Alerts)
  useEffect(() => {
    if (!user) return;
    
    const qUser = query(
      collection(db, 'notifications'),
      where('userId', '==', user.uid),
      orderBy('createdAt', 'desc')
    );

    const unsubUser = onSnapshot(qUser, (snap) => {
      const userNotifs = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
      setNotifications(prev => {
        const adminItems = prev.filter(n => n.targetRole === 'admin');
        const combined = [...userNotifs, ...adminItems];
        const unique = Array.from(new Set(combined.map(a => a.id))).map(id => combined.find(a => a.id === id));
        return unique.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      });
    });

    let unsubAdmin = () => {};
    if (user.role === 'admin') {
       const qAdmin = query(
          collection(db, 'notifications'),
          where('targetRole', '==', 'admin'),
          orderBy('createdAt', 'desc')
       );
       unsubAdmin = onSnapshot(qAdmin, (snap) => {
          const adminNotifs = snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
          setNotifications(prev => {
             const userItems = prev.filter(n => n.userId === user.uid);
             const combined = [...userItems, ...adminNotifs];
             const unique = Array.from(new Set(combined.map(a => a.id))).map(id => combined.find(a => a.id === id));
             return unique.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
          });
       });
    }

    return () => { unsubUser(); unsubAdmin(); };
  }, [user]);

  // Fetch activity
  useEffect(() => {
    if (!user || user.role !== 'admin' || !isOpen) return;

    const fetchActivity = async () => {
      setLoading(true);
      try {
        const activityItems = [];
        const today = new Date().toISOString().substring(0, 10);

        // Fetch concurrently
        const [leaves, expenses, attendance] = await Promise.all([
          getDocs(query(collection(db, 'leaves'), orderBy('appliedAt', 'desc'), limit(10))),
          getDocs(query(collection(db, 'expenses'), orderBy('createdAt', 'desc'), limit(10))),
          getDocs(query(collection(db, 'attendance'), where('date', '==', today), limit(20)))
        ]);

        leaves.docs.forEach(d => {
          const data = d.data();
          activityItems.push({
            id: `leave_${d.id}`,
            icon: <FaCalendarCheck className="text-emerald-500" />,
            title: `${data.userName} - Leave`,
            detail: `${data.type} • ${data.startDate} to ${data.endDate}`,
            status: data.status,
            time: data.appliedAt || data.createdAt
          });
        });

        expenses.docs.forEach(d => {
          const data = d.data();
          activityItems.push({
            id: `exp_${d.id}`,
            icon: <FaWallet className="text-rose-500" />,
            title: `${data.userName} - Expense`,
            detail: `${data.category} • PKR ${Number(data.amount).toLocaleString()}`,
            status: data.status,
            time: data.createdAt
          });
        });

        attendance.docs.forEach(d => {
          const data = d.data();
          activityItems.push({
            id: `att_${d.id}`,
            icon: <FaUserCheck className="text-blue-500" />,
            title: `${data.userName} - Check-In`,
            detail: `Status: ${data.status?.toUpperCase()}`,
            status: data.status,
            time: data.checkInTime
          });
        });

        activityItems.sort((a, b) => new Date(b.time || 0) - new Date(a.time || 0));
        setActivities(activityItems.slice(0, 25));
      } catch (err) {
        console.error(err);
      } finally {
        setLoading(false);
      }
    };
    fetchActivity();
  }, [user, isOpen]);

  const unreadNotifications = notifications.filter(n => !n.readBy?.includes(user?.uid));
  const totalUnreadCount = unreadNotifications.length;

  const handleMarkAsRead = async (notif) => {
    try {
      const readBy = notif.readBy || [];
      if (!readBy.includes(user.uid)) {
        await updateDoc(doc(db, 'notifications', notif.id), {
          readBy: [...readBy, user.uid]
        });
      }
    } catch (e) { console.error(e); }
  };

  const getStatusBadge = (status) => {
    if (!status) return null;
    const colors = {
      pending: 'bg-amber-100 text-amber-700',
      approved: 'bg-green-100 text-green-700',
      rejected: 'bg-red-100 text-red-700',
      present: 'bg-blue-100 text-blue-700',
      late: 'bg-yellow-100 text-yellow-700',
      outside: 'bg-orange-100 text-orange-700',
    };
    return (
      <span className={`px-2 py-0.5 rounded-full text-[9px] font-black uppercase ${colors[status] || 'bg-gray-100 text-gray-600'}`}>
        {status}
      </span>
    );
  };

  return (
    <div className="relative" ref={buttonRef}>
      <button 
        onClick={() => setIsOpen(!isOpen)} 
        className={`relative p-2.5 transition-all rounded-full ${isOpen ? 'bg-indigo-100 text-indigo-700' : 'text-gray-500 hover:bg-gray-100'}`}
      >
        <FaBell className="text-xl" />
        {totalUnreadCount > 0 && (
          <span className="absolute top-1 right-1 flex h-5 w-5 items-center justify-center rounded-full bg-red-600 text-[10px] font-black text-white ring-2 ring-white">
            {totalUnreadCount}
          </span>
        )}
      </button>

      <AnimatePresence>
        {isOpen && (
          <motion.div 
            initial={{ opacity: 0, x: 0, y: 20, scale: 0.9 }}
            animate={{ opacity: 1, x: 0, y: 0, scale: 1 }}
            exit={{ opacity: 0, x: 0, y: 20, scale: 0.9 }}
            onClick={(e) => e.stopPropagation()}
            /* Floating beautifully above the user profile */
            className="fixed left-4 bottom-20 w-[380px] bg-white rounded-3xl shadow-[0_25px_70px_rgba(0,0,0,0.25)] border border-gray-100 overflow-hidden z-[9999]"
            style={{ maxHeight: 'calc(100vh - 100px)' }}
          >
            {/* Header */}
            <div className="p-6 border-b border-gray-50 bg-white">
              <div className="flex items-center justify-between mb-5">
                <div>
                  <h3 className="text-xl font-black text-gray-900 tracking-tight">Notifications</h3>
                  <div className="flex items-center gap-2 mt-1">
                     <span className="w-1.5 h-1.5 rounded-full bg-indigo-500 animate-pulse"></span>
                     <p className="text-[11px] font-bold text-gray-400 uppercase tracking-widest">Real-time Activity Hub</p>
                  </div>
                </div>
                <button onClick={() => setIsOpen(false)} className="h-8 w-8 flex items-center justify-center rounded-full bg-gray-100 text-gray-400 hover:bg-gray-200 hover:text-gray-600 transition-all">
                  <FaTimes size={14} />
                </button>
              </div>

              {user?.role === 'admin' && (
                <div className="flex p-1.5 bg-gray-100 rounded-2xl">
                  <button 
                    onClick={() => setActiveTab('activity')}
                    className={`flex-1 flex items-center justify-center gap-2 py-2.5 text-xs font-black rounded-xl transition-all ${activeTab === 'activity' ? 'bg-white text-indigo-700 shadow-sm' : 'text-gray-500 hover:text-gray-800'}`}
                  >
                    Activity Feed
                  </button>
                  <button 
                    onClick={() => setActiveTab('alerts')}
                    className={`flex-1 flex items-center justify-center gap-2 py-2.5 text-xs font-black rounded-xl transition-all ${activeTab === 'alerts' ? 'bg-white text-indigo-700 shadow-sm' : 'text-gray-500 hover:text-gray-800'}`}
                  >
                    Alerts ({totalUnreadCount})
                  </button>
                </div>
              )}
            </div>

            {/* List */}
            <div className="overflow-y-auto scrollbar-hide bg-gray-50/50 p-4" style={{ height: '500px', maxHeight: '60vh' }}>
              {activeTab === 'activity' && user?.role === 'admin' ? (
                loading ? (
                  <div className="h-full flex flex-col items-center justify-center text-gray-400">
                    <div className="w-8 h-8 border-3 border-indigo-600 border-t-transparent rounded-full animate-spin mb-4"></div>
                    <p className="text-xs font-black uppercase tracking-widest">Refreshing Feed...</p>
                  </div>
                ) : activities.length > 0 ? (
                  <div className="space-y-3">
                    {activities.map(item => (
                      <div key={item.id} className="p-4 bg-white rounded-2xl border border-gray-100 shadow-sm hover:shadow-md transition-all group">
                        <div className="flex gap-4">
                          <div className="h-12 w-12 rounded-2xl bg-gray-50 flex items-center justify-center flex-shrink-0 group-hover:bg-indigo-50 transition-colors">
                            {item.icon}
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-start justify-between gap-2">
                              <p className="text-sm font-bold text-gray-900 leading-tight truncate">{item.title}</p>
                              {getStatusBadge(item.status)}
                            </div>
                            <p className="text-[11px] text-gray-500 mt-1 line-clamp-1">{item.detail}</p>
                            <div className="flex items-center gap-2 mt-2.5">
                               <p className="text-[10px] font-black text-indigo-400 uppercase tracking-tighter">
                                  {item.time ? formatDistanceToNow(new Date(item.time), { addSuffix: true }) : 'Just now'}
                               </p>
                            </div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="h-full flex flex-col items-center justify-center text-gray-400 opacity-50">
                    <FaInbox size={40} className="mb-4" />
                    <p className="font-black text-sm">Nothing to report today</p>
                  </div>
                )
              ) : (
                /* Alerts */
                unreadNotifications.length > 0 ? (
                  <div className="space-y-3">
                    {unreadNotifications.map(n => (
                      <div 
                        key={n.id} 
                        onClick={(e) => {
                          e.stopPropagation();
                          handleMarkAsRead(n);
                        }}
                        className="p-5 bg-white hover:bg-indigo-50/30 rounded-2xl cursor-pointer transition-all border-l-4 border-l-indigo-600 border border-gray-100 shadow-sm hover:shadow-md relative group"
                      >
                        <div className="flex gap-4">
                          <div className="h-12 w-12 rounded-2xl bg-indigo-100 text-indigo-600 flex items-center justify-center flex-shrink-0">
                             <FaBell className="animate-bounce" />
                          </div>
                          <div className="flex-1 min-w-0">
                            <p className="text-sm font-black text-gray-900 leading-tight">{n.title}</p>
                            <p className="text-xs text-gray-600 mt-1.5 line-clamp-2">{n.message}</p>
                            <p className="text-[10px] font-black text-indigo-400 mt-3 uppercase">
                              {n.createdAt ? formatDistanceToNow(parseISO(n.createdAt), { addSuffix: true }) : ''}
                            </p>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                ) : (
                  <div className="h-full flex flex-col items-center justify-center text-gray-400">
                    <div className="w-20 h-20 bg-green-50 rounded-full flex items-center justify-center mb-4">
                      <FaCheck className="text-green-500 text-2xl" />
                    </div>
                    <p className="text-sm font-black text-gray-900">Inbox is empty!</p>
                    <p className="text-[10px] uppercase font-bold tracking-widest mt-1">No new alerts to show</p>
                  </div>
                )
              )}
            </div>
            
            {/* Footer */}
            <div className="p-4 bg-white border-t border-gray-50 flex items-center justify-center">
               <span className="text-[10px] font-black text-gray-300 uppercase tracking-[0.2em]">O.S Travel & Tours HCM</span>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
