import { useState, useEffect } from 'react';
import { db } from '../firebase/config';
import { collection, query, where, getDocs, orderBy } from 'firebase/firestore';
import { useAuth } from '../hooks/useAuth';
import { FaStar, FaChartBar, FaQuoteLeft, FaCalendarAlt } from 'react-icons/fa';
import { motion } from 'framer-motion';

export default function Performance() {
  const { user } = useAuth();
  const [appraisals, setAppraisals] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (user) fetchMyPerformance();
  }, [user]);

  const fetchMyPerformance = async () => {
    setLoading(true);
    try {
      const q = query(
        collection(db, 'appraisals'),
        where('userId', '==', user.uid),
        orderBy('createdAt', 'desc')
      );
      const querySnapshot = await getDocs(q);
      setAppraisals(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching performance:", error);
    } finally {
      setLoading(false);
    }
  };

  // Note: I made a typo in the variable name 'setPayslips' instead of 'setAppraisals' above. Fixing it in the final code.
  // Actually, I'll just rewrite the fetch logic properly in the file content.

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">My Performance</h1>
        <p className="text-gray-500 text-sm">Track your KPIs, ratings, and feedback from management.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 space-y-6">
          {loading ? (
            <div className="text-center py-20 text-gray-500">Loading your performance history...</div>
          ) : appraisals.length === 0 ? (
            <div className="bg-white p-10 rounded-3xl border border-dashed border-gray-200 text-center text-gray-400">
              No performance reviews found yet.
            </div>
          ) : appraisals.map((app) => (
            <motion.div 
              key={app.id}
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              className="bg-white p-8 rounded-3xl shadow-sm border border-gray-100 space-y-6"
            >
              <div className="flex justify-between items-start">
                <div className="flex items-center gap-2 text-yellow-400">
                  {[...Array(5)].map((_, i) => (
                    <FaStar key={i} className={i < app.rating ? 'text-yellow-400' : 'text-gray-100'} />
                  ))}
                  <span className="ml-2 text-sm font-bold text-gray-900">{app.rating}/5 Rating</span>
                </div>
                <div className="flex items-center text-gray-400 text-xs font-medium">
                  <FaCalendarAlt className="mr-1.5" /> {new Date(app.createdAt).toLocaleDateString()}
                </div>
              </div>

              <div className="bg-gray-50 p-6 rounded-2xl relative">
                <FaQuoteLeft className="absolute top-4 left-4 text-gray-200 text-2xl" />
                <p className="text-gray-700 italic leading-relaxed pl-6">{app.feedback}</p>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                {app.kpis.map((kpi, idx) => (
                  <div key={idx} className="space-y-2">
                    <div className="flex justify-between text-xs font-bold text-gray-500 uppercase tracking-widest">
                      <span>{kpi.name}</span>
                      <span>{kpi.score}%</span>
                    </div>
                    <div className="w-full bg-gray-100 rounded-full h-2 overflow-hidden">
                      <motion.div 
                        initial={{ width: 0 }}
                        animate={{ width: `${kpi.score}%` }}
                        className="bg-indigo-600 h-2 rounded-full"
                      />
                    </div>
                  </div>
                ))}
              </div>
            </motion.div>
          ))}
        </div>

        <div className="space-y-6">
          <div className="bg-indigo-600 p-8 rounded-3xl text-white shadow-xl shadow-indigo-100">
            <FaChartBar className="text-4xl mb-4 opacity-50" />
            <h3 className="text-xl font-bold mb-2">Growth Tracker</h3>
            <p className="text-indigo-100 text-sm leading-relaxed">
              Your performance is monitored periodically to help you achieve your career goals. Maintain high KPI scores for better appraisal results.
            </p>
          </div>
          <div className="bg-white p-8 rounded-3xl border border-gray-100 shadow-sm">
            <h4 className="text-sm font-bold text-gray-900 uppercase tracking-widest mb-6">Performance Tips</h4>
            <ul className="space-y-4">
              {[
                'Ensure punctuality in all tasks.',
                'Collaborate effectively with team members.',
                'Meet your weekly KPI targets.',
                'Engage in training programs.'
              ].map((tip, i) => (
                <li key={i} className="flex items-start text-sm text-gray-600">
                  <span className="h-5 w-5 bg-green-50 text-green-600 rounded-full flex-shrink-0 flex items-center justify-center mr-3 text-[10px] font-bold">
                    {i+1}
                  </span>
                  {tip}
                </li>
              ))}
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
