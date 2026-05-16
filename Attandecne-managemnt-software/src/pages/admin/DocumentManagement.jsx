import { useState, useEffect } from 'react';
import { db } from '../../firebase/config';
import { collection, getDocs, addDoc, query, orderBy } from 'firebase/firestore';
import { DOCUMENT_TYPES } from '../../constants/hcm';
import { FaFileAlt, FaSearch, FaExclamationTriangle, FaPenFancy, FaTimes } from 'react-icons/fa';
import { motion, AnimatePresence } from 'framer-motion';

export default function DocumentManagement() {
  const [employees, setEmployees] = useState([]);
  const [documents, setDocuments] = useState([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  
  const [selectedEmp, setSelectedEmp] = useState(null);
  const [isModalOpen, setIsModalOpen] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [activeTab, setActiveTab] = useState('new'); // 'new' | 'history'
  const [selectedDocPreview, setSelectedDocPreview] = useState(null);
  
  const [formData, setFormData] = useState({
    type: 'offer_letter',
    companyName: 'Core Flow HCM',
    date: new Date().toISOString().substring(0, 10),
    subject: '',
    content: '',
    issuerName: 'HR Department'
  });

  useEffect(() => {
    fetchData();
  }, []);

  const fetchData = async () => {
    setLoading(true);
    try {
      const empSnapshot = await getDocs(collection(db, 'users'));
      setEmployees(empSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })).filter(e => e.role !== 'admin'));
      
      const docSnapshot = await getDocs(query(collection(db, 'documents'), orderBy('createdAt', 'desc')));
      setDocuments(docSnapshot.docs.map(doc => ({ id: doc.id, ...doc.data() })));
    } catch (error) {
      console.error("Error fetching document data:", error);
    } finally {
      setLoading(false);
    }
  };

  const handleGenerateDocument = async (e) => {
    e.preventDefault();
    setIsSaving(true);
    try {
      await addDoc(collection(db, 'documents'), {
        userId: selectedEmp.id,
        userName: selectedEmp.name,
        ...formData,
        status: 'issued',
        createdAt: new Date().toISOString()
      });
      setIsModalOpen(false);
      setFormData({
        type: 'offer_letter',
        companyName: 'Core Flow HCM',
        date: new Date().toISOString().substring(0, 10),
        subject: '',
        content: '',
        issuerName: 'HR Department'
      });
      fetchData();
    } catch (error) {
      console.error("Error generating document:", error);
    } finally {
      setIsSaving(false);
    }
  };

  const filteredEmployees = employees.filter(emp => emp.name?.toLowerCase().includes(search.toLowerCase()));

  return (
    <div className="space-y-6 pb-12">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">HR Documents</h1>
          <p className="text-gray-500 text-sm mt-1">Issue official company documents directly to employee records.</p>
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
          Loading document records...
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-6">
          {filteredEmployees.map(emp => {
            const empDocs = documents.filter(d => d.userId === emp.id);
            const warnings = empDocs.filter(d => d.type === 'warning');

            return (
              <div 
                key={emp.id} 
                onClick={() => { setSelectedEmp(emp); setIsModalOpen(true); }}
                className="bg-white rounded-2xl shadow-[0_2px_10px_rgba(0,0,0,0.04)] border border-gray-200 hover:border-indigo-300 hover:shadow-lg transition-all cursor-pointer flex flex-col group relative overflow-hidden"
              >
                <div className="p-5 flex flex-col gap-4 relative z-10">
                  <div className="flex items-center gap-4">
                    <img 
                      src={emp.photoURL || `https://ui-avatars.com/api/?name=${encodeURIComponent(emp.name || 'U')}&background=e0e7ff&color=4f46e5`} 
                      className="w-14 h-14 rounded-full border-2 border-gray-100 group-hover:border-indigo-200 transition-colors object-cover" 
                      alt=""
                    />
                    <div className="flex-1 min-w-0">
                      <h3 className="font-bold text-gray-900 text-lg truncate group-hover:text-indigo-600 transition-colors">{emp.name}</h3>
                      <p className="text-xs text-gray-500 truncate">{emp.designation || 'Staff'} • {emp.department || 'General'}</p>
                    </div>
                  </div>
                  
                  {/* Stats Badges */}
                  <div className="flex gap-3">
                    <div className="flex-1 bg-gray-50 border border-gray-100 rounded-lg py-2 px-3 flex items-center justify-between group-hover:bg-white transition-colors">
                      <span className="text-[10px] font-bold text-gray-500 uppercase flex items-center gap-1">
                        <FaFileAlt className="text-indigo-400" /> Total Docs
                      </span>
                      <span className="font-black text-gray-800">{empDocs.length}</span>
                    </div>
                    <div className={`flex-1 border rounded-lg py-2 px-3 flex items-center justify-between transition-colors ${warnings.length > 0 ? 'bg-red-50 border-red-100' : 'bg-gray-50 border-gray-100 group-hover:bg-white'}`}>
                      <span className={`text-[10px] font-bold uppercase flex items-center gap-1 ${warnings.length > 0 ? 'text-red-500' : 'text-gray-400'}`}>
                        <FaExclamationTriangle className={warnings.length > 0 ? 'text-red-500' : 'text-gray-300'} /> Warnings
                      </span>
                      <span className={`font-black ${warnings.length > 0 ? 'text-red-600' : 'text-gray-400'}`}>{warnings.length}</span>
                    </div>
                  </div>
                </div>

                {/* Hover overlay hint */}
                <div className="absolute inset-0 bg-indigo-50/0 group-hover:bg-indigo-50/40 flex items-center justify-center opacity-0 group-hover:opacity-100 transition-all z-0 pointer-events-none">
                  <div className="bg-white text-indigo-600 font-bold px-4 py-2 rounded-full shadow-sm text-sm translate-y-4 group-hover:translate-y-0 transition-transform flex items-center gap-2">
                    <FaPenFancy /> Issue Document
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Full Screen Formal Document Modal Overlay */}
      <AnimatePresence>
        {isModalOpen && selectedEmp && (
          <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-gray-900/60 backdrop-blur-sm overflow-y-auto">
            <motion.div 
              initial={{ opacity: 0, scale: 0.95, y: 20 }} 
              animate={{ opacity: 1, scale: 1, y: 0 }} 
              exit={{ opacity: 0, scale: 0.95, y: 20 }} 
              className="bg-gray-100 rounded-xl shadow-2xl w-full max-w-2xl overflow-hidden relative my-auto"
            >
              {/* Modal Header Actions */}
              <div className="bg-gray-800 text-white px-4 py-3 flex justify-between items-center shadow-md z-10 relative">
                <div className="flex items-center gap-3">
                  <span className="font-bold text-sm tracking-wide">Document Management</span>
                  <div className="h-4 w-[1px] bg-gray-600"></div>
                  <span className="text-[10px] font-bold text-gray-400 uppercase tracking-widest">{selectedEmp.name}</span>
                </div>
                <button onClick={() => { setIsModalOpen(false); setSelectedDocPreview(null); setActiveTab('new'); }} className="text-gray-400 hover:text-white transition-colors bg-white/10 hover:bg-white/20 p-1.5 rounded-md">
                  <FaTimes />
                </button>
              </div>

              {/* Tabs */}
              <div className="flex bg-white border-b border-gray-200">
                <button 
                  onClick={() => { setActiveTab('new'); setSelectedDocPreview(null); }}
                  className={`flex-1 py-3 text-xs font-bold transition-all border-b-2 ${activeTab === 'new' ? 'border-indigo-600 text-indigo-700 bg-indigo-50/30' : 'border-transparent text-gray-400 hover:text-gray-600'}`}
                >
                  Issue New Document
                </button>
                <button 
                  onClick={() => setActiveTab('history')}
                  className={`flex-1 py-3 text-xs font-bold transition-all border-b-2 ${activeTab === 'history' ? 'border-indigo-600 text-indigo-700 bg-indigo-50/30' : 'border-transparent text-gray-400 hover:text-gray-600'}`}
                >
                  View History ({documents.filter(d => d.userId === selectedEmp.id).length})
                </button>
              </div>

              {/* The "Paper" Area */}
              <div className="p-4 sm:p-8 overflow-y-auto max-h-[80vh] scrollbar-hide">
                {activeTab === 'new' ? (
                  <form onSubmit={handleGenerateDocument} className="bg-white p-6 sm:p-10 rounded shadow-md border border-gray-200 relative mx-auto">
                    {/* Paper styling top accent */}
                    <div className="absolute top-0 left-0 w-full h-1.5 bg-gradient-to-r from-indigo-500 to-purple-600"></div>
                    
                    {/* Formal Document Layout */}
                    <div className="space-y-6">
                      
                      {/* Company Name Header */}
                      <div className="text-center pb-6 border-b-2 border-gray-100">
                        <input 
                          type="text" 
                          className="text-xl sm:text-2xl font-black text-center w-full outline-none uppercase tracking-[0.25em] text-gray-900 placeholder-gray-300 bg-transparent" 
                          value={formData.companyName} 
                          onChange={e => setFormData({...formData, companyName: e.target.value})} 
                          placeholder="COMPANY NAME" 
                          required 
                        />
                      </div>
                      
                      {/* Date and Type Selection */}
                      <div className="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-4 text-sm">
                        <div>
                          <label className="text-[10px] font-bold text-gray-400 uppercase block mb-1">Issue Date</label>
                          <input 
                            type="date" 
                            className="outline-none font-bold text-gray-800 bg-transparent border-b border-dashed border-gray-300 pb-1 focus:border-indigo-500 transition-colors w-full sm:w-auto" 
                            value={formData.date} 
                            onChange={e => setFormData({...formData, date: e.target.value})} 
                            required 
                          />
                        </div>
                        <div className="text-left sm:text-right">
                          <label className="text-[10px] font-bold text-gray-400 uppercase block mb-1">Document Type</label>
                          <select 
                            className="outline-none font-bold text-indigo-700 bg-indigo-50 border border-indigo-100 px-3 py-1.5 rounded-md w-full sm:w-auto focus:ring-2 focus:ring-indigo-500 cursor-pointer shadow-sm" 
                            value={formData.type} 
                            onChange={e => setFormData({...formData, type: e.target.value})} 
                            required
                          >
                            {DOCUMENT_TYPES.map(t => <option key={t.id} value={t.id}>{t.label}</option>)}
                          </select>
                        </div>
                      </div>
                      
                      {/* Subject and To */}
                      <div className="pt-4">
                        <p className="text-sm font-semibold text-gray-800 mb-6">To: <span className="font-bold text-indigo-600">{selectedEmp.name}</span></p>
                        <div className="relative bg-gray-50/50 p-3 rounded-lg border border-gray-100 focus-within:border-indigo-300 focus-within:bg-white transition-colors">
                          <span className="absolute left-3 top-1/2 -translate-y-1/2 text-sm font-bold text-gray-500 uppercase tracking-wide">Sub:</span>
                          <input 
                            type="text" 
                            placeholder="Enter official subject..." 
                            className="w-full pl-10 text-base font-bold outline-none bg-transparent text-gray-900" 
                            value={formData.subject} 
                            onChange={e => setFormData({...formData, subject: e.target.value})} 
                            required 
                          />
                        </div>
                      </div>
                      
                      {/* Body Content */}
                      <div>
                        <textarea 
                          className="w-full h-48 outline-none text-sm text-gray-700 resize-none leading-loose bg-transparent placeholder-gray-300 mt-2 p-1 border border-transparent hover:border-gray-100 focus:border-indigo-200 rounded transition-colors" 
                          placeholder="Type the formal content, reasons, conditions, or official notes here..." 
                          value={formData.content} 
                          onChange={e => setFormData({...formData, content: e.target.value})} 
                          required
                        ></textarea>
                      </div>
                      
                      {/* Sign-off */}
                      <div className="pt-6 border-t border-gray-100 w-1/2 mt-4">
                        <p className="text-[10px] font-bold text-gray-400 uppercase mb-1">Officially Issued By</p>
                        <input 
                          type="text" 
                          className="text-sm font-bold outline-none text-gray-900 bg-transparent border-b border-dashed border-gray-300 pb-1 focus:border-indigo-500 transition-colors w-full" 
                          value={formData.issuerName} 
                          onChange={e => setFormData({...formData, issuerName: e.target.value})} 
                          placeholder="Name or Department" 
                          required 
                        />
                      </div>
                      
                      {/* Submit Button */}
                      <button 
                        type="submit" 
                        disabled={isSaving} 
                        className="w-full mt-8 bg-indigo-600 text-white font-bold py-3.5 rounded-lg shadow-md hover:bg-indigo-700 transition-colors disabled:opacity-50 flex items-center justify-center gap-2 group"
                      >
                        {isSaving ? (
                          <>
                            <div className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></div>
                            Processing Document...
                          </>
                        ) : (
                          <>
                            <FaPenFancy className="group-hover:-translate-y-0.5 group-hover:translate-x-0.5 transition-transform" /> Formally Issue Document
                          </>
                        )}
                      </button>
                      
                    </div>
                  </form>
                ) : (
                  <div className="space-y-4">
                    {selectedDocPreview ? (
                      <div className="bg-white p-8 rounded-xl shadow-lg border border-gray-200 animate-fadeIn">
                        <button onClick={() => setSelectedDocPreview(null)} className="mb-4 text-xs font-bold text-indigo-600 flex items-center gap-1 hover:underline">
                          ← Back to History List
                        </button>
                        <div className="border-b border-gray-100 pb-4 mb-6">
                           <h4 className="text-xl font-black text-gray-900 uppercase tracking-wider">{DOCUMENT_TYPES.find(t => t.id === selectedDocPreview.type)?.label}</h4>
                           <p className="text-xs font-bold text-gray-400 mt-1 uppercase tracking-widest">Issued by {selectedDocPreview.issuerName} on {new Date(selectedDocPreview.createdAt).toLocaleDateString()}</p>
                        </div>
                        {selectedDocPreview.subject && (
                          <p className="text-lg font-bold text-indigo-600 mb-6 italic">Subject: {selectedDocPreview.subject}</p>
                        )}
                        <div className="text-sm text-gray-700 leading-relaxed whitespace-pre-wrap font-serif bg-gray-50/50 p-6 rounded-lg border border-gray-100">
                          {selectedDocPreview.content}
                        </div>
                        <div className="mt-8 pt-6 border-t border-gray-100 flex justify-end">
                           <button onClick={() => window.print()} className="px-6 py-2 bg-gray-800 text-white text-xs font-black rounded-lg uppercase tracking-widest hover:bg-black transition-colors">Print Copy</button>
                        </div>
                      </div>
                    ) : documents.filter(d => d.userId === selectedEmp.id).length > 0 ? (
                      <div className="grid grid-cols-1 gap-3">
                        {documents.filter(d => d.userId === selectedEmp.id).map(doc => (
                          <div 
                            key={doc.id}
                            onClick={() => setSelectedDocPreview(doc)}
                            className="bg-white p-5 rounded-2xl border border-gray-200 hover:border-indigo-400 hover:shadow-md transition-all cursor-pointer group"
                          >
                            <div className="flex justify-between items-start">
                              <div>
                                <h4 className="font-bold text-gray-900 group-hover:text-indigo-600 transition-colors">{DOCUMENT_TYPES.find(t => t.id === doc.type)?.label}</h4>
                                {doc.subject && <p className="text-xs text-gray-500 mt-0.5 italic">Sub: {doc.subject}</p>}
                                <p className="text-[10px] text-gray-400 font-bold uppercase mt-2">{new Date(doc.createdAt).toLocaleDateString()} • Issued by {doc.issuerName}</p>
                              </div>
                              <div className="p-2 bg-gray-50 rounded-lg group-hover:bg-indigo-50 transition-colors">
                                <FaFileAlt className="text-gray-300 group-hover:text-indigo-400" />
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <div className="py-20 text-center bg-white rounded-2xl border border-dashed border-gray-200">
                        <FaFileAlt className="mx-auto text-4xl text-gray-100 mb-4" />
                        <p className="text-gray-400 font-bold text-sm uppercase tracking-widest">No Documents Found</p>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </motion.div>
          </div>
        )}
      </AnimatePresence>
    </div>
  );
}
