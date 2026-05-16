import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, doc, updateDoc, addDoc, query, orderBy } from 'firebase/firestore';
import { JOB_STAGES } from '../../constants/hcm';
import { FaUserTie, FaPhone, FaEnvelope, FaEllipsisV, FaPlus } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function CandidateTracking() {
  const [candidates, setCandidates] = useState([]);
  const [loading, setLoading] = useState(true);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [newCandidate, setNewCandidate] = useState({
    name: '',
    email: '',
    phone: '',
    position: '',
    stage: 'applied'
  });

  useEffect(() => {
    fetchCandidates();
  }, []);

  const fetchCandidates = async () => {
    setLoading(true);
    try {
      const q = query(collection(db, 'candidates'), orderBy('createdAt', 'desc'));
      const querySnapshot = await getDocs(q);
      setCandidates(querySnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching candidates:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleUpdateStage = async (id, newStage) => {
    try {
      await updateDoc(doc(db, 'candidates', id), { stage: newStage });
      fetchCandidates();
    } catch (error) {
      console.error("Error updating candidate stage:", error);
    }
  };

  const handleAddCandidate = async (e) => {
    e.preventDefault();
    try {
      await addDoc(collection(db, 'candidates'), {
        ...newCandidate,
        createdAt: new Date().toISOString()
      });
      setIsModalOpen(false);
      fetchCandidates();
      setNewCandidate({ name: '', email: '', phone: '', position: '', stage: 'applied' });
    } catch (error) {
      console.error("Error adding candidate:", error);
    }
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Candidate Tracking</h1>
          <p className="text-gray-500 text-sm">Manage applicants and track their progress through the hiring pipeline.</p>
        </div>
        <button 
          onClick={() => setIsModalOpen(true)}
          className="flex items-center justify-center px-4 py-2 bg-indigo-600 text-white rounded-lg hover:bg-indigo-700 shadow-sm text-sm font-medium"
        >
          <FaPlus className="mr-2" /> Add Candidate
        </button>
      </div>

      <div className="flex gap-6 overflow-x-auto pb-6 min-h-[600px]">
        {JOB_STAGES.map((stage) => (
          <div key={stage.id} className="flex-shrink-0 w-80 space-y-4">
            <div className={`px-4 py-2 rounded-lg ${stage.color} flex justify-between items-center`}>
              <span className="text-sm font-bold uppercase tracking-wider">{stage.label}</span>
              <span className="bg-white/50 px-2 py-0.5 rounded text-xs font-bold">
                {candidates.filter(c => c.stage === stage.id).length}
              </span>
            </div>
            
            <div className="space-y-3">
              {candidates.filter(c => c.stage === stage.id).map((candidate) => (
                <motion.div 
                  key={candidate.id}
                  layoutId={candidate.id}
                  className="bg-white p-4 rounded-xl shadow-sm border border-gray-100 space-y-3 group"
                >
                  <div className="flex justify-between items-start">
                    <div className="h-10 w-10 bg-indigo-50 rounded-lg flex items-center justify-center text-indigo-600">
                      <FaUserTie className="text-xl" />
                    </div>
                    <select 
                      className="text-xs border-none bg-gray-50 rounded px-2 py-1 outline-none focus:ring-1 focus:ring-indigo-500"
                      value={candidate.stage}
                      onChange={(e) => handleUpdateStage(candidate.id, e.target.value)}
                    >
                      {JOB_STAGES.map(s => <option key={s.id} value={s.id}>{s.label}</option>)}
                    </select>
                  </div>
                  <div>
                    <h4 className="text-sm font-bold text-gray-900">{candidate.name}</h4>
                    <p className="text-xs text-indigo-600 font-medium">{candidate.position}</p>
                  </div>
                  <div className="space-y-1">
                    <div className="flex items-center text-[10px] text-gray-400">
                      <FaEnvelope className="mr-1.5" /> {candidate.email}
                    </div>
                    <div className="flex items-center text-[10px] text-gray-400">
                      <FaPhone className="mr-1.5" /> {candidate.phone}
                    </div>
                  </div>
                </motion.div>
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Add Candidate Modal */}
      <AnimatePresence>
        {isModalOpen && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
            <motion.div
              initial={{ opacity: 0, scale: 0.95 }}
              animate={{ opacity: 1, scale: 1 }}
              exit={{ opacity: 0, scale: 0.95 }}
              className="bg-white rounded-2xl shadow-2xl w-full max-w-md overflow-hidden"
            >
              <form onSubmit={handleAddCandidate}>
                <div className="px-6 py-4 border-b border-gray-100 flex items-center justify-between">
                  <h2 className="text-xl font-bold text-gray-900">Add New Candidate</h2>
                  <button type="button" onClick={() => setIsModalOpen(false)} className="text-gray-400">✕</button>
                </div>
                <div className="p-6 space-y-4">
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Full Name</label>
                    <input 
                      type="text" 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={newCandidate.name}
                      onChange={(e) => setNewCandidate({...newCandidate, name: e.target.value})}
                      required
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Email Address</label>
                    <input 
                      type="email" 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={newCandidate.email}
                      onChange={(e) => setNewCandidate({...newCandidate, email: e.target.value})}
                      required
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Phone Number</label>
                    <input 
                      type="tel" 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      value={newCandidate.phone}
                      onChange={(e) => setNewCandidate({...newCandidate, phone: e.target.value})}
                      required
                    />
                  </div>
                  <div className="space-y-1">
                    <label className="text-sm font-semibold text-gray-700">Applying For</label>
                    <input 
                      type="text" 
                      className="w-full px-4 py-2 border border-gray-200 rounded-lg outline-none focus:ring-2 focus:ring-indigo-500"
                      placeholder="e.g. Senior Frontend Engineer"
                      value={newCandidate.position}
                      onChange={(e) => setNewCandidate({...newCandidate, position: e.target.value})}
                      required
                    />
                  </div>
                </div>
                <div className="px-6 py-4 bg-gray-50 border-t border-gray-100 flex justify-end gap-3">
                  <button type="button" onClick={() => setIsModalOpen(false)} className="px-4 py-2 text-sm font-semibold text-gray-600">Cancel</button>
                  <button type="submit" className="px-6 py-2 bg-indigo-600 text-white rounded-lg font-semibold text-sm shadow-md">Add Candidate</button>
                </div>
              </form>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
