import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, addDoc, doc, updateDoc, query, orderBy } from 'firebase/firestore';
import { TRAINING_LEVELS, DEPARTMENTS } from '../../constants/hcm';
import { FaGraduationCap, FaPlus, FaUsers, FaClock, FaSearch } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function TrainingManagement() {
  const [trainings, setTrainings] = useState([]);
  const [employees, setEmployees] = useState([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [assignModalOpen, setAssignModalOpen] = useState(false);
  const [selectedTraining, setSelectedTraining] = useState(null);
  const [formData, setFormData] = useState({
    title: '',
    description: '',
    level: 'Beginner',
    duration: '',
    department: 'Engineering'
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      const tSnapshot = await getDocs(query(collection(db, 'trainings'), orderBy('createdAt', 'desc')));
      setTrainings(tSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
      
      const eSnapshot = await getDocs(collection(db, 'users'));
      setEmployees(eSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })).filter(e => e.role !== 'admin'));
    } catch (error) {
      console.error("Error fetching training data:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleCreateTraining = async (e) => {
    e.preventDefault();
    try {
      await addDoc(collection(db, 'trainings'), {
        ...formData,
        createdAt: new Date().toISOString()
      });
      setIsModalOpen(false);
      fetchData();
    } catch (error) {
      console.error("Error creating training:", error);
    }
  };

  const handleAssignTraining = async (empId, empName) => {
    try {
      await addDoc(collection(db, 'user_trainings'), {
        trainingId: selectedTraining.id,
        trainingTitle: selectedTraining.title,
        userId: empId,
        userName: empName,
        status: 'assigned',
        progress: 0,
        assignedAt: new Date().toISOString()
      });
      alert(`Assigned to ${empName}`);
    } catch (error) {
      console.error("Error assigning training:", error);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Training & Development</h1>
          <p className="text-gray-500 text-sm">Create courses and assign them to your team.</p>
        </div>
        <button 
          onClick={() => setIsModalOpen(true)}
          className="flex items-center justify-center px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 shadow-sm text-sm font-medium"
        >
          <FaPlus className="mr-2" /> Create Course
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {loading ? (
          <div className="col-span-full text-center py-10 text-gray-500">Loading training modules...</div>
        ) : trainings.map((t) => (
          <motion.div 
            key={t.id}
            className="bg-white p-6 rounded-2xl shadow-sm border border-gray-100 flex flex-col justify-between hover:shadow-md transition-all"
          >
            <div className="space-y-4">
              <div className="flex justify-between items-start">
                <div className="p-3 bg-purple-50 rounded-xl text-purple-600">
                  <FaGraduationCap className="text-2xl" />
                </div>
                <span className="px-2.5 py-0.5 bg-gray-100 text-gray-600 rounded-full text-[10px] font-bold uppercase tracking-widest">
                  {t.level}
                </span>
              </div>
              <div>
                <h3 className="text-lg font-bold text-gray-900">{t.title}</h3>
                <p className="text-xs text-indigo-600 font-medium">{t.department}</p>
              </div>
              <p className="text-sm text-gray-500 line-clamp-2">{t.description}</p>
              <div className="flex items-center text-xs text-gray-400 gap-4">
                <span className="flex items-center"><FaClock className="mr-1" /> {t.duration}</span>
              </div>
            </div>
            <div className="pt-6 mt-6 border-t border-gray-50">
              <button 
                onClick={() => { setSelectedTraining(t); setAssignModalOpen(true); }}
                className="w-full flex items-center justify-center gap-2 py-2 bg-indigo-50 text-indigo-600 rounded-lg text-xs font-bold hover:bg-indigo-100"
              >
                <FaUsers /> Assign to Employees
              </button>
            </div>
          </motion.div>
        ))}
      </div>

      {/* Create Course Modal */}
      <AnimatePresence>
        {isModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white rounded-2xl shadow-2xl w-full max-w-lg overflow-hidden"
            >
              <form onSubmit={handleCreateTraining}>
                <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
                  <h2 className="text-xl font-bold text-gray-900">Create New Training Course</h2>
                  <button type="button" onClick={() => setIsModalOpen(false)} className="text-gray-400">✕</button>
                </div>
                <div className="p-6 space-y-4">
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Course Title</label>
                    <input 
                      type="text" 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={formData.title}
                      onChange={(e) => setFormData({...formData, title: e.target.value})}
                      required
                    />
                  </div>
                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-1">
                      <label className="text-sm font-semibold text-gray-700">Level</label>
                      <select 
                        className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                        value={formData.level}
                        onChange={(e) => setFormData({...formData, level: e.target.value})}
                        required
                      >
                        {TRAINING_LEVELS.map(l => <option key={l} value={l}>{l}</option>)}
                      </select>
                    </div>
                    <div className="space-y-1">
                      <label className="text-sm font-semibold text-gray-700">Department</label>
                      <select 
                        className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                        value={formData.department}
                        onChange={(e) => setFormData({...formData, department: e.target.value})}
                        required
                      >
                        {DEPARTMENTS.map(d => <option key={d} value={d}>{d}</option>)}
                      </select>
                    </div>
                  </div>
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Duration (e.g. 4 Hours)</label>
                    <input 
                      type="text" 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={formData.duration}
                      onChange={(e) => setFormData({...formData, duration: e.target.value})}
                      required
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Description</label>
                    <textarea 
                      rows="3"
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={formData.description}
                      onChange={(e) => setFormData({...formData, description: e.target.value})}
                      required
                    ></textarea>
                  </div>
                </div>
                <div className="px-6 py-4 bg-gray-50 border-t border-gray-100 flex justify-end gap-3">
                  <button type="button" onClick={() => setIsModalOpen(false)} className="px-4 py-2 text-sm font-semibold text-gray-600">Cancel</button>
                  <button type="submit" className="px-6 py-2 bg-indigo-600 text-white rounded-lg font-semibold text-sm shadow-md">Create Course</button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>

      {/* Assign Modal */}
      <AnimatePresence>
        {assignModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden"
            >
              <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
                <h2 className="text-xl font-bold text-gray-900">Assign Training</h2>
                <button type="button" onClick={() => setAssignModalOpen(false)} className="text-gray-400">✕</button>
              </div>
              <div className="p-6 max-h-[60vh] overflow-y-auto space-y-2">
                {employees.map(emp => (
                  <div key={emp.id} className="flex items-center justify-between p-3 hover:bg-gray-50 rounded-xl transition-colors">
                    <div>
                      <p className="text-sm font-semibold text-gray-900">{emp.name}</p>
                      <p className="text-xs text-gray-500">{emp.department}</p>
                    </div>
                    <button 
                      onClick={() => handleAssignTraining(emp.id, emp.name)}
                      className="px-3 py-1 bg-indigo-600 text-white rounded-lg text-xs font-bold"
                    >
                      Assign
                    </button>
                  </div>
                ))}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
