import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, addDoc, query, where, orderBy } from 'firebase/firestore';
import { FaStar, FaTrophy, FaSearch, FaExclamationTriangle, FaClock, FaCalendarCheck } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function PerformanceManagement() {
  const [employees, setEmployees] = useState([]);
  const [appraisals, setAppraisals] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [selectedEmp, setSelectedEmp] = useState(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [formData, setFormData] = useState({
    rating: 3,
    feedback: '',
    kpis: [{ name: 'Quality of Work', score: 80 }, { name: 'Punctuality', score: 90 }, { name: 'Teamwork', score: 85 }]
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      const empSnapshot = await getDocs(collection(db, 'users'));
      const attSnapshot = await getDocs(collection(db, 'attendance'));
      const docSnapshot = await getDocs(query(collection(db, 'documents'), where('type', '==', 'warning')));
      const appSnapshot = await getDocs(collection(db, 'appraisals'));
      
      const attData = attSnapshot.docs.map(doc => doc.data());
      const warnData = docSnapshot.docs.map(doc => doc.data());
      
      setAppraisals(appSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));

      const employeesData = empSnapshot.docs
        .map(doc => ({ id: doc.id, ...doc.data() }))
        .filter(e => e.role !== 'admin')
        .map(emp => {
          const empAtt = attData.filter(a => a.userId === emp.id);
          const empWarnings = warnData.filter(w => w.userId === emp.id).length;
          
          const presentDays = empAtt.length;
          const lateDays = empAtt.filter(a => a.status === 'Late').length;
          const onTimeDays = presentDays - lateDays;
          
          // insideOfficeTime is usually in ms
          const totalHours = empAtt.reduce((sum, a) => sum + (a.insideOfficeTime || 0), 0) / (1000 * 60 * 60);
          
          // Dynamic Score Calculation (Max 100)
          let score = 50 + (onTimeDays * 1.5) - (lateDays * 5) - (empWarnings * 20) + (totalHours * 0.1);
          score = Math.max(0, Math.min(100, Math.round(score)));

          return { 
            ...emp, 
            presentDays, 
            lateDays, 
            onTimeDays, 
            totalHours: Math.round(totalHours), 
            warnings: empWarnings, 
            score 
          };
        })
        .sort((a, b) => b.score - a.score);

      setEmployees(employeesData);
    } catch (error) {
      console.error("Error fetching performance data:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleAppraisal = async (e) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await addDoc(collection(db, 'appraisals'), {
        userId: selectedEmp.id,
        userName: selectedEmp.name,
        ...formData,
        createdAt: new Date().toISOString()
      });
      setIsModalOpen(false);
      setFormData({ rating: 3, feedback: '', kpis: [{ name: 'Quality of Work', score: 80 }, { name: 'Punctuality', score: 90 }, { name: 'Teamwork', score: 85 }] });
      fetchData();
    } catch (error) {
      console.error("Error submitting appraisal:", error);
    } finally {
      setIsSaving(false);
    }
  };

  const filteredEmployees = employees.filter(emp => 
    emp.name?.toLowerCase().includes(search.toLowerCase()) || 
    emp.email?.toLowerCase().includes(search.toLowerCase())
  );

  const topPerformers = filteredEmployees.slice(0, 3);
  const otherEmployees = filteredEmployees.slice(3);

  return (
    <div className="space-y-8 pb-10">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Performance Management</h1>
          <p className="text-gray-500 text-sm mt-1">Data-driven performance metrics based on attendance, time, and conduct.</p>
        </div>
        <div className="relative w-full md:w-72">
          <FaSearch className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-400" />
          <input 
            type="text" 
            placeholder="Search employee..."
            className="w-full pl-10 pr-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500 text-sm shadow-sm"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </div>
      </div>

      {loading ? (
        <div className="text-center py-16 text-gray-500">
          <div className="w-8 h-8 border-4 border-indigo-200 border-t-indigo-600 rounded-full animate-spin mx-auto mb-3"></div>
          Calculating performance scores...
        </div>
      ) : (
        <>
          {/* Top Performers Podium */}
          {topPerformers.length > 0 && (
            <div>
              <h2 className="text-sm font-bold text-gray-900 uppercase tracking-wider mb-4 flex items-center gap-2">
                <FaTrophy className="text-yellow-500" /> Top Performers
              </h2>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
                {topPerformers.map((emp, idx) => {
                  const rankColors = ['text-yellow-500', 'text-gray-400', 'text-amber-600'];
                  const rankBgs = ['bg-yellow-400', 'bg-gray-400', 'bg-amber-500'];
                  const rankBorder = ['border-yellow-400', 'border-gray-400', 'border-amber-500'];
                  const currentMonth = new Date().toISOString().substring(0, 7);
                  const appraisedThisMonth = appraisals.some(a => a.userId === emp.id && a.createdAt?.startsWith(currentMonth));

                  return (
                    <motion.div 
                      initial={{ opacity: 0, y: 20 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: idx * 0.1 }}
                      key={emp.id} 
                      className="relative bg-white rounded-2xl p-6 shadow-[0_4px_20px_rgba(0,0,0,0.04)] border border-gray-100 flex flex-col items-center text-center overflow-hidden group hover:shadow-lg transition-all"
                    >
                      <div className={`absolute top-0 left-0 w-full h-1.5 ${rankBgs[idx]}`}></div>
                      
                      <div className="relative mb-4 mt-2">
                        <div className={`relative z-10 w-20 h-20 rounded-full border-4 ${rankBorder[idx]} shadow-md overflow-hidden bg-white`}>
                           <img src={emp.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(emp.name || 'U')}&background=e0e7ff&color=4f46e5`} alt="" className="w-full h-full object-cover" />
                        </div>
                        <div className={`absolute -bottom-2 -right-2 w-8 h-8 rounded-full flex items-center justify-center text-white text-xs font-black shadow-sm z-20 ${rankBgs[idx]} border-2 border-white`}>
                          #{idx + 1}
                        </div>
                      </div>
                      
                      <h3 className="font-bold text-gray-900 text-lg group-hover:text-indigo-600 transition-colors">{emp.name}</h3>
                      <p className="text-xs text-gray-500 mb-6">{emp.designation || 'Staff'} • {emp.department || 'General'}</p>

                      {/* Circular Progress */}
                      <div className="relative flex items-center justify-center mb-6">
                        <svg width="100" height="100" className="transform -rotate-90">
                          <circle cx="50" cy="50" r="42" stroke="currentColor" strokeWidth="8" fill="transparent" className="text-gray-50" />
                          <circle 
                            cx="50" cy="50" r="42" 
                            stroke="currentColor" strokeWidth="8" fill="transparent" 
                            strokeDasharray={42 * 2 * Math.PI} 
                            strokeDashoffset={(42 * 2 * Math.PI) - (emp.score / 100) * (42 * 2 * Math.PI)} 
                            className={`${rankColors[idx]} transition-all duration-1000 ease-out`} 
                            strokeLinecap="round" 
                          />
                        </svg>
                        <div className="absolute flex flex-col items-center justify-center">
                          <span className="text-2xl font-black text-gray-800">{emp.score}</span>
                          <span className="text-[8px] text-gray-400 font-bold uppercase tracking-widest mt-0.5">Score</span>
                        </div>
                      </div>

                      <div className="grid grid-cols-2 gap-3 w-full">
                        <div className="bg-gray-50 rounded-xl p-2.5 text-center border border-gray-100">
                          <FaCalendarCheck className="mx-auto text-green-500 mb-1 text-sm" />
                          <p className="text-[9px] text-gray-400 font-bold uppercase mb-0.5">On Time</p>
                          <p className="text-sm font-bold text-gray-800">{emp.onTimeDays} <span className="text-[10px] font-normal text-gray-500">days</span></p>
                        </div>
                        <div className="bg-gray-50 rounded-xl p-2.5 text-center border border-gray-100">
                          <FaClock className="mx-auto text-indigo-500 mb-1 text-sm" />
                          <p className="text-[9px] text-gray-400 font-bold uppercase mb-0.5">Office Time</p>
                          <p className="text-sm font-bold text-gray-800">{emp.totalHours} <span className="text-[10px] font-normal text-gray-500">hrs</span></p>
                        </div>
                        <div className="bg-gray-50 rounded-xl p-2.5 text-center border border-gray-100">
                          <FaExclamationTriangle className="mx-auto text-amber-500 mb-1 text-sm" />
                          <p className="text-[9px] text-gray-400 font-bold uppercase mb-0.5">Lates</p>
                          <p className="text-sm font-bold text-gray-800">{emp.lateDays}</p>
                        </div>
                        <div className="bg-gray-50 rounded-xl p-2.5 text-center border border-gray-100">
                          <FaStar className="mx-auto text-red-400 mb-1 text-sm" />
                          <p className="text-[9px] text-gray-400 font-bold uppercase mb-0.5">Warnings</p>
                          <p className={`text-sm font-bold ${emp.warnings > 0 ? 'text-red-500' : 'text-gray-800'}`}>{emp.warnings}</p>
                        </div>
                      </div>
                      
                      {appraisedThisMonth ? (
                        <div className="w-full mt-5 py-2.5 bg-green-50 text-green-700 rounded-xl text-xs font-bold text-center border border-green-200 cursor-default">
                          ✓ Appraised this month
                        </div>
                      ) : (
                        <button 
                          onClick={() => { setSelectedEmp(emp); setIsModalOpen(true); }}
                          className="w-full mt-5 py-2.5 bg-gray-900 text-white rounded-xl text-xs font-bold hover:bg-gray-800 transition-colors"
                        >
                          Appraise
                        </button>
                      )}
                    </motion.div>
                  )
                })}
              </div>
            </div>
          )}

          {/* All Other Employees */}
          {otherEmployees.length > 0 && (
            <div>
              <h2 className="text-sm font-bold text-gray-900 uppercase tracking-wider mb-4 mt-8 border-t border-gray-200 pt-8">
                General Workforce Performance
              </h2>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
                {otherEmployees.map(emp => {
                  const currentMonth = new Date().toISOString().substring(0, 7);
                  const appraisedThisMonth = appraisals.some(a => a.userId === emp.id && a.createdAt?.startsWith(currentMonth));
                  
                  return (
                    <div key={emp.id} className="bg-white border border-gray-200 rounded-xl p-4 shadow-sm hover:shadow-md hover:border-indigo-300 transition-all flex flex-col group">
                    <div className="flex items-center gap-3 mb-4">
                      <img src={emp.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(emp.name || 'U')}&background=e0e7ff&color=4f46e5`} className="w-10 h-10 rounded-full border border-gray-100" alt="" />
                      <div className="flex-1 min-w-0">
                        <h4 className="font-bold text-gray-900 text-sm truncate group-hover:text-indigo-600 transition-colors">{emp.name}</h4>
                        <p className="text-[10px] text-gray-500 truncate">{emp.designation || 'Staff'}</p>
                      </div>
                      <div className="ml-auto bg-indigo-50 text-indigo-700 px-2 py-1 rounded-lg text-xs font-black shadow-sm">
                        {emp.score} pt
                      </div>
                    </div>
                    
                    <div className="space-y-2.5 mb-4 bg-gray-50 p-3 rounded-lg border border-gray-100">
                      <div className="flex justify-between items-center text-xs">
                        <span className="text-gray-500 font-medium flex items-center gap-1.5"><FaCalendarCheck className="text-green-500"/> On Time</span>
                        <span className="font-bold text-gray-800">{emp.onTimeDays} d</span>
                      </div>
                      <div className="flex justify-between items-center text-xs">
                        <span className="text-gray-500 font-medium flex items-center gap-1.5"><FaClock className="text-indigo-500"/> Hrs</span>
                        <span className="font-bold text-gray-800">{emp.totalHours} h</span>
                      </div>
                      <div className="flex justify-between items-center text-xs">
                        <span className="text-gray-500 font-medium flex items-center gap-1.5"><FaExclamationTriangle className="text-amber-500"/> Lates</span>
                        <span className="font-bold text-amber-600">{emp.lateDays}</span>
                      </div>
                      <div className="flex justify-between items-center text-xs">
                        <span className="text-gray-500 font-medium flex items-center gap-1.5"><FaStar className="text-red-400"/> Warnings</span>
                        <span className={`font-bold ${emp.warnings > 0 ? 'text-red-500' : 'text-green-500'}`}>{emp.warnings}</span>
                      </div>
                    </div>
                    
                    {appraisedThisMonth ? (
                      <div className="w-full mt-auto py-2 bg-green-50 text-green-700 rounded-lg text-xs font-bold text-center border border-green-100 cursor-default">
                        ✓ Appraised this month
                      </div>
                    ) : (
                      <button 
                        onClick={() => { setSelectedEmp(emp); setIsModalOpen(true); }}
                        className="w-full mt-auto py-2 bg-white border border-gray-200 hover:border-indigo-600 hover:bg-indigo-50 hover:text-indigo-700 text-gray-700 rounded-lg text-xs font-bold transition-all shadow-sm"
                      >
                        Appraise Employee
                      </button>
                    )}
                  </div>
                )})}
              </div>
            </div>
          )}
        </>
      )}

      {/* Appraisal Modal */}
      <AnimatePresence>
        {isModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="bg-white rounded-2xl shadow-2xl w-full max-w-xl overflow-hidden flex flex-col max-h-[90vh]"
            >
              <form onSubmit={handleAppraisal} className="flex flex-col h-full">
                <div className="px-6 py-5 border-b border-gray-100 flex items-center justify-between bg-gradient-to-r from-indigo-50 to-white">
                  <div>
                    <h2 className="text-xl font-bold text-gray-900">Conduct Appraisal</h2>
                    <p className="text-xs text-gray-500 mt-1">For <span className="font-semibold">{selectedEmp.name}</span> (Score: {selectedEmp.score})</p>
                  </div>
                  <button type="button" onClick={() => setIsModalOpen(false)} className="text-gray-400 hover:text-gray-600 bg-white p-2 rounded-full shadow-sm">✕</button>
                </div>
                
                <div className="p-6 space-y-6 overflow-y-auto flex-1">
                  <div className="space-y-3">
                    <label className="text-sm font-bold text-gray-800 uppercase tracking-wide">Overall Manual Rating</label>
                    <div className="flex gap-3">
                      {[1, 2, 3, 4, 5].map((num) => (
                        <button
                          key={num}
                          type="button"
                          onClick={() => setFormData({...formData, rating: num})}
                          className={`flex-1 py-3 rounded-xl transition-all border ${
                            formData.rating >= num 
                            ? 'bg-yellow-50 border-yellow-200 text-yellow-500 shadow-inner' 
                            : 'bg-white border-gray-200 text-gray-200 hover:border-yellow-200 hover:text-yellow-300'
                          }`}
                        >
                          <FaStar className="text-xl mx-auto" />
                        </button>
                      ))}
                    </div>
                  </div>
                  
                  <div className="space-y-5 bg-gray-50 p-4 rounded-xl border border-gray-100">
                    <label className="text-sm font-bold text-gray-800 uppercase tracking-wide">Key Performance Indicators</label>
                    {formData.kpis.map((kpi, idx) => (
                      <div key={idx} className="space-y-2">
                        <div className="flex justify-between text-xs font-bold text-gray-600">
                          <span>{kpi.name}</span>
                          <span className="text-indigo-600 bg-indigo-50 px-2 py-0.5 rounded">{kpi.score}%</span>
                        </div>
                        <input 
                          type="range" 
                          className="w-full h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer accent-indigo-600"
                          value={kpi.score}
                          onChange={(e) => {
                            const newKpis = [...formData.kpis];
                            newKpis[idx].score = Number(e.target.value);
                            setFormData({...formData, kpis: newKpis});
                          }}
                        />
                      </div>
                    ))}
                  </div>

                  <div className="space-y-2">
                    <label className="text-sm font-bold text-gray-800 uppercase tracking-wide">Manager's Feedback</label>
                    <textarea 
                      rows="4"
                      className="w-full px-4 py-3 border border-gray-200 rounded-xl outline-none focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 text-sm shadow-sm transition-shadow"
                      placeholder="Write detailed qualitative feedback on employee performance..."
                      value={formData.feedback}
                      onChange={(e) => setFormData({...formData, feedback: e.target.value})}
                      required
                    ></textarea>
                  </div>
                </div>
                
                <div className="px-6 py-4 bg-gray-50 border-t border-gray-100 flex justify-end gap-3">
                  <button type="button" onClick={() => setIsModalOpen(false)} className="px-5 py-2 text-sm font-bold text-gray-600 hover:bg-gray-200 rounded-lg transition-colors">Cancel</button>
                  <button type="submit" disabled={isSaving} className="px-6 py-2 bg-indigo-600 text-white rounded-lg font-bold text-sm shadow-md hover:bg-indigo-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed">
                    {isSaving ? 'Saving...' : 'Submit Review'}
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
