import { useState, useEffect } from 'react';
import { db } from '../firebase/config';
import { collection, query, where, getDocs, updateDoc, doc } from 'firebase/firestore';
import { useAuth } from '../hooks/useAuth';
import { TRAINING_STATUS } from '../constants/hcm';
import { FaGraduationCap, FaPlay, FaCheckCircle, FaBookOpen } from 'react-icons/fa';
import { motion } from 'framer-motion';

export default function MyLearning() {
  const { user } = useAuth();
  const [userTrainings, setUserTrainings] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (user) fetchMyLearning();
  }, [user]);

  const fetchMyLearning = async () => {
    setLoading(true);
    try {
      const q = query(
        collection(db, 'user_trainings'),
        where('userId', '==', user.uid)
      );
      const querySnapshot = await getDocs(q);
      setUserTrainings(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching learning:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleStartCourse = async (id) => {
    try {
      await updateDoc(doc(db, 'user_trainings', id), { status: 'in_progress', progress: 10 });
      fetchMyLearning();
    } catch (error) {
      console.error("Error starting course:", error);
    }
  };

  const handleCompleteCourse = async (id) => {
    try {
      await updateDoc(doc(db, 'user_trainings', id), { status: 'completed', progress: 100, completedAt: new Date().toISOString() });
      fetchMyLearning();
    } catch (error) {
      console.error("Error completing course:", error);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex items-center gap-4">
        <div className="h-12 w-12 bg-indigo-600 rounded-2xl flex items-center justify-center text-white text-xl shadow-lg shadow-indigo-100">
          <FaBookOpen />
        </div>
        <div>
          <h1 className="text-2xl font-bold text-gray-900">My Learning</h1>
          <p className="text-gray-500 text-sm">Grow your skills with assigned corporate training.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {loading ? (
          <div className="col-span-full text-center py-10 text-gray-500">Loading your courses...</div>
        ) : userTrainings.length === 0 ? (
          <div className="col-span-full py-20 bg-white rounded-3xl border border-dashed border-gray-200 text-center flex flex-col items-center">
            <FaGraduationCap className="text-4xl text-gray-200 mb-4" />
            <p className="text-gray-400">No training courses assigned yet.</p>
          </div>
        ) : userTrainings.map((ut) => (
          <motion.div 
            key={ut.id}
            className="bg-white p-6 rounded-3xl shadow-sm border border-gray-100 space-y-4 hover:shadow-md transition-all"
          >
            <div className="flex justify-between items-start">
              <span className={`px-2.5 py-1 rounded-lg text-[10px] font-bold uppercase tracking-wider ${TRAINING_STATUS.find(s => s.id === ut.status)?.color}`}>
                {TRAINING_STATUS.find(s => s.id === ut.status)?.label}
              </span>
              <span className="text-xs font-bold text-indigo-600">{ut.progress}%</span>
            </div>
            
            <h3 className="text-lg font-bold text-gray-900 leading-tight">{ut.trainingTitle}</h3>
            
            <div className="w-full bg-gray-100 rounded-full h-1.5 overflow-hidden">
              <div className="bg-indigo-600 h-full rounded-full transition-all duration-500" style={{ width: `${ut.progress}%` }}></div>
            </div>

            <div className="pt-4 flex gap-2">
              {ut.status === 'assigned' && (
                <button 
                  onClick={() => handleStartCourse(ut.id)}
                  className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-indigo-600 text-white rounded-xl text-xs font-bold shadow-md shadow-indigo-100"
                >
                  <FaPlay /> Start Learning
                </button>
              )}
              {ut.status === 'in_progress' && (
                <button 
                  onClick={() => handleCompleteCourse(ut.id)}
                  className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-green-600 text-white rounded-xl text-xs font-bold"
                >
                  <FaCheckCircle /> Mark Complete
                </button>
              )}
              {ut.status === 'completed' && (
                <div className="flex-1 flex items-center justify-center gap-2 py-2.5 bg-green-50 text-green-600 rounded-xl text-xs font-bold">
                  <FaCheckCircle /> Completed
                </div>
              )}
            </div>
          </motion.div>
        ))}
      </div>
    </div>
  );
}
